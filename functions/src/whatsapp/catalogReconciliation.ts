import { createHash, randomBytes } from "crypto";
import { FieldPath, FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { requireBotRequest } from "../security/requestAuth";
import {
  whatsappCatalogMerchantAllowed,
  whatsappCatalogRuntimeConfig,
} from "./catalogConfig";
import {
  MerchantWhatsAppCatalogCompleteness,
  reconcileMerchantWhatsAppCatalogCompleteness,
} from "./catalogCompleteness";
import { catalogRetailerId } from "./catalogProjection";
import {
  WHATSAPP_CATALOG_MAPPINGS,
  WHATSAPP_CATALOG_OUTBOX,
  enqueueMerchantProductCatalogSync,
} from "./catalogQueue";

const RECONCILIATION_STATE_PATH =
  "whatsappCatalogSyncState/productReconciliation";
const FULL_RECONCILIATION_STATE_PATH =
  "whatsappCatalogSyncState/fullProductReconciliation";
export const WHATSAPP_CATALOG_RECONCILIATION_RUNS =
  "whatsappCatalogReconciliationRuns";
const FULL_RECONCILIATION_MAX_PAGE_SIZE = 200;

export type WhatsAppCatalogFullReconciliationPage = {
  outcome:
    | "page"
    | "product_scan_complete"
    | "scan_complete"
    | "verification_incomplete"
    | "complete";
  phase: "products" | "mappings" | "verify" | "complete";
  cycleId: string;
  inspected: number;
  queued: number;
  merchantCompleteness: MerchantWhatsAppCatalogCompleteness[];
  nextCursorPath: string | null;
  cycleComplete: boolean;
  catalogComplete: boolean;
  completeMerchants: number;
  incompleteMerchants: number;
  verificationPass: number;
  scanPass: number;
  malformedMappings: number;
  pendingOutboxJobs: number;
  stabilityVerified: boolean;
  sourceDigest: string;
  sourceCountsVerified: boolean;
  malformedMappingDigest: string;
  completionDigest?: string;
};

export class WhatsAppCatalogFullReconciliationError extends Error {
  constructor(
    public readonly code:
      | "DELIVERY_MUST_BE_DISABLED"
      | "FULL_SYNC_SCOPE_REQUIRED"
      | "RECONCILIATION_IN_PROGRESS"
      | "RECONCILIATION_CYCLE_INVALID"
      | "RECONCILIATION_CURSOR_MISMATCH",
    public readonly current?: {
      cycleId: string;
      nextCursorPath: string | null;
      phase?: "products" | "mappings" | "verify" | "complete";
    },
  ) {
    super(code);
    this.name = "WhatsAppCatalogFullReconciliationError";
  }
}

type FullReconciliationPhase = "products" | "mappings" | "verify" | "complete";

const EMPTY_SOURCE_DIGEST = "0".repeat(64);

function mappingIdentity(
  value: Record<string, unknown>,
): { merchantId: string; productId: string } | null {
  const merchantId = mappingMerchantId(value);
  const productId = text(value.productId);
  return merchantId && /^[A-Za-z0-9_-]{1,500}$/.test(productId)
    ? { merchantId, productId }
    : null;
}

function mappingReconciliationIdentity(
  documentId: string,
  value: Record<string, unknown>,
): { merchantId: string; productId: string } | null {
  const identity = mappingIdentity(value);
  if (!identity || !/^spz_[a-f0-9]{32}$/.test(documentId)) return null;
  const declaredRetailerId = text(value.retailerId) || documentId;
  return declaredRetailerId === documentId &&
    catalogRetailerId(identity.merchantId, identity.productId) === documentId
    ? identity
    : null;
}

function mappingMerchantId(value: Record<string, unknown>): string {
  const merchantId = text(value.merchantId);
  return /^[A-Za-z0-9_-]{1,200}$/.test(merchantId) ? merchantId : "";
}

function productIdentity(path: string): {
  merchantId: string;
  productId: string;
} | null {
  const parts = path.split("/");
  return parts.length === 4 && parts[0] === "users" && parts[2] === "products"
    ? { merchantId: parts[1], productId: parts[3] }
    : null;
}

async function enqueueWithConcurrency(
  products: readonly { merchantId: string; productId: string }[],
): Promise<number> {
  let next = 0;
  let queued = 0;
  const workers = Array.from(
    { length: Math.min(5, products.length) },
    async () => {
      while (next < products.length) {
        const product = products[next++];
        const result = await enqueueMerchantProductCatalogSync(product);
        if (result === "queued") queued += 1;
      }
    },
  );
  await Promise.all(workers);
  return queued;
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function boundedFullReconciliationPageSize(value: unknown): number {
  const parsed = Number(value ?? 100);
  return Number.isSafeInteger(parsed) && parsed >= 1
    ? Math.min(FULL_RECONCILIATION_MAX_PAGE_SIZE, parsed)
    : 100;
}

function scanSourceDigest(
  previous: string,
  phase: "products" | "mappings",
  documents: readonly FirebaseFirestore.QueryDocumentSnapshot[],
): string {
  const accumulator = Buffer.from(
    /^[a-f0-9]{64}$/.test(previous) ? previous : EMPTY_SOURCE_DIGEST,
    "hex",
  );
  for (const document of documents) {
    const atom = createHash("sha256")
      .update(`${phase}:${document.ref.path}:${document.updateTime.toMillis()}`)
      .digest();
    for (let index = 0; index < accumulator.length; index += 1) {
      accumulator[index] ^= atom[index];
    }
  }
  return accumulator.toString("hex");
}

function malformedMappingDigest(
  previous: string,
  documents: readonly FirebaseFirestore.QueryDocumentSnapshot[],
): string {
  const accumulator = Buffer.from(
    /^[a-f0-9]{64}$/.test(previous) ? previous : EMPTY_SOURCE_DIGEST,
    "hex",
  );
  for (const document of documents) {
    const value = document.data();
    const atom = createHash("sha256")
      .update(
        JSON.stringify([
          document.id,
          text(value.merchantId),
          text(value.productId),
          text(value.retailerId),
          text(value.status),
        ]),
      )
      .digest();
    for (let index = 0; index < accumulator.length; index += 1) {
      accumulator[index] ^= atom[index];
    }
  }
  return accumulator.toString("hex");
}

async function commitRunTransition(
  stateRef: FirebaseFirestore.DocumentReference,
  runRef: FirebaseFirestore.DocumentReference,
  value: Record<string, unknown>,
): Promise<void> {
  const batch = db.batch();
  batch.set(stateRef, value, { merge: true });
  batch.set(runRef, value, { merge: true });
  await batch.commit();
}

async function globalSourceEvidence(): Promise<{
  productDocuments: number;
  mappingDocuments: number;
  pendingOutboxJobs: number;
}> {
  const [products, mappings, pendingOutbox] = await Promise.all([
    db.collectionGroup("products").count().get(),
    db.collection(WHATSAPP_CATALOG_MAPPINGS).count().get(),
    db
      .collection(WHATSAPP_CATALOG_OUTBOX)
      .where("status", "in", ["pending", "retry", "processing", "submitted"])
      .count()
      .get(),
  ]);
  return {
    productDocuments: Number(products.data().count ?? 0),
    mappingDocuments: Number(mappings.data().count ?? 0),
    pendingOutboxJobs: Number(pendingOutbox.data().count ?? 0),
  };
}

async function completenessWithConcurrency(
  merchantIds: readonly string[],
): Promise<MerchantWhatsAppCatalogCompleteness[]> {
  const results: MerchantWhatsAppCatalogCompleteness[] = [];
  let next = 0;
  const workers = Array.from(
    { length: Math.min(5, merchantIds.length) },
    async () => {
      while (next < merchantIds.length) {
        const merchantId = merchantIds[next++];
        results.push(
          await reconcileMerchantWhatsAppCatalogCompleteness(merchantId),
        );
      }
    },
  );
  await Promise.all(workers);
  return results.sort((a, b) => a.merchantId.localeCompare(b.merchantId));
}

function currentRunState(value: Record<string, unknown>): {
  cycleId: string;
  cursorPath: string;
  status: string;
  phase: FullReconciliationPhase;
  totalInspected: number;
  totalQueued: number;
  pages: number;
  verificationPass: number;
  scanPass: number;
  scanProductDocuments: number;
  scanMappingDocuments: number;
  scanQueued: number;
  malformedMappings: number;
  scanSourceDigest: string;
  malformedMappingDigest: string;
  verifiedSourceDigest: string;
  verifiedProductDocuments: number;
  verifiedMappingDocuments: number;
  verifiedCompletionDigest: string;
  verifiedCompleteMerchants: number;
  verifiedEligibleProducts: number;
  verifiedActiveAcceptedProducts: number;
  stableVerificationSourceDigest: string;
  stableVerificationMerchantDigest: string;
} {
  const phase = text(value.phase);
  return {
    cycleId: text(value.cycleId),
    cursorPath: text(value.cursorPath),
    status: text(value.status),
    phase: ["products", "mappings", "verify", "complete"].includes(phase)
      ? (phase as FullReconciliationPhase)
      : "products",
    totalInspected: Number(value.totalInspected ?? 0),
    totalQueued: Number(value.totalQueued ?? 0),
    pages: Number(value.pages ?? 0),
    verificationPass: Number(value.verificationPass ?? 0),
    scanPass: Math.max(1, Number(value.scanPass ?? 1)),
    scanProductDocuments: Number(value.scanProductDocuments ?? 0),
    scanMappingDocuments: Number(value.scanMappingDocuments ?? 0),
    scanQueued: Number(value.scanQueued ?? 0),
    malformedMappings: Number(value.malformedMappings ?? 0),
    scanSourceDigest: text(value.scanSourceDigest) || EMPTY_SOURCE_DIGEST,
    malformedMappingDigest:
      text(value.malformedMappingDigest) || EMPTY_SOURCE_DIGEST,
    verifiedSourceDigest: text(value.verifiedSourceDigest),
    verifiedProductDocuments: Number(value.verifiedProductDocuments ?? 0),
    verifiedMappingDocuments: Number(value.verifiedMappingDocuments ?? 0),
    verifiedCompletionDigest: text(value.verifiedCompletionDigest),
    verifiedCompleteMerchants: Number(value.verifiedCompleteMerchants ?? 0),
    verifiedEligibleProducts: Number(value.verifiedEligibleProducts ?? 0),
    verifiedActiveAcceptedProducts: Number(
      value.verifiedActiveAcceptedProducts ?? 0,
    ),
    stableVerificationSourceDigest: text(value.stableVerificationSourceDigest),
    stableVerificationMerchantDigest: text(
      value.stableVerificationMerchantDigest,
    ),
  };
}

function reconciliationCompletionDigest(
  summaries: readonly MerchantWhatsAppCatalogCompleteness[],
): string {
  const receipt = [...summaries]
    .sort((a, b) => a.merchantId.localeCompare(b.merchantId))
    .map(
      (summary) =>
        `${summary.merchantId}:${summary.eligibleSetDigest}:${summary.activeAcceptedSetDigest}`,
    )
    .join("\n");
  return createHash("sha256").update(receipt).digest("hex");
}

function stabilizedCompletionDigest(input: {
  merchantSetDigest: string;
  sourceDigest: string;
  productDocuments: number;
  mappingDocuments: number;
}): string {
  return createHash("sha256")
    .update(
      JSON.stringify({
        merchantSetDigest: input.merchantSetDigest,
        sourceDigest: input.sourceDigest,
        productDocuments: input.productDocuments,
        mappingDocuments: input.mappingDocuments,
        malformedMappings: 0,
        pendingOutboxJobs: 0,
      }),
    )
    .digest("hex");
}

/**
 * One resumable product page for an operator-started all-merchant backfill.
 * The server owns the cursor and rejects stale resumes. Replaying a page before
 * its cursor commits is safe because catalogue enqueueing is revision-idempotent.
 */
export async function runWhatsAppCatalogFullReconciliationPage(input: {
  cycleId?: string;
  cursorPath?: string;
  pageSize?: number;
}): Promise<WhatsAppCatalogFullReconciliationPage> {
  const config = whatsappCatalogRuntimeConfig();
  if (
    !config.queueEnabled ||
    !config.syncEnabled ||
    !config.fullRolloutEnabled
  ) {
    throw new WhatsAppCatalogFullReconciliationError(
      "FULL_SYNC_SCOPE_REQUIRED",
    );
  }
  if (
    String(process.env.WHATSAPP_PRODUCT_LIST_ENABLED ?? "")
      .trim()
      .toLowerCase() === "true"
  ) {
    throw new WhatsAppCatalogFullReconciliationError(
      "DELIVERY_MUST_BE_DISABLED",
    );
  }

  const pageSize = boundedFullReconciliationPageSize(input.pageSize);
  const stateRef = db.doc(FULL_RECONCILIATION_STATE_PATH);
  const stateDocument = await stateRef.get();
  let state = currentRunState(stateDocument.data() ?? {});
  const requestedCycleId = text(input.cycleId);
  const requestedCursorPath = text(input.cursorPath);

  if (!requestedCycleId) {
    if (state.status === "running" && state.cycleId) {
      throw new WhatsAppCatalogFullReconciliationError(
        "RECONCILIATION_IN_PROGRESS",
        {
          cycleId: state.cycleId,
          nextCursorPath: state.cursorPath || null,
          phase: state.phase,
        },
      );
    }
    const cycleId = randomBytes(16).toString("hex");
    state = {
      cycleId,
      cursorPath: "",
      status: "running",
      phase: "products",
      totalInspected: 0,
      totalQueued: 0,
      pages: 0,
      verificationPass: 0,
      scanPass: 1,
      scanProductDocuments: 0,
      scanMappingDocuments: 0,
      scanQueued: 0,
      malformedMappings: 0,
      scanSourceDigest: EMPTY_SOURCE_DIGEST,
      malformedMappingDigest: EMPTY_SOURCE_DIGEST,
      verifiedSourceDigest: "",
      verifiedProductDocuments: 0,
      verifiedMappingDocuments: 0,
      verifiedCompletionDigest: "",
      verifiedCompleteMerchants: 0,
      verifiedEligibleProducts: 0,
      verifiedActiveAcceptedProducts: 0,
      stableVerificationSourceDigest: "",
      stableVerificationMerchantDigest: "",
    };
    const initialState = {
      ...state,
      cursorPath: null,
      catalogComplete: false,
      completionDigest: null,
      stabilityVerified: false,
      sourceCountsVerified: false,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      updatedAtMs: Date.now(),
      schemaVersion: 1,
    };
    const initialRunRef = db.doc(
      `${WHATSAPP_CATALOG_RECONCILIATION_RUNS}/${cycleId}`,
    );
    const batch = db.batch();
    batch.set(stateRef, initialState, { merge: true });
    batch.set(
      initialRunRef,
      {
        ...initialState,
        pageSize,
      },
      { merge: true },
    );
    await batch.commit();
  } else {
    if (!/^[a-f0-9]{32}$/.test(requestedCycleId)) {
      throw new WhatsAppCatalogFullReconciliationError(
        "RECONCILIATION_CYCLE_INVALID",
      );
    }
    if (state.cycleId !== requestedCycleId) {
      throw new WhatsAppCatalogFullReconciliationError(
        "RECONCILIATION_CYCLE_INVALID",
        state.cycleId
          ? {
              cycleId: state.cycleId,
              nextCursorPath: state.cursorPath || null,
              phase: state.phase,
            }
          : undefined,
      );
    }
    if (state.status === "complete") {
      const run = await db
        .doc(`${WHATSAPP_CATALOG_RECONCILIATION_RUNS}/${state.cycleId}`)
        .get();
      return {
        outcome: "complete",
        phase: "complete",
        cycleId: state.cycleId,
        inspected: 0,
        queued: 0,
        merchantCompleteness: [],
        nextCursorPath: null,
        cycleComplete: true,
        catalogComplete: run.data()?.catalogComplete === true,
        completeMerchants: Number(run.data()?.completeMerchants ?? 0),
        incompleteMerchants: Number(run.data()?.incompleteMerchants ?? 0),
        verificationPass: Number(run.data()?.verificationPass ?? 0),
        scanPass: Number(run.data()?.scanPass ?? 0),
        malformedMappings: Number(run.data()?.malformedMappings ?? 0),
        pendingOutboxJobs: Number(run.data()?.pendingOutboxJobs ?? 0),
        stabilityVerified: run.data()?.stabilityVerified === true,
        sourceDigest: text(run.data()?.sourceDigest),
        sourceCountsVerified: run.data()?.sourceCountsVerified === true,
        malformedMappingDigest:
          text(run.data()?.malformedMappingDigest) || EMPTY_SOURCE_DIGEST,
        ...(text(run.data()?.completionDigest)
          ? { completionDigest: text(run.data()?.completionDigest) }
          : {}),
      };
    }
    if (state.status !== "running") {
      throw new WhatsAppCatalogFullReconciliationError(
        "RECONCILIATION_CYCLE_INVALID",
      );
    }
    if (requestedCursorPath !== state.cursorPath) {
      throw new WhatsAppCatalogFullReconciliationError(
        "RECONCILIATION_CURSOR_MISMATCH",
        {
          cycleId: state.cycleId,
          nextCursorPath: state.cursorPath || null,
          phase: state.phase,
        },
      );
    }
  }

  const runRef = db.doc(
    `${WHATSAPP_CATALOG_RECONCILIATION_RUNS}/${state.cycleId}`,
  );

  if (state.phase === "products" || state.phase === "mappings") {
    let query =
      state.phase === "products"
        ? db
            .collectionGroup("products")
            .orderBy(FieldPath.documentId())
            .limit(pageSize + 1)
        : db
            .collection(WHATSAPP_CATALOG_MAPPINGS)
            .orderBy(FieldPath.documentId())
            .limit(pageSize + 1);
    if (state.cursorPath) {
      query =
        state.phase === "products"
          ? query.startAfter(db.doc(state.cursorPath))
          : query.startAfter(state.cursorPath);
    }
    const snapshot = await query.get();
    const pageDocuments = snapshot.docs.slice(0, pageSize);
    const identities = pageDocuments
      .map((document) =>
        state.phase === "products"
          ? productIdentity(document.ref.path)
          : mappingReconciliationIdentity(document.id, document.data()),
      )
      .filter(
        (item): item is { merchantId: string; productId: string } =>
          item !== null,
      );
    const malformedMappingDocuments =
      state.phase === "mappings"
        ? pageDocuments.filter(
            (document) =>
              mappingReconciliationIdentity(document.id, document.data()) ===
              null,
          )
        : [];
    const pageMalformedMappings = malformedMappingDocuments.length;
    const queued = await enqueueWithConcurrency(identities);
    // A corrupt/missing productId must not hide an otherwise valid merchant
    // from the reverse scan. Only valid identities are enqueued, but every
    // valid merchant owner is marked so exact-set verification exposes and
    // blocks the unexpected active mapping until it is repaired or removed.
    const merchantIds = [
      ...new Set(
        state.phase === "products"
          ? identities.map((item) => item.merchantId)
          : pageDocuments
              .map((document) => mappingMerchantId(document.data()))
              .filter(Boolean),
      ),
    ];
    await Promise.all(
      merchantIds.map((merchantId) =>
        runRef
          .collection("merchants")
          .doc(merchantId)
          .set(
            {
              merchantId,
              ...(state.phase === "products"
                ? { discoveredFromProducts: true }
                : { discoveredFromMappings: true }),
              lastSeenScanPass: state.scanPass,
              discoveredAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          ),
      ),
    );
    const scanPageComplete = snapshot.docs.length <= pageSize;
    const last = pageDocuments[pageDocuments.length - 1];
    const nextPhase: FullReconciliationPhase = scanPageComplete
      ? state.phase === "products"
        ? "mappings"
        : "verify"
      : state.phase;
    const nextCursorPath = scanPageComplete
      ? null
      : state.phase === "products"
        ? (last?.ref.path ?? null)
        : (last?.id ?? null);
    const nextState = {
      cycleId: state.cycleId,
      status: "running",
      phase: nextPhase,
      cursorPath: nextCursorPath,
      totalInspected: state.totalInspected + pageDocuments.length,
      totalQueued: state.totalQueued + queued,
      pages: state.pages + 1,
      scanPass: state.scanPass,
      scanProductDocuments:
        state.scanProductDocuments +
        (state.phase === "products" ? pageDocuments.length : 0),
      scanMappingDocuments:
        state.scanMappingDocuments +
        (state.phase === "mappings" ? pageDocuments.length : 0),
      scanQueued: state.scanQueued + queued,
      malformedMappings: state.malformedMappings + pageMalformedMappings,
      scanSourceDigest: scanSourceDigest(
        state.scanSourceDigest,
        state.phase,
        pageDocuments,
      ),
      malformedMappingDigest: malformedMappingDigest(
        state.malformedMappingDigest,
        malformedMappingDocuments,
      ),
      verificationPass:
        nextPhase === "verify" ? Math.max(1, state.verificationPass) : 0,
      catalogComplete: false,
      stabilityVerified: false,
      sourceCountsVerified: false,
      completeMerchants: 0,
      incompleteMerchants: 0,
      ...(state.phase === "products" && scanPageComplete
        ? { productScanCompletedAt: FieldValue.serverTimestamp() }
        : {}),
      ...(state.phase === "mappings" && scanPageComplete
        ? { scanCompletedAt: FieldValue.serverTimestamp() }
        : {}),
      updatedAt: FieldValue.serverTimestamp(),
      updatedAtMs: Date.now(),
      schemaVersion: 1,
    };
    await commitRunTransition(stateRef, runRef, nextState);
    return {
      outcome: scanPageComplete
        ? state.phase === "products"
          ? "product_scan_complete"
          : "scan_complete"
        : "page",
      phase: nextPhase,
      cycleId: state.cycleId,
      inspected: pageDocuments.length,
      queued,
      merchantCompleteness: [],
      nextCursorPath,
      cycleComplete: false,
      catalogComplete: false,
      completeMerchants: 0,
      incompleteMerchants: 0,
      verificationPass: nextState.verificationPass,
      scanPass: state.scanPass,
      malformedMappings: nextState.malformedMappings,
      pendingOutboxJobs: 0,
      stabilityVerified: false,
      sourceDigest: nextState.scanSourceDigest,
      sourceCountsVerified: false,
      malformedMappingDigest: nextState.malformedMappingDigest,
    };
  }

  const verificationPass = Math.max(1, state.verificationPass);
  const sameAsVerifiedSource =
    state.scanPass >= 2 &&
    state.scanQueued === 0 &&
    state.malformedMappings === 0 &&
    /^[a-f0-9]{64}$/.test(state.verifiedSourceDigest) &&
    state.scanSourceDigest === state.verifiedSourceDigest &&
    state.scanProductDocuments === state.verifiedProductDocuments &&
    state.scanMappingDocuments === state.verifiedMappingDocuments;
  let merchantQuery = runRef
    .collection("merchants")
    .where("lastSeenScanPass", "==", state.scanPass)
    .orderBy(FieldPath.documentId())
    .limit(pageSize + 1);
  if (state.cursorPath)
    merchantQuery = merchantQuery.startAfter(state.cursorPath);
  const merchantSnapshot = await merchantQuery.get();
  const merchantPage = merchantSnapshot.docs.slice(0, pageSize);
  const merchantCompleteness = await completenessWithConcurrency(
    merchantPage.map((document) => document.id),
  );
  await Promise.all(
    merchantCompleteness.map((summary) =>
      runRef
        .collection("merchants")
        .doc(summary.merchantId)
        .set(
          {
            ...summary,
            verificationPass,
            checkedAt: FieldValue.serverTimestamp(),
            checkedAtMs: Date.now(),
          },
          { merge: true },
        ),
    ),
  );
  const verificationPageComplete = merchantSnapshot.docs.length <= pageSize;
  const lastMerchant = merchantPage[merchantPage.length - 1];
  if (!verificationPageComplete) {
    const nextCursorPath = lastMerchant?.id ?? null;
    const nextState = {
      cycleId: state.cycleId,
      status: "running",
      phase: "verify",
      cursorPath: nextCursorPath,
      totalInspected: state.totalInspected + merchantPage.length,
      totalQueued: state.totalQueued,
      pages: state.pages + 1,
      verificationPass,
      scanPass: state.scanPass,
      scanProductDocuments: state.scanProductDocuments,
      scanMappingDocuments: state.scanMappingDocuments,
      scanQueued: state.scanQueued,
      malformedMappings: state.malformedMappings,
      scanSourceDigest: state.scanSourceDigest,
      malformedMappingDigest: state.malformedMappingDigest,
      catalogComplete: false,
      stabilityVerified: false,
      sourceCountsVerified: false,
      updatedAt: FieldValue.serverTimestamp(),
      updatedAtMs: Date.now(),
      schemaVersion: 1,
    };
    await commitRunTransition(stateRef, runRef, nextState);
    return {
      outcome: "page",
      phase: "verify",
      cycleId: state.cycleId,
      inspected: merchantPage.length,
      queued: 0,
      merchantCompleteness,
      nextCursorPath,
      cycleComplete: false,
      catalogComplete: false,
      completeMerchants: 0,
      incompleteMerchants: 0,
      verificationPass,
      scanPass: state.scanPass,
      malformedMappings: state.malformedMappings,
      pendingOutboxJobs: merchantCompleteness.reduce(
        (sum, summary) => sum + summary.pendingOutboxJobs,
        0,
      ),
      stabilityVerified: false,
      sourceDigest: state.scanSourceDigest,
      sourceCountsVerified: false,
      malformedMappingDigest: state.malformedMappingDigest,
    };
  }

  const allMerchantDocuments = await runRef
    .collection("merchants")
    .where("lastSeenScanPass", "==", state.scanPass)
    .get();
  const verifiedSummaries = allMerchantDocuments.docs
    .filter(
      (document) =>
        Number(document.data().verificationPass) === verificationPass,
    )
    .map(
      (document) =>
        document.data() as MerchantWhatsAppCatalogCompleteness & {
          verificationPass: number;
        },
    );
  const completeMerchants = verifiedSummaries.filter(
    (summary) => summary.complete,
  ).length;
  const incompleteMerchants = allMerchantDocuments.size - completeMerchants;
  const merchantSetComplete =
    verifiedSummaries.length === allMerchantDocuments.size &&
    incompleteMerchants === 0;
  const merchantSetDigest = merchantSetComplete
    ? reconciliationCompletionDigest(verifiedSummaries)
    : "";
  const eligibleProducts = verifiedSummaries.reduce(
    (sum, summary) => sum + summary.eligibleProducts,
    0,
  );
  const activeAcceptedProducts = verifiedSummaries.reduce(
    (sum, summary) => sum + summary.activeAcceptedProducts,
    0,
  );
  const evidence = await globalSourceEvidence();
  const sourceCountsCurrent =
    evidence.productDocuments === state.scanProductDocuments &&
    evidence.mappingDocuments === state.scanMappingDocuments;
  const catalogComplete =
    merchantSetComplete &&
    sameAsVerifiedSource &&
    merchantSetDigest === state.verifiedCompletionDigest &&
    state.stableVerificationSourceDigest === state.scanSourceDigest &&
    state.stableVerificationMerchantDigest === merchantSetDigest &&
    state.malformedMappings === 0 &&
    evidence.pendingOutboxJobs === 0 &&
    sourceCountsCurrent;
  if (catalogComplete) {
    const completionDigest = stabilizedCompletionDigest({
      merchantSetDigest,
      sourceDigest: state.scanSourceDigest,
      productDocuments: state.scanProductDocuments,
      mappingDocuments: state.scanMappingDocuments,
    });
    const completedState = {
      cycleId: state.cycleId,
      status: "complete",
      phase: "complete",
      cursorPath: null,
      totalInspected: state.totalInspected + merchantPage.length,
      totalQueued: state.totalQueued,
      pages: state.pages + 1,
      verificationPass,
      scanPass: state.scanPass,
      scanProductDocuments: state.scanProductDocuments,
      scanMappingDocuments: state.scanMappingDocuments,
      scanQueued: state.scanQueued,
      sourceDigest: state.scanSourceDigest,
      scanSourceDigest: state.scanSourceDigest,
      malformedMappings: 0,
      malformedMappingDigest: EMPTY_SOURCE_DIGEST,
      pendingOutboxJobs: 0,
      outboxDrained: true,
      sourceCountsVerified: true,
      stabilityVerified: true,
      catalogComplete: true,
      setEqualityVerified: true,
      completeMerchants,
      incompleteMerchants: 0,
      eligibleProducts,
      activeAcceptedProducts,
      merchantSetDigest,
      completionDigest,
      cycleCompletedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      updatedAtMs: Date.now(),
      schemaVersion: 1,
    };
    await commitRunTransition(stateRef, runRef, completedState);
    return {
      outcome: "complete",
      phase: "complete",
      cycleId: state.cycleId,
      inspected: merchantPage.length,
      queued: 0,
      merchantCompleteness,
      nextCursorPath: null,
      cycleComplete: true,
      catalogComplete: true,
      completeMerchants,
      incompleteMerchants: 0,
      verificationPass,
      scanPass: state.scanPass,
      malformedMappings: 0,
      pendingOutboxJobs: 0,
      stabilityVerified: true,
      sourceDigest: state.scanSourceDigest,
      sourceCountsVerified: true,
      malformedMappingDigest: EMPTY_SOURCE_DIGEST,
      completionDigest,
    };
  }
  const cleanMerchantVerification =
    merchantSetComplete &&
    state.malformedMappings === 0 &&
    evidence.pendingOutboxJobs === 0 &&
    sourceCountsCurrent;
  const matchesVerifiedBaseline =
    cleanMerchantVerification &&
    sameAsVerifiedSource &&
    merchantSetDigest === state.verifiedCompletionDigest;
  const establishStabilityBarrier =
    cleanMerchantVerification && !matchesVerifiedBaseline;
  const recordStableVerification =
    matchesVerifiedBaseline &&
    !(
      state.stableVerificationSourceDigest === state.scanSourceDigest &&
      state.stableVerificationMerchantDigest === merchantSetDigest
    );
  const requiresSourceRefresh =
    establishStabilityBarrier ||
    state.malformedMappings > 0 ||
    !sourceCountsCurrent ||
    (sameAsVerifiedSource && !merchantSetComplete);
  const nextVerificationPass = verificationPass + 1;
  const nextState = {
    cycleId: state.cycleId,
    status: "running",
    phase: requiresSourceRefresh ? "products" : "verify",
    cursorPath: null,
    totalInspected: state.totalInspected + merchantPage.length,
    totalQueued: state.totalQueued,
    pages: state.pages + 1,
    verificationPass: nextVerificationPass,
    scanPass: requiresSourceRefresh ? state.scanPass + 1 : state.scanPass,
    scanProductDocuments: requiresSourceRefresh
      ? 0
      : state.scanProductDocuments,
    scanMappingDocuments: requiresSourceRefresh
      ? 0
      : state.scanMappingDocuments,
    scanQueued: requiresSourceRefresh ? 0 : state.scanQueued,
    scanSourceDigest: requiresSourceRefresh
      ? EMPTY_SOURCE_DIGEST
      : state.scanSourceDigest,
    malformedMappings: requiresSourceRefresh ? 0 : state.malformedMappings,
    malformedMappingDigest: requiresSourceRefresh
      ? EMPTY_SOURCE_DIGEST
      : state.malformedMappingDigest,
    catalogComplete: false,
    setEqualityVerified: merchantSetComplete,
    stabilityVerified: false,
    sourceCountsVerified: sourceCountsCurrent,
    completeMerchants,
    incompleteMerchants,
    eligibleProducts,
    activeAcceptedProducts,
    pendingOutboxJobs: evidence.pendingOutboxJobs,
    completionDigest: null,
    ...(establishStabilityBarrier
      ? {
          verifiedSourceDigest: state.scanSourceDigest,
          verifiedProductDocuments: state.scanProductDocuments,
          verifiedMappingDocuments: state.scanMappingDocuments,
          verifiedCompletionDigest: merchantSetDigest,
          verifiedCompleteMerchants: completeMerchants,
          verifiedEligibleProducts: eligibleProducts,
          verifiedActiveAcceptedProducts: activeAcceptedProducts,
          stableVerificationSourceDigest: "",
          stableVerificationMerchantDigest: "",
          stabilityBarrierEstablishedAt: FieldValue.serverTimestamp(),
        }
      : {}),
    ...(recordStableVerification
      ? {
          stableVerificationSourceDigest: state.scanSourceDigest,
          stableVerificationMerchantDigest: merchantSetDigest,
          stableVerificationPass: verificationPass,
          stableVerificationRecordedAt: FieldValue.serverTimestamp(),
        }
      : {}),
    verificationIncompleteAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    updatedAtMs: Date.now(),
    schemaVersion: 1,
  };
  await commitRunTransition(stateRef, runRef, nextState);
  return {
    outcome: "verification_incomplete",
    phase: requiresSourceRefresh ? "products" : "verify",
    cycleId: state.cycleId,
    inspected: merchantPage.length,
    queued: 0,
    merchantCompleteness,
    nextCursorPath: null,
    cycleComplete: false,
    catalogComplete: false,
    completeMerchants,
    incompleteMerchants,
    verificationPass: nextVerificationPass,
    scanPass: nextState.scanPass,
    malformedMappings: state.malformedMappings,
    pendingOutboxJobs: evidence.pendingOutboxJobs,
    stabilityVerified: false,
    sourceDigest: state.scanSourceDigest,
    sourceCountsVerified: sourceCountsCurrent,
    malformedMappingDigest: state.malformedMappingDigest,
  };
}

/** Authenticated operator path; it is physically blocked while delivery is on. */
export const runWhatsAppCatalogFullReconciliationBotHttp = functions
  .runWith({
    secrets: ["PASELLA_BOT_TOKEN"],
    timeoutSeconds: 540,
    memory: "512MB",
    maxInstances: 1,
  })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    if (req.method !== "POST") {
      res.status(405).json({
        outcome: "rejected",
        reason: "method_not_allowed",
        code: "METHOD_NOT_ALLOWED",
      });
      return;
    }
    try {
      const result = await runWhatsAppCatalogFullReconciliationPage({
        cycleId: req.body?.cycleId,
        cursorPath: req.body?.cursorPath,
        pageSize: req.body?.pageSize,
      });
      res.status(200).json(result);
    } catch (error) {
      if (error instanceof WhatsAppCatalogFullReconciliationError) {
        res.status(error.code.includes("REQUIRED") ? 503 : 409).json({
          outcome: "rejected",
          reason: error.code.toLowerCase(),
          code: error.code,
          ...(error.current ?? {}),
        });
        return;
      }
      console.error("[whatsapp-catalog-reconciliation] page failed", {
        code: error instanceof Error ? error.name : "UNKNOWN",
      });
      res.status(500).json({
        outcome: "rejected",
        reason: "reconciliation_failed",
        code: "RECONCILIATION_FAILED",
      });
    }
  });

export async function runWhatsAppCatalogReconciliationOnce(
  limit = 200,
): Promise<{ disabled: boolean; inspected: number; queued: number }> {
  const config = whatsappCatalogRuntimeConfig();
  if (
    !config.queueEnabled ||
    (config.environment === "production" && !config.syncEnabled)
  ) {
    return { disabled: true, inspected: 0, queued: 0 };
  }
  const stateRef = db.doc(RECONCILIATION_STATE_PATH);
  const state = await stateRef.get();
  const cursorPath = String(state.data()?.cursorPath ?? "").trim();
  const pageLimit = Math.max(1, Math.min(500, limit));
  let query = db
    .collectionGroup("products")
    .orderBy(FieldPath.documentId())
    .limit(pageLimit);
  if (cursorPath) query = query.startAfter(db.doc(cursorPath));
  const snapshot = await query.get();
  const identities = snapshot.docs
    .map((doc) => productIdentity(doc.ref.path))
    .filter(
      (item): item is { merchantId: string; productId: string } =>
        item !== null,
    )
    .filter(
      (item) =>
        !config.syncEnabled ||
        whatsappCatalogMerchantAllowed(config, item.merchantId),
    );
  const queued = await enqueueWithConcurrency(identities);
  const last = snapshot.docs[snapshot.docs.length - 1];
  const cycleComplete = snapshot.empty || snapshot.size < pageLimit;
  await stateRef.set(
    {
      cursorPath: cycleComplete ? null : last.ref.path,
      lastInspected: snapshot.size,
      lastQueued: queued,
      ...(cycleComplete
        ? { cycleCompletedAt: FieldValue.serverTimestamp() }
        : {}),
      updatedAt: FieldValue.serverTimestamp(),
      updatedAtMs: Date.now(),
      schemaVersion: 1,
    },
    { merge: true },
  );
  return { disabled: false, inspected: snapshot.size, queued };
}

/** Safety net for missed triggers; product writes still enqueue immediately. */
export const reconcileWhatsAppMerchantCatalog = functions
  .runWith({ timeoutSeconds: 240, memory: "512MB", maxInstances: 1 })
  .pubsub.schedule("every 24 hours")
  .timeZone("Africa/Johannesburg")
  .onRun(() => runWhatsAppCatalogReconciliationOnce());
