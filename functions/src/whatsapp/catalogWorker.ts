import { randomBytes } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import {
  WhatsAppCatalogRuntimeConfig,
  whatsappCatalogMerchantAllowed,
  whatsappCatalogRuntimeConfig,
} from "./catalogConfig";
import { probeCatalogImageUrl } from "./catalogImage";
import {
  WHATSAPP_CATALOG_MAPPINGS,
  WHATSAPP_CATALOG_OUTBOX,
} from "./catalogQueue";
import { MerchantCatalogProjection } from "./catalogProjection";
import {
  MetaCatalogBatchStatus,
  MetaCatalogMutation,
  MetaCatalogProviderError,
  checkMetaCatalogBatch,
  submitMetaCatalogBatch,
} from "./metaCatalogClient";

const WORKER_LEASE_MS = 90 * 1000;
const MAX_ATTEMPTS = 5;
const MAX_STATUS_CHECKS = 20;
const MAX_STATUS_HANDLES_PER_RUN = 2;

type CatalogAction = "upsert" | "delete";

type CatalogOutboxValue = {
  merchantId?: unknown;
  productId?: unknown;
  retailerId?: unknown;
  status?: unknown;
  attempts?: unknown;
  availableAtMs?: unknown;
  leaseUntilMs?: unknown;
  claimToken?: unknown;
  desiredRevision?: unknown;
  desiredAction?: unknown;
  desiredProjection?: unknown;
  lastAppliedRevision?: unknown;
  processingRevision?: unknown;
  processingAction?: unknown;
  processingProjection?: unknown;
  batchHandle?: unknown;
  nextCheckAtMs?: unknown;
  statusCheckAttempts?: unknown;
};

type ClaimedCatalogJob = {
  ref: FirebaseFirestore.DocumentReference;
  merchantId: string;
  retailerId: string;
  revision: string;
  action: CatalogAction;
  projection: MerchantCatalogProjection | null;
  claimToken: string;
  attempts: number;
};

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function action(value: unknown): CatalogAction | null {
  return value === "upsert" || value === "delete" ? value : null;
}

function projection(value: unknown): MerchantCatalogProjection | null {
  if (!value || typeof value !== "object") return null;
  const item = value as MerchantCatalogProjection;
  return text(item.retailerId) && text(item.imageUrl) && item.priceMinor > 0
    ? item
    : null;
}

export function catalogRetryDelayMs(attempts: number): number {
  const exponent = Math.max(0, Math.min(5, attempts - 1));
  return Math.min(15 * 60 * 1000, 30 * 1000 * Math.pow(2, exponent));
}

async function recoverExpiredClaims(nowMs: number): Promise<number> {
  const snapshot = await db
    .collection(WHATSAPP_CATALOG_OUTBOX)
    .where("status", "==", "processing")
    .limit(500)
    .get();
  const expired = snapshot.docs.filter(
    (doc) => Number(doc.data().leaseUntilMs ?? 0) <= nowMs,
  );
  if (!expired.length) return 0;
  const batch = db.batch();
  for (const doc of expired) {
    const attempts = Number(doc.data().attempts ?? 1);
    batch.set(
      doc.ref,
      {
        status: attempts >= MAX_ATTEMPTS ? "failed" : "retry",
        availableAtMs:
          attempts >= MAX_ATTEMPTS ? 0 : nowMs + catalogRetryDelayMs(attempts),
        claimToken: null,
        leaseUntilMs: 0,
        processingRevision: null,
        processingAction: null,
        processingProjection: null,
        lastErrorCode: "CATALOG_WORKER_LEASE_EXPIRED",
        updatedAt: FieldValue.serverTimestamp(),
        updatedAtMs: nowMs,
      },
      { merge: true },
    );
  }
  await batch.commit();
  return expired.length;
}

async function dueCandidates(
  config: WhatsAppCatalogRuntimeConfig,
  nowMs: number,
): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const [pending, retry] = await Promise.all([
    db
      .collection(WHATSAPP_CATALOG_OUTBOX)
      .where("status", "==", "pending")
      .limit(1000)
      .get(),
    db
      .collection(WHATSAPP_CATALOG_OUTBOX)
      .where("status", "==", "retry")
      .limit(1000)
      .get(),
  ]);
  return [...pending.docs, ...retry.docs]
    .filter((doc) => {
      const value = doc.data();
      return (
        whatsappCatalogMerchantAllowed(
          config,
          String(value.merchantId ?? ""),
        ) && Number(value.availableAtMs ?? 0) <= nowMs
      );
    })
    .sort(
      (a, b) =>
        Number(a.data().updatedAtMs ?? 0) - Number(b.data().updatedAtMs ?? 0),
    )
    .slice(0, config.maxBatchSize);
}

async function claimJob(
  candidate: FirebaseFirestore.QueryDocumentSnapshot,
  nowMs: number,
): Promise<ClaimedCatalogJob | null> {
  const claimToken = randomBytes(16).toString("hex");
  return db.runTransaction(async (tx) => {
    const snapshot = await tx.get(candidate.ref);
    const value = snapshot.data() as CatalogOutboxValue | undefined;
    if (!value || !["pending", "retry"].includes(String(value.status ?? ""))) {
      return null;
    }
    if (Number(value.availableAtMs ?? 0) > nowMs) return null;
    const desiredAction = action(value.desiredAction);
    const revision = text(value.desiredRevision);
    const merchantId = text(value.merchantId);
    const retailerId = text(value.retailerId);
    const desiredProjection = projection(value.desiredProjection);
    if (!desiredAction || !revision || !merchantId || !retailerId) return null;
    if (desiredAction === "upsert" && !desiredProjection) return null;
    const attempts = Number(value.attempts ?? 0) + 1;
    if (attempts > MAX_ATTEMPTS) return null;
    tx.set(
      candidate.ref,
      {
        status: "processing",
        attempts,
        claimToken,
        leaseUntilMs: nowMs + WORKER_LEASE_MS,
        processingRevision: revision,
        processingAction: desiredAction,
        processingProjection: desiredProjection,
        updatedAt: FieldValue.serverTimestamp(),
        updatedAtMs: nowMs,
      },
      { merge: true },
    );
    return {
      ref: candidate.ref,
      merchantId,
      retailerId,
      revision,
      action: desiredAction,
      projection: desiredProjection,
      claimToken,
      attempts,
    };
  });
}

async function finishClaim(
  job: ClaimedCatalogJob,
  requestedStatus: "blocked" | "rejected" | "retry",
  errorCode: string,
): Promise<void> {
  const nowMs = Date.now();
  await db.runTransaction(async (tx) => {
    const [outbox, mapping] = await Promise.all([
      tx.get(job.ref),
      tx.get(db.doc(`${WHATSAPP_CATALOG_MAPPINGS}/${job.retailerId}`)),
    ]);
    const value = outbox.data() as CatalogOutboxValue | undefined;
    if (text(value?.claimToken) !== job.claimToken) return;
    const newerDesired = text(value?.desiredRevision) !== job.revision;
    const exhausted =
      requestedStatus === "retry" && job.attempts >= MAX_ATTEMPTS;
    const status = newerDesired
      ? "pending"
      : exhausted
        ? "failed"
        : requestedStatus;
    tx.set(
      job.ref,
      {
        status,
        attempts: newerDesired ? 0 : job.attempts,
        availableAtMs:
          status === "retry" ? nowMs + catalogRetryDelayMs(job.attempts) : 0,
        claimToken: null,
        leaseUntilMs: 0,
        processingRevision: null,
        processingAction: null,
        processingProjection: null,
        lastErrorCode: errorCode.slice(0, 100),
        updatedAt: FieldValue.serverTimestamp(),
        updatedAtMs: nowMs,
      },
      { merge: true },
    );
    if (mapping.data()?.desiredRevision === job.revision) {
      tx.set(
        mapping.ref,
        {
          status: exhausted ? "failed" : requestedStatus,
          lastErrorCode: errorCode.slice(0, 100),
          updatedAt: FieldValue.serverTimestamp(),
          updatedAtMs: nowMs,
        },
        { merge: true },
      );
    }
  });
}

async function validateClaimImages(
  jobs: readonly ClaimedCatalogJob[],
): Promise<ClaimedCatalogJob[]> {
  const ready = new Set<string>();
  const cache = new Map<string, ReturnType<typeof probeCatalogImageUrl>>();
  let next = 0;
  const workers = Array.from({ length: Math.min(3, jobs.length) }, async () => {
    while (next < jobs.length) {
      const job = jobs[next++];
      if (job.action === "delete") {
        ready.add(job.retailerId);
        continue;
      }
      const imageUrl = job.projection?.imageUrl ?? "";
      if (!cache.has(imageUrl)) {
        cache.set(imageUrl, probeCatalogImageUrl(imageUrl));
      }
      const pending = cache.get(imageUrl) ?? probeCatalogImageUrl(imageUrl);
      cache.set(imageUrl, pending);
      const result = await pending;
      if (result.state === "valid") {
        ready.add(job.retailerId);
      } else {
        await finishClaim(
          job,
          result.state === "transient" ? "retry" : "blocked",
          result.code,
        );
      }
    }
  });
  await Promise.all(workers);
  return jobs.filter((job) => ready.has(job.retailerId));
}

function mutation(job: ClaimedCatalogJob): MetaCatalogMutation {
  if (job.action === "delete") {
    return { action: "delete", retailerId: job.retailerId };
  }
  if (!job.projection) throw new Error("META_CATALOG_PROJECTION_MISSING");
  return {
    action: "upsert",
    retailerId: job.retailerId,
    projection: job.projection,
  };
}

async function markSubmitted(
  jobs: readonly ClaimedCatalogJob[],
  handle: string,
  config: WhatsAppCatalogRuntimeConfig,
): Promise<void> {
  const nowMs = Date.now();
  await Promise.all(
    jobs.map((job) =>
      db.runTransaction(async (tx) => {
        const [outbox, mapping] = await Promise.all([
          tx.get(job.ref),
          tx.get(db.doc(`${WHATSAPP_CATALOG_MAPPINGS}/${job.retailerId}`)),
        ]);
        const value = outbox.data() as CatalogOutboxValue | undefined;
        if (text(value?.claimToken) !== job.claimToken) return;
        tx.set(
          job.ref,
          {
            status: "submitted",
            claimToken: null,
            leaseUntilMs: 0,
            batchHandle: handle,
            nextCheckAtMs: config.providerMode === "stub" ? 0 : nowMs + 30_000,
            statusCheckAttempts: 0,
            lastErrorCode: null,
            updatedAt: FieldValue.serverTimestamp(),
            updatedAtMs: nowMs,
          },
          { merge: true },
        );
        if (mapping.data()?.desiredRevision === job.revision) {
          tx.set(
            mapping.ref,
            {
              status: "submitted",
              lastSubmittedRevision: job.revision,
              batchHandle: handle,
              updatedAt: FieldValue.serverTimestamp(),
              updatedAtMs: nowMs,
            },
            { merge: true },
          );
        }
      }),
    ),
  );
}

async function submitClaimedJobs(
  jobs: readonly ClaimedCatalogJob[],
  config: WhatsAppCatalogRuntimeConfig,
): Promise<number> {
  if (!jobs.length) return 0;
  try {
    const result = await submitMetaCatalogBatch(jobs.map(mutation), config);
    await markSubmitted(jobs, result.handle, config);
    return jobs.length;
  } catch (error) {
    const provider =
      error instanceof MetaCatalogProviderError
        ? error
        : new MetaCatalogProviderError("META_CATALOG_SUBMISSION_FAILED", true);
    await Promise.all(
      jobs.map((job) =>
        finishClaim(
          job,
          provider.retryable ? "retry" : "rejected",
          provider.providerCode,
        ),
      ),
    );
    return 0;
  }
}

async function submittedForHandle(
  handle: string,
): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const snapshot = await db
    .collection(WHATSAPP_CATALOG_OUTBOX)
    .where("batchHandle", "==", handle)
    .limit(500)
    .get();
  return snapshot.docs.filter((doc) => doc.data().status === "submitted");
}

async function deferBatchStatus(
  docs: readonly FirebaseFirestore.QueryDocumentSnapshot[],
  errorCode: string | null,
): Promise<void> {
  const nowMs = Date.now();
  await Promise.all(
    docs.map((doc) =>
      db.runTransaction(async (tx) => {
        const snapshot = await tx.get(doc.ref);
        const value = snapshot.data() as CatalogOutboxValue | undefined;
        if (value?.status !== "submitted") return;
        const checks = Number(value.statusCheckAttempts ?? 0) + 1;
        const retrySubmission = checks >= MAX_STATUS_CHECKS;
        tx.set(
          doc.ref,
          {
            status: retrySubmission ? "retry" : "submitted",
            attempts: retrySubmission
              ? Number(value.attempts ?? 1)
              : value.attempts,
            availableAtMs: retrySubmission
              ? nowMs + catalogRetryDelayMs(Number(value.attempts ?? 1))
              : 0,
            nextCheckAtMs: retrySubmission
              ? 0
              : nowMs +
                Math.min(
                  5 * 60 * 1000,
                  30_000 * Math.pow(2, Math.min(4, checks - 1)),
                ),
            statusCheckAttempts: checks,
            batchHandle: retrySubmission ? null : value.batchHandle,
            processingRevision: retrySubmission
              ? null
              : value.processingRevision,
            processingAction: retrySubmission ? null : value.processingAction,
            processingProjection: retrySubmission
              ? null
              : value.processingProjection,
            lastErrorCode: errorCode,
            updatedAt: FieldValue.serverTimestamp(),
            updatedAtMs: nowMs,
          },
          { merge: true },
        );
      }),
    ),
  );
}

async function finishSubmittedJob(
  doc: FirebaseFirestore.QueryDocumentSnapshot,
  result: MetaCatalogBatchStatus,
): Promise<void> {
  const nowMs = Date.now();
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(doc.ref);
    const value = snapshot.data() as CatalogOutboxValue | undefined;
    const handle = text(value?.batchHandle);
    if (value?.status !== "submitted" || handle !== result.handle) return;
    const retailerId = text(value.retailerId);
    const processingRevision = text(value.processingRevision);
    const processingAction = action(value.processingAction);
    if (!retailerId || !processingRevision || !processingAction) return;
    const mappingRef = db.doc(`${WHATSAPP_CATALOG_MAPPINGS}/${retailerId}`);
    const mapping = await tx.get(mappingRef);
    const invalid =
      result.invalidRetailerIds.has(retailerId) ||
      (result.errors > 0 && result.invalidRetailerIds.size === 0);
    const newerDesired = text(value.desiredRevision) !== processingRevision;
    const terminalStatus = invalid
      ? "rejected"
      : processingAction === "delete"
        ? "deleted"
        : "active";
    tx.set(
      doc.ref,
      {
        status: newerDesired ? "pending" : terminalStatus,
        attempts: newerDesired ? 0 : value.attempts,
        availableAtMs: 0,
        processingRevision: null,
        processingAction: null,
        processingProjection: null,
        batchHandle: null,
        nextCheckAtMs: 0,
        statusCheckAttempts: 0,
        lastAppliedRevision: invalid
          ? (value.lastAppliedRevision ?? null)
          : processingRevision,
        lastErrorCode: invalid ? "META_CATALOG_ITEM_REJECTED" : null,
        providerWarnings: result.warnings,
        updatedAt: FieldValue.serverTimestamp(),
        updatedAtMs: nowMs,
      },
      { merge: true },
    );
    const mappingFields: Record<string, unknown> = {
      lastProviderCheckedAt: FieldValue.serverTimestamp(),
      providerWarnings: result.warnings,
      updatedAt: FieldValue.serverTimestamp(),
      updatedAtMs: nowMs,
    };
    if (!invalid) {
      mappingFields.lastAppliedRevision = processingRevision;
      mappingFields.lastAcceptedAt = FieldValue.serverTimestamp();
      mappingFields.lastErrorCode = null;
    } else {
      mappingFields.lastErrorCode = "META_CATALOG_ITEM_REJECTED";
    }
    if (
      !newerDesired &&
      mapping.data()?.desiredRevision === processingRevision
    ) {
      mappingFields.status = terminalStatus;
      mappingFields.metaPolicyStatus = invalid
        ? "rejected"
        : processingAction === "delete"
          ? "removed"
          : "accepted";
    }
    tx.set(mappingRef, mappingFields, { merge: true });
  });
}

async function reconcileHandle(
  handle: string,
  config: WhatsAppCatalogRuntimeConfig,
): Promise<number> {
  const docs = await submittedForHandle(handle);
  if (!docs.length) return 0;
  try {
    const result = await checkMetaCatalogBatch(handle, config);
    if (result.state === "pending") {
      await deferBatchStatus(docs, null);
      return 0;
    }
    await Promise.all(docs.map((doc) => finishSubmittedJob(doc, result)));
    return docs.length;
  } catch (error) {
    const provider =
      error instanceof MetaCatalogProviderError
        ? error
        : new MetaCatalogProviderError("META_CATALOG_STATUS_FAILED", true);
    if (provider.retryable) {
      await deferBatchStatus(docs, provider.providerCode);
    } else {
      const rejected: MetaCatalogBatchStatus = {
        state: "complete",
        handle,
        invalidRetailerIds: new Set(
          docs.map((doc) => String(doc.data().retailerId ?? "")),
        ),
        errors: docs.length,
        warnings: 0,
      };
      await Promise.all(docs.map((doc) => finishSubmittedJob(doc, rejected)));
    }
    return 0;
  }
}

async function reconcileSubmittedBatches(
  config: WhatsAppCatalogRuntimeConfig,
): Promise<number> {
  const nowMs = Date.now();
  const snapshot = await db
    .collection(WHATSAPP_CATALOG_OUTBOX)
    .where("status", "==", "submitted")
    .limit(500)
    .get();
  const handles = [
    ...new Set(
      snapshot.docs
        .filter(
          (doc) =>
            Number(doc.data().nextCheckAtMs ?? 0) <= nowMs &&
            whatsappCatalogMerchantAllowed(
              config,
              String(doc.data().merchantId ?? ""),
            ),
        )
        .map((doc) => text(doc.data().batchHandle))
        .filter(Boolean),
    ),
  ].slice(0, MAX_STATUS_HANDLES_PER_RUN);
  const counts = await Promise.all(
    handles.map((handle) => reconcileHandle(handle, config)),
  );
  return counts.reduce((sum, count) => sum + count, 0);
}

export async function runWhatsAppCatalogWorkerOnce(): Promise<{
  disabled: boolean;
  submitted: number;
  reconciled: number;
}> {
  const config = whatsappCatalogRuntimeConfig();
  if (!config.syncEnabled)
    return { disabled: true, submitted: 0, reconciled: 0 };
  const reconciled = await reconcileSubmittedBatches(config);
  const nowMs = Date.now();
  await recoverExpiredClaims(nowMs);
  const candidates = await dueCandidates(config, nowMs);
  const claimed: ClaimedCatalogJob[] = [];
  for (const candidate of candidates) {
    const job = await claimJob(candidate, nowMs);
    if (job) claimed.push(job);
  }
  const valid = await validateClaimImages(claimed);
  const submitted = await submitClaimedJobs(valid, config);
  return { disabled: false, submitted, reconciled };
}

/** One bounded Meta batch per minute, with provider status checks first. */
export const syncWhatsAppMerchantCatalog = functions
  .runWith({
    secrets: ["META_CATALOG_ACCESS_TOKEN"],
    timeoutSeconds: 180,
    memory: "512MB",
    maxInstances: 1,
  })
  .pubsub.schedule("every 1 minutes")
  .timeZone("Africa/Johannesburg")
  .onRun(runWhatsAppCatalogWorkerOnce);
