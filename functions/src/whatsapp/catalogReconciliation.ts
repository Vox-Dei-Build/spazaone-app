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
import {
  assertWhatsAppCatalogDeploymentBinding,
  WhatsAppCatalogDeploymentBinding,
} from "./catalogProductionTarget";

const RECONCILIATION_STATE_PATH =
  "whatsappCatalogSyncState/productReconciliation";
const FULL_RECONCILIATION_STATE_PATH =
  "whatsappCatalogSyncState/fullProductReconciliation";
const RECONCILIATION_RUN_CLEANUP_STATE_PATH =
  "whatsappCatalogSyncState/reconciliationRunCleanup";
export const WHATSAPP_CATALOG_RECONCILIATION_RUNS =
  "whatsappCatalogReconciliationRuns";
const FULL_RECONCILIATION_MAX_PAGE_SIZE = 200;
export const WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS = 5 * 60 * 1000;
// A terminal proof reads at most this many minimal source documents plus one
// overflow sentinel. Beyond this bound the operation fails closed instead of
// attempting an unbounded Firestore transaction. Raising this limit requires
// an explicit scale test or a chunked epoch design.
export const WHATSAPP_CATALOG_MAX_GENERATION_DOCUMENTS = 5_000;
export const WHATSAPP_CATALOG_RECONCILIATION_RUN_RETENTION_MS =
  90 * 24 * 60 * 60 * 1_000;
export const WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_MAX_RUN_INSPECTIONS = 25;
export const WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_MAX_RUN_DELETES = 10;
export const WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_MAX_MARKER_DELETES = 200;
const WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_MARKER_BATCH_SIZE = 100;
const WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_LEASE_MS = 10 * 60 * 1_000;

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
  totalOutboxDocuments?: number;
  outboxCountsVerified?: boolean;
  outboxStatusCounts?: WhatsAppCatalogOutboxStatusCounts;
  stabilityVerified: boolean;
  sourceDigest: string;
  sourceCountsVerified: boolean;
  malformedMappingDigest: string;
  completionDigest?: string;
  mutationGenerationDigestSha256?: string;
  cycleStartedAt?: string;
  cycleCompletedAt?: string;
};

export type WhatsAppCatalogOutboxStatusCounts = {
  pending: number;
  retry: number;
  processing: number;
  submitted: number;
  active: number;
  deleted: number;
  rejected: number;
  blocked: number;
  failed: number;
  unknown: number;
};

export function summarizeWhatsAppCatalogOutboxEvidence(input: {
  total: number;
  pending: number;
  retry: number;
  processing: number;
  submitted: number;
  active: number;
  deleted: number;
  rejected: number;
  blocked: number;
  failed: number;
}): {
  pendingOutboxJobs: number;
  totalOutboxDocuments: number;
  outboxCountsVerified: boolean;
  outboxStatusCounts: WhatsAppCatalogOutboxStatusCounts;
} {
  if (
    Object.values(input).some(
      (count) => !Number.isSafeInteger(count) || count < 0,
    )
  ) {
    throw new Error("WHATSAPP_CATALOG_OUTBOX_COUNT_INVALID");
  }
  const pendingOutboxJobs =
    input.pending + input.retry + input.processing + input.submitted;
  const knownOutboxDocuments =
    pendingOutboxJobs +
    input.active +
    input.deleted +
    input.rejected +
    input.blocked +
    input.failed;
  const unknown = Math.max(0, input.total - knownOutboxDocuments);
  return {
    pendingOutboxJobs,
    totalOutboxDocuments: input.total,
    outboxCountsVerified: knownOutboxDocuments === input.total,
    outboxStatusCounts: {
      pending: input.pending,
      retry: input.retry,
      processing: input.processing,
      submitted: input.submitted,
      active: input.active,
      deleted: input.deleted,
      rejected: input.rejected,
      blocked: input.blocked,
      failed: input.failed,
      unknown,
    },
  };
}

const OUTBOX_STATUS_KEYS: readonly (keyof WhatsAppCatalogOutboxStatusCounts)[] =
  [
    "pending",
    "retry",
    "processing",
    "submitted",
    "active",
    "deleted",
    "rejected",
    "blocked",
    "failed",
    "unknown",
  ];

function exactDrainedOutboxEvidence(
  counts: WhatsAppCatalogOutboxStatusCounts | undefined,
  total: number,
  verified: unknown,
): boolean {
  if (
    verified !== true ||
    !counts ||
    !Number.isSafeInteger(total) ||
    total < 0 ||
    JSON.stringify(Object.keys(counts).sort()) !==
      JSON.stringify([...OUTBOX_STATUS_KEYS].sort()) ||
    OUTBOX_STATUS_KEYS.some(
      (key) => !Number.isSafeInteger(counts[key]) || counts[key] < 0,
    )
  ) {
    return false;
  }
  return (
    counts.pending === 0 &&
    counts.retry === 0 &&
    counts.processing === 0 &&
    counts.submitted === 0 &&
    counts.unknown === 0 &&
    OUTBOX_STATUS_KEYS.reduce((sum, key) => sum + counts[key], 0) === total
  );
}

function sameOutboxStatusCounts(
  left: WhatsAppCatalogOutboxStatusCounts | undefined,
  right: WhatsAppCatalogOutboxStatusCounts | undefined,
): boolean {
  return (
    !!left &&
    !!right &&
    OUTBOX_STATUS_KEYS.every((key) => left[key] === right[key])
  );
}

export type WhatsAppCatalogFullReconciliationResponse =
  WhatsAppCatalogFullReconciliationPage & WhatsAppCatalogDeploymentBinding;

export type WhatsAppCatalogOperatorReconciliationPage = Omit<
  WhatsAppCatalogFullReconciliationResponse,
  "merchantCompleteness" | "nextCursorPath"
> & {
  continuationStateDigestSha256?: string;
};

export class WhatsAppCatalogFullReconciliationError extends Error {
  constructor(
    public readonly code:
      | "DELIVERY_MUST_BE_DISABLED"
      | "FULL_SYNC_SCOPE_REQUIRED"
      | "RECONCILIATION_IN_PROGRESS"
      | "RECONCILIATION_CYCLE_INVALID"
      | "RECONCILIATION_CURSOR_MISMATCH"
      | "RECONCILIATION_DEPLOYMENT_BINDING_MISMATCH"
      | "RECONCILIATION_EVIDENCE_LIMIT_EXCEEDED"
      | "RECONCILIATION_RECOVERY_NOT_AVAILABLE"
      | "RECONCILIATION_RECOVERY_DIGEST_MISMATCH"
      | "RECONCILIATION_CURRENT_STABILITY_EXPECTATION_INVALID"
      | "RECONCILIATION_CURRENT_STABILITY_NOT_AVAILABLE"
      | "RECONCILIATION_CURRENT_STABILITY_STALE",
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

export type WhatsAppCatalogMutationGenerationEntry = {
  scope: "product" | "mapping" | "outbox";
  path: string;
  updateTimeMs: number;
  status?: string;
};

export function assertWhatsAppCatalogMutationEvidenceWithinLimit(input: {
  productDocuments: number;
  mappingDocuments: number;
  outboxDocuments: number;
}): void {
  const counts = [
    input.productDocuments,
    input.mappingDocuments,
    input.outboxDocuments,
  ];
  if (
    counts.some((count) => !Number.isSafeInteger(count) || count < 0) ||
    counts.reduce((sum, count) => sum + count, 0) >
      WHATSAPP_CATALOG_MAX_GENERATION_DOCUMENTS
  ) {
    throw new WhatsAppCatalogFullReconciliationError(
      "RECONCILIATION_EVIDENCE_LIMIT_EXCEEDED",
    );
  }
}

/**
 * Canonical generation for every document that can change catalogue
 * completeness. Firestore commit timestamps make an otherwise content-neutral
 * product/mapping/outbox update visible to the final stability barrier.
 */
export function whatsappCatalogMutationGenerationDigest(input: {
  entries: readonly WhatsAppCatalogMutationGenerationEntry[];
}): string {
  const entries = input.entries.map((entry) => {
    if (
      !["product", "mapping", "outbox"].includes(entry.scope) ||
      !entry.path ||
      !Number.isSafeInteger(entry.updateTimeMs) ||
      entry.updateTimeMs < 0 ||
      (entry.scope === "outbox" && typeof entry.status !== "string")
    ) {
      throw new Error("WHATSAPP_CATALOG_MUTATION_GENERATION_INVALID");
    }
    return [
      entry.scope,
      entry.path,
      entry.updateTimeMs,
      entry.scope === "outbox" ? entry.status : "",
    ] as const;
  });
  entries.sort((left, right) =>
    JSON.stringify(left).localeCompare(JSON.stringify(right)),
  );
  return createHash("sha256").update(JSON.stringify(entries)).digest("hex");
}

type WhatsAppCatalogGlobalMutationEvidence = {
  productDocuments: number;
  mappingDocuments: number;
  pendingOutboxJobs: number;
  totalOutboxDocuments: number;
  outboxCountsVerified: boolean;
  outboxStatusCounts: WhatsAppCatalogOutboxStatusCounts;
  sourceDigest: string;
  mutationGenerationDigestSha256: string;
  latestMutationAtMs: number;
};

type QuerySnapshotReader = (
  query: FirebaseFirestore.Query,
) => Promise<FirebaseFirestore.QuerySnapshot>;

function mutationDocumentUpdateTimeMs(
  document: FirebaseFirestore.QueryDocumentSnapshot,
): number {
  const updateTime = document.updateTime as
    | { toMillis?: () => number }
    | undefined;
  const updateTimeMs = updateTime?.toMillis?.();
  if (!Number.isSafeInteger(updateTimeMs) || Number(updateTimeMs) <= 0) {
    throw new WhatsAppCatalogFullReconciliationError(
      "RECONCILIATION_CURRENT_STABILITY_NOT_AVAILABLE",
    );
  }
  return Number(updateTimeMs);
}

async function readGlobalMutationEvidence(
  readQuery: QuerySnapshotReader,
): Promise<WhatsAppCatalogGlobalMutationEvidence> {
  // Firestore transactions are serializable, so these query reads establish a
  // single point-in-time view and protect the terminal CAS from phantoms. Keep
  // that transaction explicitly bounded: each next query receives only the
  // remaining budget plus one overflow sentinel, so at most MAX + 1 documents
  // are ever read before an oversized catalogue fails closed.
  let remaining = WHATSAPP_CATALOG_MAX_GENERATION_DOCUMENTS;
  const products = await readQuery(
    db
      .collectionGroup("products")
      .select()
      .limit(remaining + 1),
  );
  assertWhatsAppCatalogMutationEvidenceWithinLimit({
    productDocuments: products.size,
    mappingDocuments: 0,
    outboxDocuments: 0,
  });
  remaining -= products.size;
  const mappings = await readQuery(
    db
      .collection(WHATSAPP_CATALOG_MAPPINGS)
      .select()
      .limit(remaining + 1),
  );
  assertWhatsAppCatalogMutationEvidenceWithinLimit({
    productDocuments: products.size,
    mappingDocuments: mappings.size,
    outboxDocuments: 0,
  });
  remaining -= mappings.size;
  const outbox = await readQuery(
    db
      .collection(WHATSAPP_CATALOG_OUTBOX)
      .select("status")
      .limit(remaining + 1),
  );
  assertWhatsAppCatalogMutationEvidenceWithinLimit({
    productDocuments: products.size,
    mappingDocuments: mappings.size,
    outboxDocuments: outbox.size,
  });
  const statusCounts = {
    pending: 0,
    retry: 0,
    processing: 0,
    submitted: 0,
    active: 0,
    deleted: 0,
    rejected: 0,
    blocked: 0,
    failed: 0,
  };
  for (const document of outbox.docs) {
    const status = text(document.data().status) as keyof typeof statusCounts;
    if (Object.prototype.hasOwnProperty.call(statusCounts, status)) {
      statusCounts[status] += 1;
    }
  }
  const outboxEvidence = summarizeWhatsAppCatalogOutboxEvidence({
    total: outbox.size,
    ...statusCounts,
  });
  const mutationEntries: WhatsAppCatalogMutationGenerationEntry[] = [
    ...products.docs.map((document) => ({
      scope: "product" as const,
      path: document.ref.path,
      updateTimeMs: mutationDocumentUpdateTimeMs(document),
    })),
    ...mappings.docs.map((document) => ({
      scope: "mapping" as const,
      path: document.ref.path,
      updateTimeMs: mutationDocumentUpdateTimeMs(document),
    })),
    ...outbox.docs.map((document) => ({
      scope: "outbox" as const,
      path: document.ref.path,
      updateTimeMs: mutationDocumentUpdateTimeMs(document),
      status: text(document.data().status),
    })),
  ];
  return {
    productDocuments: products.size,
    mappingDocuments: mappings.size,
    ...outboxEvidence,
    sourceDigest: scanSourceDigest(
      scanSourceDigest(EMPTY_SOURCE_DIGEST, "products", products.docs),
      "mappings",
      mappings.docs,
    ),
    mutationGenerationDigestSha256: whatsappCatalogMutationGenerationDigest({
      entries: mutationEntries,
    }),
    latestMutationAtMs: mutationEntries.reduce(
      (latest, entry) => Math.max(latest, entry.updateTimeMs),
      0,
    ),
  };
}

async function globalSourceEvidence(): Promise<WhatsAppCatalogGlobalMutationEvidence> {
  return db.runTransaction((transaction) =>
    readGlobalMutationEvidence((query) => transaction.get(query)),
  );
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
  stableMutationGenerationDigestSha256: string;
  cycleStartedAtMs: number;
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
    stableMutationGenerationDigestSha256: text(
      value.stableMutationGenerationDigestSha256,
    ),
    cycleStartedAtMs: Number(value.cycleStartedAtMs ?? 0),
  };
}

function persistedDeploymentBinding(
  binding: WhatsAppCatalogDeploymentBinding,
): Record<string, string> {
  return {
    deployedAppCommit: binding.deployedAppCommit,
    targetConfigurationDigestSha256: binding.targetConfigurationDigestSha256,
    firebaseProjectId: binding.firebaseProjectId,
    catalogId: binding.catalogId,
    senderPhoneNumberId: binding.senderPhoneNumberId,
  };
}

function persistedDeploymentBindingMatches(
  value: Record<string, unknown>,
  binding: WhatsAppCatalogDeploymentBinding,
): boolean {
  return Object.entries(persistedDeploymentBinding(binding)).every(
    ([key, expected]) => text(value[key]) === expected,
  );
}

function assertPersistedDeploymentBinding(
  state: Record<string, unknown>,
  run: Record<string, unknown>,
  binding: WhatsAppCatalogDeploymentBinding,
): void {
  if (
    !persistedDeploymentBindingMatches(state, binding) ||
    !persistedDeploymentBindingMatches(run, binding)
  ) {
    throw new WhatsAppCatalogFullReconciliationError(
      "RECONCILIATION_DEPLOYMENT_BINDING_MISMATCH",
    );
  }
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
  mutationGenerationDigestSha256: string;
  productDocuments: number;
  mappingDocuments: number;
  totalOutboxDocuments: number;
  outboxStatusCounts: WhatsAppCatalogOutboxStatusCounts;
}): string {
  return createHash("sha256")
    .update(
      JSON.stringify({
        merchantSetDigest: input.merchantSetDigest,
        sourceDigest: input.sourceDigest,
        mutationGenerationDigestSha256: input.mutationGenerationDigestSha256,
        productDocuments: input.productDocuments,
        mappingDocuments: input.mappingDocuments,
        malformedMappings: 0,
        pendingOutboxJobs: 0,
        totalOutboxDocuments: input.totalOutboxDocuments,
        outboxStatusCounts: Object.fromEntries(
          OUTBOX_STATUS_KEYS.map((key) => [key, input.outboxStatusCounts[key]]),
        ),
        outboxCountsVerified: true,
      }),
    )
    .digest("hex");
}

const RECONCILIATION_COMPLETION_CAS_FIELDS = [
  "cycleId",
  "cursorPath",
  "status",
  "phase",
  "pages",
  "verificationPass",
  "scanPass",
  "scanProductDocuments",
  "scanMappingDocuments",
  "scanSourceDigest",
  "malformedMappings",
  "stableVerificationSourceDigest",
  "stableVerificationMerchantDigest",
  "stableMutationGenerationDigestSha256",
  "cycleStartedAtMs",
] as const;

function completionCasStateMatches(
  value: Record<string, unknown>,
  expected: ReturnType<typeof currentRunState>,
): boolean {
  const current = currentRunState(value);
  return RECONCILIATION_COMPLETION_CAS_FIELDS.every(
    (key) => current[key] === expected[key],
  );
}

type ReconciliationCompletionAttempt =
  | {
      completed: false;
      evidence: WhatsAppCatalogGlobalMutationEvidence;
    }
  | {
      completed: true;
      evidence: WhatsAppCatalogGlobalMutationEvidence;
      completionDigest: string;
      cycleCompletedAtMs: number;
    };

async function commitReconciliationCompletionIfUnchanged(input: {
  stateRef: FirebaseFirestore.DocumentReference;
  runRef: FirebaseFirestore.DocumentReference;
  state: ReturnType<typeof currentRunState>;
  deploymentBinding?: WhatsAppCatalogDeploymentBinding;
  merchantSetDigest: string;
  completeMerchants: number;
  eligibleProducts: number;
  activeAcceptedProducts: number;
  verificationPass: number;
  inspected: number;
}): Promise<ReconciliationCompletionAttempt> {
  return db.runTransaction(async (transaction) => {
    const [stateDocument, runDocument, evidence] = await Promise.all([
      transaction.get(input.stateRef),
      transaction.get(input.runRef),
      readGlobalMutationEvidence((query) => transaction.get(query)),
    ]);
    const rawState = stateDocument.data() ?? {};
    const rawRun = runDocument.data() ?? {};
    if (
      !stateDocument.exists ||
      !runDocument.exists ||
      !completionCasStateMatches(rawState, input.state) ||
      !completionCasStateMatches(rawRun, input.state)
    ) {
      throw new WhatsAppCatalogFullReconciliationError(
        "RECONCILIATION_CURSOR_MISMATCH",
        {
          cycleId: currentRunState(rawState).cycleId,
          nextCursorPath: currentRunState(rawState).cursorPath || null,
          phase: currentRunState(rawState).phase,
        },
      );
    }
    if (input.deploymentBinding) {
      assertPersistedDeploymentBinding(
        rawState,
        rawRun,
        input.deploymentBinding,
      );
    }
    // The snapshot read time is assigned by Firestore. Use it for the durable
    // receipt chronology so workstation clock skew cannot author completion
    // evidence.
    const nowMs = stateDocument.readTime.toMillis();
    const sourceStillCurrent =
      evidence.productDocuments === input.state.scanProductDocuments &&
      evidence.mappingDocuments === input.state.scanMappingDocuments &&
      evidence.sourceDigest === input.state.scanSourceDigest;
    const mutationGenerationStillCurrent =
      /^[a-f0-9]{64}$/.test(input.state.stableMutationGenerationDigestSha256) &&
      evidence.mutationGenerationDigestSha256 ===
        input.state.stableMutationGenerationDigestSha256;
    const completionStillValid =
      sourceStillCurrent &&
      mutationGenerationStillCurrent &&
      input.merchantSetDigest ===
        input.state.stableVerificationMerchantDigest &&
      input.state.scanSourceDigest ===
        input.state.stableVerificationSourceDigest &&
      input.state.malformedMappings === 0 &&
      evidence.pendingOutboxJobs === 0 &&
      exactDrainedOutboxEvidence(
        evidence.outboxStatusCounts,
        evidence.totalOutboxDocuments,
        evidence.outboxCountsVerified,
      ) &&
      Number.isSafeInteger(input.state.cycleStartedAtMs) &&
      input.state.cycleStartedAtMs > 0 &&
      input.state.cycleStartedAtMs <=
        nowMs + WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS;
    if (!completionStillValid) return { completed: false, evidence };

    const completionDigest = stabilizedCompletionDigest({
      merchantSetDigest: input.merchantSetDigest,
      sourceDigest: input.state.scanSourceDigest,
      mutationGenerationDigestSha256: evidence.mutationGenerationDigestSha256,
      productDocuments: input.state.scanProductDocuments,
      mappingDocuments: input.state.scanMappingDocuments,
      totalOutboxDocuments: evidence.totalOutboxDocuments,
      outboxStatusCounts: evidence.outboxStatusCounts,
    });
    const completedState = {
      cycleId: input.state.cycleId,
      status: "complete",
      phase: "complete",
      cursorPath: null,
      totalInspected: input.state.totalInspected + input.inspected,
      totalQueued: input.state.totalQueued,
      pages: input.state.pages + 1,
      verificationPass: input.verificationPass,
      scanPass: input.state.scanPass,
      scanProductDocuments: input.state.scanProductDocuments,
      scanMappingDocuments: input.state.scanMappingDocuments,
      scanQueued: input.state.scanQueued,
      sourceDigest: input.state.scanSourceDigest,
      scanSourceDigest: input.state.scanSourceDigest,
      malformedMappings: 0,
      malformedMappingDigest: EMPTY_SOURCE_DIGEST,
      pendingOutboxJobs: 0,
      totalOutboxDocuments: evidence.totalOutboxDocuments,
      outboxCountsVerified: evidence.outboxCountsVerified,
      outboxStatusCounts: evidence.outboxStatusCounts,
      outboxDrained: true,
      sourceCountsVerified: true,
      stabilityVerified: true,
      catalogComplete: true,
      setEqualityVerified: true,
      completeMerchants: input.completeMerchants,
      incompleteMerchants: 0,
      eligibleProducts: input.eligibleProducts,
      activeAcceptedProducts: input.activeAcceptedProducts,
      merchantSetDigest: input.merchantSetDigest,
      mutationGenerationDigestSha256: evidence.mutationGenerationDigestSha256,
      completionDigest,
      cycleCompletedAt: FieldValue.serverTimestamp(),
      cycleCompletedAtMs: nowMs,
      updatedAt: FieldValue.serverTimestamp(),
      updatedAtMs: nowMs,
      schemaVersion: 1,
    };
    transaction.set(input.stateRef, completedState, { merge: true });
    transaction.set(input.runRef, completedState, { merge: true });
    return {
      completed: true,
      evidence,
      completionDigest,
      cycleCompletedAtMs: nowMs,
    };
  });
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
  deploymentBinding?: WhatsAppCatalogDeploymentBinding;
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
  const requestedCycleId = text(input.cycleId);
  const requestedCursorPath = text(input.cursorPath);
  const deploymentBinding = input.deploymentBinding;
  let stateDocument: FirebaseFirestore.DocumentSnapshot | undefined;
  let state: ReturnType<typeof currentRunState>;

  if (!requestedCycleId) {
    state = await db.runTransaction(async (transaction) => {
      const currentDocument = await transaction.get(stateRef);
      const current = currentRunState(currentDocument.data() ?? {});
      if (current.status === "running" && current.cycleId) {
        throw new WhatsAppCatalogFullReconciliationError(
          "RECONCILIATION_IN_PROGRESS",
          {
            cycleId: current.cycleId,
            nextCursorPath: current.cursorPath || null,
            phase: current.phase,
          },
        );
      }
      const cycleId = randomBytes(16).toString("hex");
      // Firestore owns this timestamp even when the state document does not yet
      // exist; DocumentSnapshot.readTime is the transaction's server read time.
      const cycleStartedAtMs = currentDocument.readTime.toMillis();
      const initialized: ReturnType<typeof currentRunState> = {
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
        stableMutationGenerationDigestSha256: "",
        cycleStartedAtMs,
      };
      const initialState = {
        ...initialized,
        ...(deploymentBinding
          ? persistedDeploymentBinding(deploymentBinding)
          : {}),
        cursorPath: null,
        catalogComplete: false,
        completionDigest: null,
        stabilityVerified: false,
        sourceCountsVerified: false,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        updatedAtMs: cycleStartedAtMs,
        schemaVersion: 1,
      };
      const initialRunRef = db.doc(
        `${WHATSAPP_CATALOG_RECONCILIATION_RUNS}/${cycleId}`,
      );
      transaction.set(stateRef, initialState, { merge: true });
      transaction.set(
        initialRunRef,
        {
          ...initialState,
          pageSize,
        },
        { merge: true },
      );
      return initialized;
    });
  } else {
    stateDocument = await stateRef.get();
    state = currentRunState(stateDocument.data() ?? {});
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
    const persistedRun = deploymentBinding
      ? await db
          .doc(`${WHATSAPP_CATALOG_RECONCILIATION_RUNS}/${state.cycleId}`)
          .get()
      : null;
    if (deploymentBinding) {
      const persistedCycleStartedAtMs = Number(
        persistedRun?.data()?.cycleStartedAtMs,
      );
      assertPersistedDeploymentBinding(
        stateDocument?.data() ?? {},
        persistedRun?.data() ?? {},
        deploymentBinding,
      );
      if (
        !Number.isSafeInteger(persistedCycleStartedAtMs) ||
        persistedCycleStartedAtMs <= 0 ||
        Number(stateDocument?.data()?.cycleStartedAtMs) !==
          persistedCycleStartedAtMs
      ) {
        throw new WhatsAppCatalogFullReconciliationError(
          "RECONCILIATION_DEPLOYMENT_BINDING_MISMATCH",
        );
      }
    }
    if (state.status === "complete") {
      const run =
        persistedRun ??
        (await db
          .doc(`${WHATSAPP_CATALOG_RECONCILIATION_RUNS}/${state.cycleId}`)
          .get());
      const cycleStartedAtMs = Number(run.data()?.cycleStartedAtMs);
      const cycleCompletedAtMs = Number(run.data()?.cycleCompletedAtMs);
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
        totalOutboxDocuments: Number(run.data()?.totalOutboxDocuments ?? -1),
        outboxCountsVerified: run.data()?.outboxCountsVerified === true,
        ...(run.data()?.outboxStatusCounts
          ? {
              outboxStatusCounts: run.data()
                ?.outboxStatusCounts as WhatsAppCatalogOutboxStatusCounts,
            }
          : {}),
        stabilityVerified: run.data()?.stabilityVerified === true,
        sourceDigest: text(run.data()?.sourceDigest),
        sourceCountsVerified: run.data()?.sourceCountsVerified === true,
        malformedMappingDigest:
          text(run.data()?.malformedMappingDigest) || EMPTY_SOURCE_DIGEST,
        ...(text(run.data()?.completionDigest)
          ? { completionDigest: text(run.data()?.completionDigest) }
          : {}),
        ...(text(run.data()?.mutationGenerationDigestSha256)
          ? {
              mutationGenerationDigestSha256: text(
                run.data()?.mutationGenerationDigestSha256,
              ),
            }
          : {}),
        ...(Number.isSafeInteger(cycleStartedAtMs) &&
        Number.isSafeInteger(cycleCompletedAtMs)
          ? {
              cycleStartedAt: new Date(cycleStartedAtMs).toISOString(),
              cycleCompletedAt: new Date(cycleCompletedAtMs).toISOString(),
            }
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
  let evidence = await globalSourceEvidence();
  let sourceCountsCurrent =
    evidence.productDocuments === state.scanProductDocuments &&
    evidence.mappingDocuments === state.scanMappingDocuments &&
    evidence.sourceDigest === state.scanSourceDigest;
  const catalogComplete =
    merchantSetComplete &&
    sameAsVerifiedSource &&
    merchantSetDigest === state.verifiedCompletionDigest &&
    state.stableVerificationSourceDigest === state.scanSourceDigest &&
    state.stableVerificationMerchantDigest === merchantSetDigest &&
    state.stableMutationGenerationDigestSha256 ===
      evidence.mutationGenerationDigestSha256 &&
    state.malformedMappings === 0 &&
    evidence.pendingOutboxJobs === 0 &&
    exactDrainedOutboxEvidence(
      evidence.outboxStatusCounts,
      evidence.totalOutboxDocuments,
      evidence.outboxCountsVerified,
    ) &&
    sourceCountsCurrent;
  if (catalogComplete) {
    const completion = await commitReconciliationCompletionIfUnchanged({
      stateRef,
      runRef,
      state,
      deploymentBinding,
      merchantSetDigest,
      completeMerchants,
      eligibleProducts,
      activeAcceptedProducts,
      verificationPass,
      inspected: merchantPage.length,
    });
    evidence = completion.evidence;
    sourceCountsCurrent =
      evidence.productDocuments === state.scanProductDocuments &&
      evidence.mappingDocuments === state.scanMappingDocuments &&
      evidence.sourceDigest === state.scanSourceDigest;
    if (completion.completed) {
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
        totalOutboxDocuments: evidence.totalOutboxDocuments,
        outboxCountsVerified: evidence.outboxCountsVerified,
        outboxStatusCounts: evidence.outboxStatusCounts,
        stabilityVerified: true,
        sourceDigest: state.scanSourceDigest,
        sourceCountsVerified: true,
        malformedMappingDigest: EMPTY_SOURCE_DIGEST,
        completionDigest: completion.completionDigest,
        mutationGenerationDigestSha256: evidence.mutationGenerationDigestSha256,
        cycleStartedAt: new Date(state.cycleStartedAtMs).toISOString(),
        cycleCompletedAt: new Date(completion.cycleCompletedAtMs).toISOString(),
      };
    }
  }
  const cleanMerchantVerification =
    merchantSetComplete &&
    state.malformedMappings === 0 &&
    evidence.pendingOutboxJobs === 0 &&
    exactDrainedOutboxEvidence(
      evidence.outboxStatusCounts,
      evidence.totalOutboxDocuments,
      evidence.outboxCountsVerified,
    ) &&
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
      state.stableVerificationMerchantDigest === merchantSetDigest &&
      state.stableMutationGenerationDigestSha256 ===
        evidence.mutationGenerationDigestSha256
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
    stableMutationGenerationDigestSha256: requiresSourceRefresh
      ? ""
      : state.stableMutationGenerationDigestSha256,
    catalogComplete: false,
    setEqualityVerified: merchantSetComplete,
    stabilityVerified: false,
    sourceCountsVerified: sourceCountsCurrent,
    completeMerchants,
    incompleteMerchants,
    eligibleProducts,
    activeAcceptedProducts,
    pendingOutboxJobs: evidence.pendingOutboxJobs,
    totalOutboxDocuments: evidence.totalOutboxDocuments,
    outboxCountsVerified: evidence.outboxCountsVerified,
    outboxStatusCounts: evidence.outboxStatusCounts,
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
          stableMutationGenerationDigestSha256: "",
          stabilityBarrierEstablishedAt: FieldValue.serverTimestamp(),
        }
      : {}),
    ...(recordStableVerification
      ? {
          stableVerificationSourceDigest: state.scanSourceDigest,
          stableVerificationMerchantDigest: merchantSetDigest,
          stableMutationGenerationDigestSha256:
            evidence.mutationGenerationDigestSha256,
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
    totalOutboxDocuments: evidence.totalOutboxDocuments,
    outboxCountsVerified: evidence.outboxCountsVerified,
    outboxStatusCounts: evidence.outboxStatusCounts,
    stabilityVerified: false,
    sourceDigest: state.scanSourceDigest,
    sourceCountsVerified: sourceCountsCurrent,
    malformedMappingDigest: state.malformedMappingDigest,
  };
}

/** Bind the deployed revision and immutable provider target before any page work. */
export async function runBoundWhatsAppCatalogFullReconciliationPage(
  input: {
    expectedAppCommit: unknown;
    expectedTargetConfigurationDigestSha256: unknown;
    cycleId?: string;
    cursorPath?: string;
    pageSize?: number;
  },
  executePage: typeof runWhatsAppCatalogFullReconciliationPage = runWhatsAppCatalogFullReconciliationPage,
): Promise<WhatsAppCatalogFullReconciliationResponse> {
  const deploymentBinding = assertWhatsAppCatalogDeploymentBinding(input);
  const result = await executePage({
    cycleId: input.cycleId,
    cursorPath: input.cursorPath,
    pageSize: input.pageSize,
    deploymentBinding,
  });
  return { ...result, ...deploymentBinding };
}

type WhatsAppCatalogRecoveryState = {
  deploymentBinding: WhatsAppCatalogDeploymentBinding;
  status: "running" | "complete";
  cycleId: string;
  cursorPath: string;
  phase: FullReconciliationPhase;
  pages: number;
  pageSize: number;
  productScanComplete: boolean;
  mappingScanComplete: boolean;
  completionProof?: {
    cycleStartedAtMs: number;
    cycleCompletedAtMs: number;
    completionDigest: string;
    mutationGenerationDigestSha256: string;
    totalOutboxDocuments: number;
    outboxCountsVerified: true;
    outboxStatusCounts: WhatsAppCatalogOutboxStatusCounts;
  };
  continuationStateDigestSha256: string;
};

function continuationStateDigest(
  binding: WhatsAppCatalogDeploymentBinding,
  state: Omit<WhatsAppCatalogRecoveryState, "continuationStateDigestSha256">,
): string {
  return createHash("sha256")
    .update(
      JSON.stringify({
        schemaVersion: 1,
        deployedAppCommit: binding.deployedAppCommit,
        targetConfigurationDigestSha256:
          binding.targetConfigurationDigestSha256,
        firebaseProjectId: binding.firebaseProjectId,
        catalogId: binding.catalogId,
        senderPhoneNumberId: binding.senderPhoneNumberId,
        status: state.status,
        cycleId: state.cycleId,
        cursorPath: state.cursorPath,
        phase: state.phase,
        pages: state.pages,
        pageSize: state.pageSize,
        productScanComplete: state.productScanComplete,
        mappingScanComplete: state.mappingScanComplete,
        completionProof: state.completionProof ?? null,
      }),
    )
    .digest("hex");
}

async function currentRecoveryState(
  binding: WhatsAppCatalogDeploymentBinding,
): Promise<WhatsAppCatalogRecoveryState> {
  const stateDocument = await db.doc(FULL_RECONCILIATION_STATE_PATH).get();
  const rawState = stateDocument.data() ?? {};
  const state = currentRunState(rawState);
  if (
    !stateDocument.exists ||
    rawState.schemaVersion !== 1 ||
    !["running", "complete"].includes(state.status) ||
    !/^[a-f0-9]{32}$/.test(state.cycleId) ||
    (state.status === "running"
      ? !["products", "mappings", "verify"].includes(text(rawState.phase))
      : text(rawState.phase) !== "complete") ||
    !Number.isSafeInteger(rawState.pages) ||
    Number(rawState.pages) < 0
  ) {
    throw new WhatsAppCatalogFullReconciliationError(
      "RECONCILIATION_RECOVERY_NOT_AVAILABLE",
    );
  }
  const run = await db
    .doc(`${WHATSAPP_CATALOG_RECONCILIATION_RUNS}/${state.cycleId}`)
    .get();
  const runData = run.data() ?? {};
  const pageSize = Number(runData.pageSize);
  if (
    !run.exists ||
    runData.schemaVersion !== 1 ||
    text(runData.cycleId) !== state.cycleId ||
    text(runData.status) !== state.status ||
    text(runData.phase) !== state.phase ||
    text(runData.cursorPath) !== state.cursorPath ||
    Number(runData.pages) !== state.pages ||
    !Number.isSafeInteger(pageSize) ||
    pageSize < 1 ||
    pageSize > FULL_RECONCILIATION_MAX_PAGE_SIZE
  ) {
    throw new WhatsAppCatalogFullReconciliationError(
      "RECONCILIATION_RECOVERY_NOT_AVAILABLE",
    );
  }
  assertPersistedDeploymentBinding(rawState, runData, binding);
  const cycleStartedAtMs = Number(runData.cycleStartedAtMs);
  const recoveryReadAtMs = Math.max(
    stateDocument.readTime.toMillis(),
    run.readTime.toMillis(),
  );
  if (
    !Number.isSafeInteger(cycleStartedAtMs) ||
    cycleStartedAtMs <= 0 ||
    cycleStartedAtMs >
      recoveryReadAtMs + WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS ||
    Number(rawState.cycleStartedAtMs) !== cycleStartedAtMs
  ) {
    throw new WhatsAppCatalogFullReconciliationError(
      "RECONCILIATION_RECOVERY_NOT_AVAILABLE",
    );
  }
  let completionProof: WhatsAppCatalogRecoveryState["completionProof"];
  if (state.status === "complete") {
    const cycleCompletedAtMs = Number(runData.cycleCompletedAtMs);
    const completionDigest = text(runData.completionDigest);
    const mutationGenerationDigestSha256 = text(
      runData.mutationGenerationDigestSha256,
    );
    const totalOutboxDocuments = Number(runData.totalOutboxDocuments);
    const outboxStatusCounts = runData.outboxStatusCounts as
      | WhatsAppCatalogOutboxStatusCounts
      | undefined;
    const proofMatchesState =
      Number(rawState.cycleCompletedAtMs) === cycleCompletedAtMs &&
      text(rawState.completionDigest) === completionDigest &&
      text(rawState.mutationGenerationDigestSha256) ===
        mutationGenerationDigestSha256 &&
      JSON.stringify(rawState.outboxStatusCounts) ===
        JSON.stringify(outboxStatusCounts) &&
      Number(rawState.totalOutboxDocuments) === totalOutboxDocuments &&
      rawState.outboxCountsVerified === runData.outboxCountsVerified &&
      rawState.catalogComplete === runData.catalogComplete &&
      rawState.stabilityVerified === runData.stabilityVerified &&
      rawState.sourceCountsVerified === runData.sourceCountsVerified &&
      Number(rawState.pendingOutboxJobs) ===
        Number(runData.pendingOutboxJobs) &&
      Number(rawState.incompleteMerchants) ===
        Number(runData.incompleteMerchants) &&
      Number(rawState.malformedMappings) === Number(runData.malformedMappings);
    if (
      !Number.isSafeInteger(cycleCompletedAtMs) ||
      cycleCompletedAtMs < cycleStartedAtMs ||
      cycleCompletedAtMs >
        recoveryReadAtMs + WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS ||
      !/^[a-f0-9]{64}$/.test(completionDigest) ||
      !/^[a-f0-9]{64}$/.test(mutationGenerationDigestSha256) ||
      !proofMatchesState ||
      runData.catalogComplete !== true ||
      runData.stabilityVerified !== true ||
      runData.sourceCountsVerified !== true ||
      runData.outboxCountsVerified !== true ||
      Number(runData.pendingOutboxJobs) !== 0 ||
      Number(runData.incompleteMerchants) !== 0 ||
      Number(runData.malformedMappings) !== 0 ||
      !outboxStatusCounts ||
      !exactDrainedOutboxEvidence(
        outboxStatusCounts,
        totalOutboxDocuments,
        runData.outboxCountsVerified,
      )
    ) {
      throw new WhatsAppCatalogFullReconciliationError(
        "RECONCILIATION_RECOVERY_NOT_AVAILABLE",
      );
    }
    completionProof = {
      cycleStartedAtMs,
      cycleCompletedAtMs,
      completionDigest,
      mutationGenerationDigestSha256,
      totalOutboxDocuments,
      outboxCountsVerified: true,
      outboxStatusCounts,
    };
  }
  const snapshot = {
    deploymentBinding: binding,
    status: state.status as "running" | "complete",
    cycleId: state.cycleId,
    cursorPath: state.cursorPath,
    phase: state.phase,
    pages: state.pages,
    pageSize,
    productScanComplete: state.phase !== "products",
    mappingScanComplete: state.phase === "verify" || state.phase === "complete",
    ...(completionProof ? { completionProof } : {}),
  };
  return {
    ...snapshot,
    continuationStateDigestSha256: continuationStateDigest(binding, snapshot),
  };
}

type WhatsAppCatalogRecoveryStateReader = (
  binding: WhatsAppCatalogDeploymentBinding,
) => Promise<WhatsAppCatalogRecoveryState>;

export async function inspectBoundWhatsAppCatalogReconciliationRecovery(
  input: {
    expectedAppCommit: unknown;
    expectedTargetConfigurationDigestSha256: unknown;
  },
  readRecoveryState: WhatsAppCatalogRecoveryStateReader = currentRecoveryState,
): Promise<
  {
    outcome: "recovery_state";
    phase: FullReconciliationPhase;
    acknowledgedPages: number;
    productScanComplete: boolean;
    mappingScanComplete: boolean;
    continuationStateDigestSha256: string;
    cycleId?: string;
    cycleStartedAt?: string;
    cycleCompletedAt?: string;
    cycleComplete?: boolean;
    catalogComplete?: boolean;
    stabilityVerified?: boolean;
    sourceCountsVerified?: boolean;
    pendingOutboxJobs?: number;
    totalOutboxDocuments?: number;
    outboxCountsVerified?: boolean;
    outboxStatusCounts?: WhatsAppCatalogOutboxStatusCounts;
    incompleteMerchants?: number;
    malformedMappings?: number;
    completionDigest?: string;
    mutationGenerationDigestSha256?: string;
  } & WhatsAppCatalogDeploymentBinding
> {
  const binding = assertWhatsAppCatalogDeploymentBinding(input);
  const state = await readRecoveryState(binding);
  if (JSON.stringify(state.deploymentBinding) !== JSON.stringify(binding)) {
    throw new WhatsAppCatalogFullReconciliationError(
      "RECONCILIATION_DEPLOYMENT_BINDING_MISMATCH",
    );
  }
  const completion = state.completionProof;
  return {
    outcome: "recovery_state",
    phase: state.phase,
    acknowledgedPages: state.pages,
    productScanComplete: state.productScanComplete,
    mappingScanComplete: state.mappingScanComplete,
    continuationStateDigestSha256: state.continuationStateDigestSha256,
    ...(completion
      ? {
          cycleId: state.cycleId,
          cycleStartedAt: new Date(completion.cycleStartedAtMs).toISOString(),
          cycleCompletedAt: new Date(
            completion.cycleCompletedAtMs,
          ).toISOString(),
          cycleComplete: true,
          catalogComplete: true,
          stabilityVerified: true,
          sourceCountsVerified: true,
          pendingOutboxJobs: 0,
          totalOutboxDocuments: completion.totalOutboxDocuments,
          outboxCountsVerified: completion.outboxCountsVerified,
          outboxStatusCounts: completion.outboxStatusCounts,
          incompleteMerchants: 0,
          malformedMappings: 0,
          completionDigest: completion.completionDigest,
          mutationGenerationDigestSha256:
            completion.mutationGenerationDigestSha256,
        }
      : {}),
    ...binding,
  };
}

export type WhatsAppCatalogCurrentStability = {
  deploymentBinding: WhatsAppCatalogDeploymentBinding;
  readAtMs: number;
  cycleId: string;
  cycleStartedAtMs: number;
  cycleCompletedAtMs: number;
  completionReceiptHashSha256: string;
  mutationGenerationDigestSha256: string;
  sourceDigestSha256: string;
  productDocuments: number;
  mappingDocuments: number;
  pendingOutboxJobs: 0;
  terminalOutboxDocuments: number;
  nonterminalOutboxDocuments: 0;
  totalOutboxDocuments: number;
  outboxCountsVerified: true;
  outboxStatusCounts: WhatsAppCatalogOutboxStatusCounts;
};

type WhatsAppCatalogCurrentStabilityExpectation = {
  cycleId: string;
  completionReceiptHashSha256: string;
  mutationGenerationDigestSha256: string;
};

function strictNonNegativeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

function timestampMillis(value: unknown): number | null {
  if (
    !value ||
    typeof value !== "object" ||
    !("toMillis" in value) ||
    typeof (value as { toMillis?: unknown }).toMillis !== "function"
  ) {
    return null;
  }
  const milliseconds = (value as { toMillis: () => number }).toMillis();
  return Number.isSafeInteger(milliseconds) && milliseconds > 0
    ? milliseconds
    : null;
}

function currentStabilityUnavailable(): never {
  throw new WhatsAppCatalogFullReconciliationError(
    "RECONCILIATION_CURRENT_STABILITY_NOT_AVAILABLE",
  );
}

function currentStabilityStale(): never {
  throw new WhatsAppCatalogFullReconciliationError(
    "RECONCILIATION_CURRENT_STABILITY_STALE",
  );
}

function assertExactCompletionStateAndRun(
  state: Record<string, unknown>,
  run: Record<string, unknown>,
): void {
  const exactFields = [
    "schemaVersion",
    "cycleId",
    "status",
    "phase",
    "cursorPath",
    "cycleStartedAtMs",
    "cycleCompletedAtMs",
    "scanProductDocuments",
    "scanMappingDocuments",
    "sourceDigest",
    "scanSourceDigest",
    "malformedMappings",
    "pendingOutboxJobs",
    "totalOutboxDocuments",
    "outboxCountsVerified",
    "outboxDrained",
    "sourceCountsVerified",
    "stabilityVerified",
    "catalogComplete",
    "setEqualityVerified",
    "completeMerchants",
    "incompleteMerchants",
    "eligibleProducts",
    "activeAcceptedProducts",
    "merchantSetDigest",
    "verifiedSourceDigest",
    "verifiedProductDocuments",
    "verifiedMappingDocuments",
    "verifiedCompletionDigest",
    "verifiedCompleteMerchants",
    "verifiedEligibleProducts",
    "verifiedActiveAcceptedProducts",
    "stableVerificationSourceDigest",
    "stableVerificationMerchantDigest",
    "stableMutationGenerationDigestSha256",
    "mutationGenerationDigestSha256",
    "completionDigest",
  ] as const;
  if (
    exactFields.some(
      (field) => JSON.stringify(state[field]) !== JSON.stringify(run[field]),
    ) ||
    !sameOutboxStatusCounts(
      state.outboxStatusCounts as WhatsAppCatalogOutboxStatusCounts | undefined,
      run.outboxStatusCounts as WhatsAppCatalogOutboxStatusCounts | undefined,
    )
  ) {
    currentStabilityUnavailable();
  }
}

async function currentWhatsAppCatalogStability(
  binding: WhatsAppCatalogDeploymentBinding,
  expectation: WhatsAppCatalogCurrentStabilityExpectation,
): Promise<WhatsAppCatalogCurrentStability> {
  return db.runTransaction(async (transaction) => {
    const stateRef = db.doc(FULL_RECONCILIATION_STATE_PATH);
    const stateDocument = await transaction.get(stateRef);
    const state = stateDocument.data() ?? {};
    if (
      !stateDocument.exists ||
      state.schemaVersion !== 1 ||
      text(state.cycleId) !== expectation.cycleId ||
      text(state.status) !== "complete" ||
      text(state.phase) !== "complete"
    ) {
      currentStabilityStale();
    }

    const runRef = db.doc(
      `${WHATSAPP_CATALOG_RECONCILIATION_RUNS}/${expectation.cycleId}`,
    );
    const runDocument = await transaction.get(runRef);
    const run = runDocument.data() ?? {};
    if (!runDocument.exists) currentStabilityUnavailable();
    assertPersistedDeploymentBinding(state, run, binding);
    assertExactCompletionStateAndRun(state, run);
    const evidence = await readGlobalMutationEvidence((query) =>
      transaction.get(query),
    );

    const readAtMs = Math.max(
      timestampMillis(stateDocument.readTime) ?? 0,
      timestampMillis(runDocument.readTime) ?? 0,
    );
    const stateUpdatedAtMs = timestampMillis(stateDocument.updateTime);
    const runUpdatedAtMs = timestampMillis(runDocument.updateTime);
    const cycleStartedAtMs = state.cycleStartedAtMs;
    const cycleCompletedAtMs = state.cycleCompletedAtMs;
    const stateCycleCompletedTimestampMs = timestampMillis(
      state.cycleCompletedAt,
    );
    const runCycleCompletedTimestampMs = timestampMillis(run.cycleCompletedAt);
    const completionReceiptHashSha256 = text(state.completionDigest);
    const sealedMutationGenerationDigestSha256 = text(
      state.mutationGenerationDigestSha256,
    );
    const sourceDigestSha256 = text(state.scanSourceDigest);
    const merchantSetDigest = text(state.merchantSetDigest);
    const productDocuments = state.scanProductDocuments;
    const mappingDocuments = state.scanMappingDocuments;
    const totalOutboxDocuments = state.totalOutboxDocuments;
    const completeMerchants = state.completeMerchants;
    const eligibleProducts = state.eligibleProducts;
    const activeAcceptedProducts = state.activeAcceptedProducts;
    const outboxStatusCounts = state.outboxStatusCounts as
      | WhatsAppCatalogOutboxStatusCounts
      | undefined;
    const pageSize = run.pageSize;

    if (
      readAtMs <= 0 ||
      stateUpdatedAtMs === null ||
      runUpdatedAtMs === null ||
      !strictNonNegativeInteger(cycleStartedAtMs) ||
      cycleStartedAtMs === 0 ||
      !strictNonNegativeInteger(cycleCompletedAtMs) ||
      cycleCompletedAtMs < cycleStartedAtMs ||
      stateCycleCompletedTimestampMs === null ||
      runCycleCompletedTimestampMs === null ||
      stateCycleCompletedTimestampMs !== runCycleCompletedTimestampMs ||
      stateCycleCompletedTimestampMs < cycleCompletedAtMs ||
      cycleCompletedAtMs >
        readAtMs + WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS ||
      stateCycleCompletedTimestampMs >
        readAtMs + WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS ||
      stateUpdatedAtMs >
        readAtMs + WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS ||
      runUpdatedAtMs > readAtMs + WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS ||
      evidence.latestMutationAtMs >
        readAtMs + WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS ||
      !/^[a-f0-9]{64}$/.test(completionReceiptHashSha256) ||
      !/^[a-f0-9]{64}$/.test(sealedMutationGenerationDigestSha256) ||
      !/^[a-f0-9]{64}$/.test(sourceDigestSha256) ||
      text(state.sourceDigest) !== sourceDigestSha256 ||
      !/^[a-f0-9]{64}$/.test(merchantSetDigest) ||
      text(state.verifiedSourceDigest) !== sourceDigestSha256 ||
      state.verifiedProductDocuments !== productDocuments ||
      state.verifiedMappingDocuments !== mappingDocuments ||
      text(state.verifiedCompletionDigest) !== merchantSetDigest ||
      state.verifiedCompleteMerchants !== completeMerchants ||
      state.verifiedEligibleProducts !== eligibleProducts ||
      state.verifiedActiveAcceptedProducts !== activeAcceptedProducts ||
      text(state.stableVerificationSourceDigest) !== sourceDigestSha256 ||
      text(state.stableVerificationMerchantDigest) !== merchantSetDigest ||
      text(state.stableMutationGenerationDigestSha256) !==
        sealedMutationGenerationDigestSha256 ||
      !strictNonNegativeInteger(productDocuments) ||
      !strictNonNegativeInteger(mappingDocuments) ||
      !strictNonNegativeInteger(totalOutboxDocuments) ||
      !strictNonNegativeInteger(completeMerchants) ||
      !strictNonNegativeInteger(eligibleProducts) ||
      !strictNonNegativeInteger(activeAcceptedProducts) ||
      eligibleProducts !== activeAcceptedProducts ||
      !strictNonNegativeInteger(pageSize) ||
      pageSize < 1 ||
      pageSize > FULL_RECONCILIATION_MAX_PAGE_SIZE ||
      state.malformedMappings !== 0 ||
      state.pendingOutboxJobs !== 0 ||
      state.incompleteMerchants !== 0 ||
      state.outboxCountsVerified !== true ||
      state.outboxDrained !== true ||
      state.sourceCountsVerified !== true ||
      state.stabilityVerified !== true ||
      state.catalogComplete !== true ||
      state.setEqualityVerified !== true ||
      !outboxStatusCounts ||
      !exactDrainedOutboxEvidence(
        outboxStatusCounts,
        totalOutboxDocuments,
        state.outboxCountsVerified,
      )
    ) {
      currentStabilityUnavailable();
    }

    const recomputedCompletionReceiptHashSha256 = stabilizedCompletionDigest({
      merchantSetDigest,
      sourceDigest: sourceDigestSha256,
      mutationGenerationDigestSha256: sealedMutationGenerationDigestSha256,
      productDocuments,
      mappingDocuments,
      totalOutboxDocuments,
      outboxStatusCounts,
    });
    if (
      completionReceiptHashSha256 !== expectation.completionReceiptHashSha256 ||
      sealedMutationGenerationDigestSha256 !==
        expectation.mutationGenerationDigestSha256 ||
      recomputedCompletionReceiptHashSha256 !== completionReceiptHashSha256
    ) {
      currentStabilityStale();
    }

    const currentEvidenceMatchesSealedReceipt =
      evidence.productDocuments === productDocuments &&
      evidence.mappingDocuments === mappingDocuments &&
      evidence.sourceDigest === sourceDigestSha256 &&
      evidence.mutationGenerationDigestSha256 ===
        sealedMutationGenerationDigestSha256 &&
      evidence.pendingOutboxJobs === 0 &&
      evidence.totalOutboxDocuments === totalOutboxDocuments &&
      evidence.outboxCountsVerified === true &&
      sameOutboxStatusCounts(evidence.outboxStatusCounts, outboxStatusCounts) &&
      exactDrainedOutboxEvidence(
        evidence.outboxStatusCounts,
        evidence.totalOutboxDocuments,
        evidence.outboxCountsVerified,
      );
    if (!currentEvidenceMatchesSealedReceipt) currentStabilityStale();

    const terminalOutboxDocuments =
      evidence.outboxStatusCounts.active +
      evidence.outboxStatusCounts.deleted +
      evidence.outboxStatusCounts.rejected +
      evidence.outboxStatusCounts.blocked +
      evidence.outboxStatusCounts.failed;
    const nonterminalOutboxDocuments =
      evidence.outboxStatusCounts.pending +
      evidence.outboxStatusCounts.retry +
      evidence.outboxStatusCounts.processing +
      evidence.outboxStatusCounts.submitted +
      evidence.outboxStatusCounts.unknown;
    if (
      terminalOutboxDocuments !== totalOutboxDocuments ||
      nonterminalOutboxDocuments !== 0
    ) {
      currentStabilityStale();
    }

    return {
      deploymentBinding: binding,
      readAtMs,
      cycleId: expectation.cycleId,
      cycleStartedAtMs,
      cycleCompletedAtMs,
      completionReceiptHashSha256,
      mutationGenerationDigestSha256: evidence.mutationGenerationDigestSha256,
      sourceDigestSha256: evidence.sourceDigest,
      productDocuments: evidence.productDocuments,
      mappingDocuments: evidence.mappingDocuments,
      pendingOutboxJobs: 0,
      terminalOutboxDocuments,
      nonterminalOutboxDocuments: 0,
      totalOutboxDocuments: evidence.totalOutboxDocuments,
      outboxCountsVerified: true,
      outboxStatusCounts: evidence.outboxStatusCounts,
    };
  });
}

type WhatsAppCatalogCurrentStabilityReader = (
  binding: WhatsAppCatalogDeploymentBinding,
  expectation: WhatsAppCatalogCurrentStabilityExpectation,
) => Promise<WhatsAppCatalogCurrentStability>;

/**
 * Fresh, read-only proof that the current catalogue still equals a sealed
 * completed reconciliation receipt. The caller owns expectations, never state
 * or cursors, and the default reader performs one serializable read transaction.
 */
export async function inspectBoundWhatsAppCatalogCurrentStability(
  input: {
    expectedAppCommit: unknown;
    expectedTargetConfigurationDigestSha256: unknown;
    expectedCycleId: unknown;
    expectedCompletionReceiptHashSha256: unknown;
    expectedMutationGenerationDigestSha256: unknown;
  },
  readCurrentStability: WhatsAppCatalogCurrentStabilityReader = currentWhatsAppCatalogStability,
): Promise<
  Omit<WhatsAppCatalogCurrentStability, "deploymentBinding"> &
    WhatsAppCatalogDeploymentBinding & { outcome: "current_stability" }
> {
  const binding = assertWhatsAppCatalogDeploymentBinding(input);
  const expectation = {
    cycleId: text(input.expectedCycleId),
    completionReceiptHashSha256: text(
      input.expectedCompletionReceiptHashSha256,
    ),
    mutationGenerationDigestSha256: text(
      input.expectedMutationGenerationDigestSha256,
    ),
  };
  if (
    !/^[a-f0-9]{32}$/.test(expectation.cycleId) ||
    !/^[a-f0-9]{64}$/.test(expectation.completionReceiptHashSha256) ||
    !/^[a-f0-9]{64}$/.test(expectation.mutationGenerationDigestSha256)
  ) {
    throw new WhatsAppCatalogFullReconciliationError(
      "RECONCILIATION_CURRENT_STABILITY_EXPECTATION_INVALID",
    );
  }
  const current = await readCurrentStability(binding, expectation);
  if (
    JSON.stringify(current.deploymentBinding) !== JSON.stringify(binding) ||
    current.cycleId !== expectation.cycleId ||
    current.completionReceiptHashSha256 !==
      expectation.completionReceiptHashSha256 ||
    current.mutationGenerationDigestSha256 !==
      expectation.mutationGenerationDigestSha256 ||
    !Number.isSafeInteger(current.readAtMs) ||
    current.readAtMs <= 0 ||
    current.pendingOutboxJobs !== 0 ||
    current.nonterminalOutboxDocuments !== 0 ||
    current.terminalOutboxDocuments !== current.totalOutboxDocuments ||
    current.outboxCountsVerified !== true ||
    !/^[a-f0-9]{64}$/.test(current.sourceDigestSha256) ||
    !strictNonNegativeInteger(current.productDocuments) ||
    !strictNonNegativeInteger(current.mappingDocuments) ||
    !strictNonNegativeInteger(current.totalOutboxDocuments) ||
    !exactDrainedOutboxEvidence(
      current.outboxStatusCounts,
      current.totalOutboxDocuments,
      current.outboxCountsVerified,
    )
  ) {
    currentStabilityStale();
  }
  const { deploymentBinding: _binding, ...redacted } = current;
  void _binding;
  return {
    outcome: "current_stability",
    ...redacted,
    ...binding,
  };
}

export async function continueBoundWhatsAppCatalogFullReconciliationPage(
  input: {
    expectedAppCommit: unknown;
    expectedTargetConfigurationDigestSha256: unknown;
    expectedContinuationStateDigestSha256: unknown;
  },
  executePage: typeof runWhatsAppCatalogFullReconciliationPage = runWhatsAppCatalogFullReconciliationPage,
  readRecoveryState: WhatsAppCatalogRecoveryStateReader = currentRecoveryState,
): Promise<WhatsAppCatalogOperatorReconciliationPage> {
  const binding = assertWhatsAppCatalogDeploymentBinding(input);
  const expectedDigest = String(
    input.expectedContinuationStateDigestSha256 ?? "",
  ).trim();
  const state = await readRecoveryState(binding);
  if (JSON.stringify(state.deploymentBinding) !== JSON.stringify(binding)) {
    throw new WhatsAppCatalogFullReconciliationError(
      "RECONCILIATION_DEPLOYMENT_BINDING_MISMATCH",
    );
  }
  if (state.status !== "running") {
    throw new WhatsAppCatalogFullReconciliationError(
      "RECONCILIATION_RECOVERY_NOT_AVAILABLE",
    );
  }
  if (
    !/^[a-f0-9]{64}$/.test(expectedDigest) ||
    expectedDigest !== state.continuationStateDigestSha256
  ) {
    throw new WhatsAppCatalogFullReconciliationError(
      "RECONCILIATION_RECOVERY_DIGEST_MISMATCH",
    );
  }
  const page = await executePage({
    cycleId: state.cycleId,
    cursorPath: state.cursorPath,
    pageSize: state.pageSize,
    deploymentBinding: binding,
  });
  const {
    merchantCompleteness: _merchant,
    nextCursorPath: _cursor,
    ...safe
  } = {
    ...page,
    ...binding,
  };
  void _merchant;
  void _cursor;
  if (page.outcome === "complete") return safe;
  const next = await readRecoveryState(binding);
  return {
    ...safe,
    continuationStateDigestSha256: next.continuationStateDigestSha256,
  };
}

async function startBoundWhatsAppCatalogFullReconciliationPage(input: {
  expectedAppCommit: unknown;
  expectedTargetConfigurationDigestSha256: unknown;
  pageSize?: number;
}): Promise<WhatsAppCatalogOperatorReconciliationPage> {
  const page = await runBoundWhatsAppCatalogFullReconciliationPage(input);
  const {
    merchantCompleteness: _merchant,
    nextCursorPath: _cursor,
    ...safe
  } = page;
  void _merchant;
  void _cursor;
  if (page.outcome === "complete") return safe;
  const binding: WhatsAppCatalogDeploymentBinding = {
    deployedAppCommit: page.deployedAppCommit,
    targetConfigurationDigestSha256: page.targetConfigurationDigestSha256,
    firebaseProjectId: page.firebaseProjectId,
    catalogId: page.catalogId,
    senderPhoneNumberId: page.senderPhoneNumberId,
  };
  const next = await currentRecoveryState(binding);
  return {
    ...safe,
    continuationStateDigestSha256: next.continuationStateDigestSha256,
  };
}

/**
 * Authenticated operator path. Mutating start/continue operations are blocked
 * while delivery is on; the two inspection operations remain strictly read-only.
 */
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
      // This check intentionally precedes every state read, enqueue, or write.
      // A stale/partial/wrong-target deployment therefore cannot start or
      // advance a reconciliation cycle.
      const operation = String(req.body?.operation ?? "start").trim();
      if (
        req.body?.cycleId !== undefined ||
        req.body?.cursorPath !== undefined
      ) {
        res.status(400).json({
          outcome: "rejected",
          reason: "caller_owned_recovery_state_forbidden",
          code: "CALLER_OWNED_RECOVERY_STATE_FORBIDDEN",
        });
        return;
      }
      const binding = {
        expectedAppCommit: req.body?.expectedAppCommit,
        expectedTargetConfigurationDigestSha256:
          req.body?.expectedTargetConfigurationDigestSha256,
      };
      if (operation === "inspect_recovery") {
        const recovery =
          await inspectBoundWhatsAppCatalogReconciliationRecovery(binding);
        res.status(200).json(recovery);
        return;
      }
      if (operation === "inspect_current_stability") {
        const current = await inspectBoundWhatsAppCatalogCurrentStability({
          ...binding,
          expectedCycleId: req.body?.expectedCycleId,
          expectedCompletionReceiptHashSha256:
            req.body?.expectedCompletionReceiptHashSha256,
          expectedMutationGenerationDigestSha256:
            req.body?.expectedMutationGenerationDigestSha256,
        });
        res.status(200).json(current);
        return;
      }
      const result =
        operation === "continue"
          ? await continueBoundWhatsAppCatalogFullReconciliationPage({
              ...binding,
              expectedContinuationStateDigestSha256:
                req.body?.expectedContinuationStateDigestSha256,
            })
          : operation === "start"
            ? await startBoundWhatsAppCatalogFullReconciliationPage({
                ...binding,
                pageSize: req.body?.pageSize,
              })
            : null;
      if (!result) {
        res.status(400).json({
          outcome: "rejected",
          reason: "operation_invalid",
          code: "RECONCILIATION_OPERATION_INVALID",
        });
        return;
      }
      res.status(200).json(result);
    } catch (error) {
      if (
        error instanceof Error &&
        error.message === "WHATSAPP_CATALOG_DEPLOYMENT_BINDING_MISMATCH"
      ) {
        res.status(409).json({
          outcome: "rejected",
          reason: "deployment_binding_mismatch",
          code: "WHATSAPP_CATALOG_DEPLOYMENT_BINDING_MISMATCH",
        });
        return;
      }
      if (error instanceof WhatsAppCatalogFullReconciliationError) {
        const status = error.code.includes("REQUIRED")
          ? 503
          : error.code.includes("EXPECTATION_INVALID")
            ? 400
            : 409;
        res.status(status).json({
          outcome: "rejected",
          reason: error.code.toLowerCase(),
          code: error.code,
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

export type WhatsAppCatalogReconciliationCleanupEvidence = {
  outcome: "complete" | "partial" | "in_progress";
  retentionMs: number;
  inspectedRuns: number;
  deletedRuns: number;
  deletedMerchantMarkers: number;
  skippedCurrentRuns: number;
  skippedIneligibleRuns: number;
  skippedAmbiguousRuns: number;
};

export type WhatsAppCatalogReconciliationCleanupResult =
  WhatsAppCatalogReconciliationCleanupEvidence & {
    evidenceDigestSha256: string;
  };

type WhatsAppCatalogReconciliationCleanupOptions = {
  maxRunInspections?: number;
  maxRunDeletes?: number;
  maxMerchantMarkerDeletes?: number;
};

type WhatsAppCatalogReconciliationCleanupDependencies = {
  /** Test seam: production callers never provide a candidate hook. */
  beforeCandidateRecheck?: (cycleId: string) => Promise<void>;
};

type ReconciliationCleanupLease = {
  operationId: string;
  cursorCycleId: string;
  activeCycleId: string;
};

type ReconciliationCleanupCandidateStep = {
  disposition:
    | "deleted"
    | "markers_deleted"
    | "missing"
    | "current"
    | "ineligible"
    | "ambiguous";
  deletedMerchantMarkers: number;
};

function boundedCleanupWorkLimit(
  value: unknown,
  fallback: number,
  maximum: number,
): number {
  if (value === undefined) return fallback;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 1 || parsed > maximum) {
    throw new Error("WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_LIMIT_INVALID");
  }
  return parsed;
}

function exactCycleId(value: unknown): string {
  const cycleId = text(value);
  return /^[a-f0-9]{32}$/.test(cycleId) ? cycleId : "";
}

function firestoreTimestampMs(value: unknown): number | null {
  const timestamp = value as { toMillis?: unknown } | null;
  if (!timestamp || typeof timestamp.toMillis !== "function") return null;
  const milliseconds = timestamp.toMillis.call(timestamp);
  return Number.isSafeInteger(milliseconds) && milliseconds > 0
    ? milliseconds
    : null;
}

export function whatsappCatalogReconciliationCleanupEvidenceDigest(
  evidence: WhatsAppCatalogReconciliationCleanupEvidence,
): string {
  if (
    !["complete", "partial", "in_progress"].includes(evidence.outcome) ||
    evidence.retentionMs !== WHATSAPP_CATALOG_RECONCILIATION_RUN_RETENTION_MS ||
    [
      evidence.inspectedRuns,
      evidence.deletedRuns,
      evidence.deletedMerchantMarkers,
      evidence.skippedCurrentRuns,
      evidence.skippedIneligibleRuns,
      evidence.skippedAmbiguousRuns,
    ].some((count) => !Number.isSafeInteger(count) || count < 0)
  ) {
    throw new Error("WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_EVIDENCE_INVALID");
  }
  return createHash("sha256")
    .update(
      JSON.stringify({
        schemaVersion: 1,
        outcome: evidence.outcome,
        retentionMs: evidence.retentionMs,
        inspectedRuns: evidence.inspectedRuns,
        deletedRuns: evidence.deletedRuns,
        deletedMerchantMarkers: evidence.deletedMerchantMarkers,
        skippedCurrentRuns: evidence.skippedCurrentRuns,
        skippedIneligibleRuns: evidence.skippedIneligibleRuns,
        skippedAmbiguousRuns: evidence.skippedAmbiguousRuns,
      }),
    )
    .digest("hex");
}

function cleanupLeaseMatches(
  value: Record<string, unknown>,
  operationId: string,
): boolean {
  return text(value.leaseOwner) === operationId;
}

async function acquireReconciliationCleanupLease(): Promise<
  { acquired: false } | { acquired: true; lease: ReconciliationCleanupLease }
> {
  const cleanupStateRef = db.doc(RECONCILIATION_RUN_CLEANUP_STATE_PATH);
  const operationId = randomBytes(16).toString("hex");
  return db.runTransaction(async (transaction) => {
    const state = await transaction.get(cleanupStateRef);
    const value = state.data() ?? {};
    const nowMs = state.readTime.toMillis();
    const leaseOwner = text(value.leaseOwner);
    const leaseUntilMs = Number(value.leaseUntilMs ?? 0);
    if (
      leaseOwner &&
      (!Number.isSafeInteger(leaseUntilMs) || leaseUntilMs <= 0)
    ) {
      throw new Error("WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_STATE_INVALID");
    }
    if (leaseOwner && leaseUntilMs > nowMs) return { acquired: false };
    const cursorCycleId = value.cursorCycleId
      ? exactCycleId(value.cursorCycleId)
      : "";
    const activeCycleId = value.activeCycleId
      ? exactCycleId(value.activeCycleId)
      : "";
    if (
      (value.cursorCycleId && !cursorCycleId) ||
      (value.activeCycleId && !activeCycleId)
    ) {
      throw new Error("WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_STATE_INVALID");
    }
    transaction.set(
      cleanupStateRef,
      {
        leaseOwner: operationId,
        leaseUntilMs: nowMs + WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_LEASE_MS,
        leaseAcquiredAt: FieldValue.serverTimestamp(),
        leaseAcquiredAtMs: nowMs,
        updatedAt: FieldValue.serverTimestamp(),
        updatedAtMs: nowMs,
        schemaVersion: 1,
      },
      { merge: true },
    );
    return {
      acquired: true,
      lease: { operationId, cursorCycleId, activeCycleId },
    };
  });
}

function reconciliationCleanupCandidateDisposition(input: {
  candidateId: string;
  currentState: FirebaseFirestore.DocumentSnapshot;
  run: FirebaseFirestore.DocumentSnapshot;
}): "eligible" | "missing" | "current" | "ineligible" | "ambiguous" {
  if (!input.run.exists) return "missing";
  const currentCycleId = exactCycleId(input.currentState.data()?.cycleId);
  if (!input.currentState.exists || !currentCycleId) return "ambiguous";
  if (currentCycleId === input.candidateId) return "current";
  const value = input.run.data() ?? {};
  if (
    !exactCycleId(input.candidateId) ||
    exactCycleId(value.cycleId) !== input.candidateId ||
    value.cleanupHold === true ||
    (value.cleanupStatus && text(value.cleanupStatus) !== "deleting")
  ) {
    return "ambiguous";
  }
  if (text(value.status) !== "complete" || text(value.phase) !== "complete") {
    return "ineligible";
  }
  const completedAtMs = Number(value.cycleCompletedAtMs);
  const completedTimestampMs = firestoreTimestampMs(value.cycleCompletedAt);
  const serverReadAtMs = input.run.readTime.toMillis();
  if (
    !Number.isSafeInteger(completedAtMs) ||
    completedAtMs <= 0 ||
    completedTimestampMs === null ||
    Math.abs(completedTimestampMs - completedAtMs) >
      WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS ||
    completedAtMs > serverReadAtMs + WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS
  ) {
    return "ambiguous";
  }
  return completedAtMs <=
    serverReadAtMs - WHATSAPP_CATALOG_RECONCILIATION_RUN_RETENTION_MS
    ? "eligible"
    : "ineligible";
}

async function cleanupReconciliationRunCandidateStep(input: {
  candidateId: string;
  operationId: string;
  markerDeleteBudget: number;
}): Promise<ReconciliationCleanupCandidateStep> {
  const cleanupStateRef = db.doc(RECONCILIATION_RUN_CLEANUP_STATE_PATH);
  const currentStateRef = db.doc(FULL_RECONCILIATION_STATE_PATH);
  const runRef = db.doc(
    `${WHATSAPP_CATALOG_RECONCILIATION_RUNS}/${input.candidateId}`,
  );
  return db.runTransaction(async (transaction) => {
    const [cleanupState, currentState, run] = await Promise.all([
      transaction.get(cleanupStateRef),
      transaction.get(currentStateRef),
      transaction.get(runRef),
    ]);
    if (
      !cleanupState.exists ||
      !cleanupLeaseMatches(cleanupState.data() ?? {}, input.operationId)
    ) {
      throw new Error("WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_LEASE_LOST");
    }
    const disposition = reconciliationCleanupCandidateDisposition({
      candidateId: input.candidateId,
      currentState,
      run,
    });
    if (disposition !== "eligible") {
      if (text(cleanupState.data()?.activeCycleId) === input.candidateId) {
        transaction.set(
          cleanupStateRef,
          { activeCycleId: null, updatedAt: FieldValue.serverTimestamp() },
          { merge: true },
        );
      }
      return { disposition, deletedMerchantMarkers: 0 };
    }

    const markerLimit = Math.min(
      WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_MARKER_BATCH_SIZE,
      input.markerDeleteBudget,
    );
    const markers = await transaction.get(
      runRef
        .collection("merchants")
        .orderBy(FieldPath.documentId())
        .limit(markerLimit),
    );
    const nowMs = run.readTime.toMillis();
    if (markers.empty) {
      transaction.delete(runRef);
      transaction.set(
        cleanupStateRef,
        {
          activeCycleId: null,
          totalDeletedRuns: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
          updatedAtMs: nowMs,
        },
        { merge: true },
      );
      return { disposition: "deleted", deletedMerchantMarkers: 0 };
    }

    for (const marker of markers.docs) transaction.delete(marker.ref);
    transaction.set(
      runRef,
      {
        cleanupStatus: "deleting",
        cleanupDeletedMerchantMarkers: FieldValue.increment(markers.size),
        cleanupUpdatedAt: FieldValue.serverTimestamp(),
        cleanupUpdatedAtMs: nowMs,
      },
      { merge: true },
    );
    transaction.set(
      cleanupStateRef,
      {
        activeCycleId: input.candidateId,
        totalDeletedMerchantMarkers: FieldValue.increment(markers.size),
        updatedAt: FieldValue.serverTimestamp(),
        updatedAtMs: nowMs,
      },
      { merge: true },
    );
    return {
      disposition: "markers_deleted",
      deletedMerchantMarkers: markers.size,
    };
  });
}

async function finalizeReconciliationCleanup(input: {
  operationId: string;
  cursorCycleId: string;
  requestedOutcome: "complete" | "partial";
  evidence: Omit<WhatsAppCatalogReconciliationCleanupEvidence, "outcome">;
}): Promise<WhatsAppCatalogReconciliationCleanupResult> {
  const cleanupStateRef = db.doc(RECONCILIATION_RUN_CLEANUP_STATE_PATH);
  return db.runTransaction(async (transaction) => {
    const state = await transaction.get(cleanupStateRef);
    const value = state.data() ?? {};
    if (!cleanupLeaseMatches(value, input.operationId)) {
      throw new Error("WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_LEASE_LOST");
    }
    const activeCycleId = text(value.activeCycleId);
    const outcome =
      input.requestedOutcome === "complete" && !activeCycleId
        ? "complete"
        : "partial";
    const evidence: WhatsAppCatalogReconciliationCleanupEvidence = {
      outcome,
      ...input.evidence,
    };
    const evidenceDigestSha256 =
      whatsappCatalogReconciliationCleanupEvidenceDigest(evidence);
    const nowMs = state.readTime.toMillis();
    transaction.set(
      cleanupStateRef,
      {
        leaseOwner: null,
        leaseUntilMs: 0,
        cursorCycleId:
          outcome === "complete" ? null : input.cursorCycleId || null,
        lastCleanupEvidence: evidence,
        lastCleanupEvidenceDigestSha256: evidenceDigestSha256,
        lastCleanupAt: FieldValue.serverTimestamp(),
        lastCleanupAtMs: nowMs,
        updatedAt: FieldValue.serverTimestamp(),
        updatedAtMs: nowMs,
        schemaVersion: 1,
      },
      { merge: true },
    );
    return { ...evidence, evidenceDigestSha256 };
  });
}

/**
 * Bounded, resumable cleanup for reconciliation audit runs only. Each marker
 * batch and each parent deletion atomically rechecks the current-cycle pointer,
 * terminal status, server-authored age, cycle identity, and cleanup lease.
 */
export async function cleanupExpiredWhatsAppCatalogReconciliationRuns(
  options: WhatsAppCatalogReconciliationCleanupOptions = {},
  dependencies: WhatsAppCatalogReconciliationCleanupDependencies = {},
): Promise<WhatsAppCatalogReconciliationCleanupResult> {
  const maxRunInspections = boundedCleanupWorkLimit(
    options.maxRunInspections,
    WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_MAX_RUN_INSPECTIONS,
    WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_MAX_RUN_INSPECTIONS,
  );
  const maxRunDeletes = boundedCleanupWorkLimit(
    options.maxRunDeletes,
    WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_MAX_RUN_DELETES,
    WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_MAX_RUN_DELETES,
  );
  const maxMerchantMarkerDeletes = boundedCleanupWorkLimit(
    options.maxMerchantMarkerDeletes,
    WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_MAX_MARKER_DELETES,
    WHATSAPP_CATALOG_RECONCILIATION_CLEANUP_MAX_MARKER_DELETES,
  );
  const acquired = await acquireReconciliationCleanupLease();
  const emptyEvidence = {
    retentionMs: WHATSAPP_CATALOG_RECONCILIATION_RUN_RETENTION_MS,
    inspectedRuns: 0,
    deletedRuns: 0,
    deletedMerchantMarkers: 0,
    skippedCurrentRuns: 0,
    skippedIneligibleRuns: 0,
    skippedAmbiguousRuns: 0,
  };
  if (!acquired.acquired) {
    const evidence = { outcome: "in_progress" as const, ...emptyEvidence };
    return {
      ...evidence,
      evidenceDigestSha256:
        whatsappCatalogReconciliationCleanupEvidenceDigest(evidence),
    };
  }

  const { lease } = acquired;
  const evidence = { ...emptyEvidence };
  let cursorCycleId = lease.cursorCycleId;
  let requestedOutcome: "complete" | "partial" = "partial";
  let stoppedEarly = false;

  const processCandidate = async (candidateId: string): Promise<boolean> => {
    evidence.inspectedRuns += 1;
    await dependencies.beforeCandidateRecheck?.(candidateId);
    while (
      evidence.deletedRuns < maxRunDeletes &&
      evidence.deletedMerchantMarkers < maxMerchantMarkerDeletes
    ) {
      const step = await cleanupReconciliationRunCandidateStep({
        candidateId,
        operationId: lease.operationId,
        markerDeleteBudget:
          maxMerchantMarkerDeletes - evidence.deletedMerchantMarkers,
      });
      evidence.deletedMerchantMarkers += step.deletedMerchantMarkers;
      if (step.disposition === "markers_deleted") continue;
      if (step.disposition === "deleted") evidence.deletedRuns += 1;
      if (step.disposition === "current") evidence.skippedCurrentRuns += 1;
      if (step.disposition === "ineligible") {
        evidence.skippedIneligibleRuns += 1;
      }
      if (step.disposition === "ambiguous") {
        evidence.skippedAmbiguousRuns += 1;
      }
      return true;
    }
    return false;
  };

  if (lease.activeCycleId) {
    const finished = await processCandidate(lease.activeCycleId);
    stoppedEarly = !finished;
    cursorCycleId = lease.activeCycleId;
  } else {
    let query = db
      .collection(WHATSAPP_CATALOG_RECONCILIATION_RUNS)
      .orderBy(FieldPath.documentId())
      .limit(maxRunInspections);
    if (cursorCycleId) query = query.startAfter(cursorCycleId);
    const candidates = await query.get();
    let processed = 0;
    for (const candidate of candidates.docs) {
      if (
        evidence.deletedRuns >= maxRunDeletes ||
        evidence.deletedMerchantMarkers >= maxMerchantMarkerDeletes
      ) {
        stoppedEarly = true;
        break;
      }
      cursorCycleId = candidate.id;
      processed += 1;
      const finished = await processCandidate(candidate.id);
      if (!finished) {
        stoppedEarly = true;
        break;
      }
    }
    requestedOutcome =
      !stoppedEarly &&
      processed === candidates.size &&
      candidates.size < maxRunInspections
        ? "complete"
        : "partial";
  }

  return finalizeReconciliationCleanup({
    operationId: lease.operationId,
    cursorCycleId,
    requestedOutcome: stoppedEarly ? "partial" : requestedOutcome,
    evidence,
  });
}

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

export async function runWhatsAppCatalogScheduledMaintenance(): Promise<{
  reconciliation: Awaited<
    ReturnType<typeof runWhatsAppCatalogReconciliationOnce>
  >;
  cleanup: WhatsAppCatalogReconciliationCleanupResult;
}> {
  const reconciliation = await runWhatsAppCatalogReconciliationOnce();
  const cleanup = await cleanupExpiredWhatsAppCatalogReconciliationRuns();
  return { reconciliation, cleanup };
}

/** Safety net for missed triggers; product writes still enqueue immediately. */
export const reconcileWhatsAppMerchantCatalog = functions
  .runWith({ timeoutSeconds: 240, memory: "512MB", maxInstances: 1 })
  .pubsub.schedule("every 24 hours")
  .timeZone("Africa/Johannesburg")
  .onRun(() => runWhatsAppCatalogScheduledMaintenance());
