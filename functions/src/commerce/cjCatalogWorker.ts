import { db, functions } from "../config/main";
import {
  buildCatalogCacheDocument,
  CATALOG_NEGATIVE_REFRESH_MS,
} from "./cjCatalogCache";
import {
  CjCatalogProduct,
  findCjProductZaDelivery,
  searchCjProducts,
} from "./cjClient";
import {
  CATALOG_JOBS_COLLECTION,
  CatalogJob,
  advanceCatalogDiscoveryPage,
  catalogProductRef,
  enqueueCatalogDemand,
  enqueueProductRefresh,
} from "./cjCatalogRepository";

const WORKER_LEASE_MS = 2 * 60 * 1000;
const RETRY_BASE_MS = 5 * 60 * 1000;
const MAX_ATTEMPTS = 5;
const MAX_JOBS_PER_RUN = 1;
const MAX_RUN_MS = 90 * 1000;
// CJ currently grants 50,000 base points per UTC day. Keep 14,000 points
// outside catalogue work for buyer/order quotes while allowing the bounded
// five-minute worker to run throughout the day.
export const DAILY_CATALOG_POINT_BUDGET = 36_000;
const CATALOG_BUDGET_PATH = "supplierIntegrationState/cjCatalogBudget";
export const ROTATING_DISCOVERY_INTERVAL_MS = 2 * 60 * 60 * 1000;
const DEFAULT_DISCOVERY_QUERIES = [
  "popular",
  "fashion",
  "home",
  "beauty",
  "electronics",
  "baby",
  "accessories",
];
const WORKER_STATE_PATH = "supplierIntegrationState/cjCatalogWorker";

type ClaimedJob = {
  id: string;
  ref: FirebaseFirestore.DocumentReference;
  value: CatalogJob;
};

function utcCalendarDay(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10);
}

export function estimatedCatalogJobPoints(kind: CatalogJob["kind"]): number {
  // CJ's free-tier point table currently charges 50 for product discovery and
  // 10 for each detail, variant, stock or freight request. A refresh is bounded
  // to two attempted variants and four possible stock origins.
  return kind === "discover_query" ? 50 : 130;
}

export function catalogRefreshPriority(discoveryPriority: number): number {
  return Math.min(35, discoveryPriority - 5);
}

export function catalogQueueOrder(
  rotatingDiscoveryQueued: boolean,
): readonly CatalogJob["queueBand"][] {
  return rotatingDiscoveryQueued
    ? ["demand", "background", "refresh"]
    : ["demand", "refresh", "background"];
}

function asCatalogProduct(value: unknown): CjCatalogProduct | null {
  if (!value || typeof value !== "object") return null;
  const product = value as Partial<CjCatalogProduct>;
  const productId = String(product.productId ?? "").trim();
  const title = String(product.title ?? "").trim();
  if (!productId || !title) return null;
  return {
    productId,
    productSku: String(product.productSku ?? ""),
    title,
    image: String(product.image ?? ""),
    category: String(product.category ?? ""),
    productCostUsdMinor: Number(product.productCostUsdMinor ?? 0),
    estimatedProductCostMinor: Number(product.estimatedProductCostMinor ?? 0),
  };
}

function availabilityFailure(error: unknown): boolean {
  const code = error instanceof Error ? error.message : "";
  return [
    "CJ_NO_SHIPPING_TO_ZA",
    "CJ_OUT_OF_STOCK",
    "CJ_PRODUCT_UNAVAILABLE",
    "CJ_PRODUCT_INVALID",
    "CJ_VARIANT_INVALID",
    "CJ_VARIANTS_UNAVAILABLE",
  ].includes(code);
}

async function recoverExpiredJobs(nowMs: number): Promise<void> {
  const snapshot = await db
    .collection(CATALOG_JOBS_COLLECTION)
    .where("status", "==", "working")
    .limit(20)
    .get();
  const expired = snapshot.docs.filter(
    (doc) => Number(doc.data().leaseUntilMs ?? 0) <= nowMs,
  );
  if (!expired.length) return;
  const batch = db.batch();
  expired.forEach((doc) => {
    const queueBand = String(doc.data().queueBand ?? "background");
    batch.set(
      doc.ref,
      {
        status: "pending",
        pendingQueueBand: ["demand", "refresh", "background"].includes(
          queueBand,
        )
          ? queueBand
          : "background",
        leaseUntilMs: 0,
        updatedAtMs: nowMs,
      },
      { merge: true },
    );
  });
  await batch.commit();
}

async function recoverDueRetryJobs(nowMs: number): Promise<void> {
  const snapshot = await db
    .collection(CATALOG_JOBS_COLLECTION)
    .where("status", "==", "retry")
    .limit(500)
    .get();
  const due = snapshot.docs.filter(
    (doc) => Number(doc.data().availableAtMs ?? 0) <= nowMs,
  );
  if (!due.length) return;
  const batch = db.batch();
  due.forEach((doc) => {
    const queueBand = String(doc.data().queueBand ?? "background");
    batch.set(
      doc.ref,
      {
        status: "pending",
        pendingQueueBand: ["demand", "refresh", "background"].includes(
          queueBand,
        )
          ? queueBand
          : "background",
        updatedAtMs: nowMs,
      },
      { merge: true },
    );
  });
  await batch.commit();
}

async function claimNextJob(
  queueOrder: readonly CatalogJob["queueBand"][] = [
    "demand",
    "refresh",
    "background",
  ],
): Promise<ClaimedJob | null> {
  const nowMs = Date.now();
  await Promise.all([recoverExpiredJobs(nowMs), recoverDueRetryJobs(nowMs)]);
  for (const queueBand of queueOrder) {
    const snapshot = await db
      .collection(CATALOG_JOBS_COLLECTION)
      .where("pendingQueueBand", "==", queueBand)
      .limit(30)
      .get();
    const candidates = snapshot.docs.sort((a, b) => {
      const priority =
        Number(b.data().priority ?? 0) - Number(a.data().priority ?? 0);
      return (
        priority ||
        Number(a.data().createdAtMs ?? 0) - Number(b.data().createdAtMs ?? 0)
      );
    });
    for (const candidate of candidates) {
      const claimed = await db.runTransaction(async (tx) => {
        const latest = await tx.get(candidate.ref);
        const value = latest.data() as CatalogJob | undefined;
        if (
          !value ||
          value.status !== "pending" ||
          value.queueBand !== queueBand
        ) {
          return null;
        }
        const attempts = Number(value.attempts ?? 0) + 1;
        tx.set(
          candidate.ref,
          {
            status: "working",
            pendingQueueBand: null,
            attempts,
            leaseUntilMs: nowMs + WORKER_LEASE_MS,
            updatedAtMs: nowMs,
          },
          { merge: true },
        );
        return { ...value, status: "working" as const, attempts };
      });
      if (claimed) {
        return { id: candidate.id, ref: candidate.ref, value: claimed };
      }
    }
  }
  return null;
}

async function reserveCatalogBudget(job: ClaimedJob): Promise<boolean> {
  const nowMs = Date.now();
  // CJ resets its provider point allowance at midnight UTC.
  const day = utcCalendarDay(nowMs);
  const estimate = estimatedCatalogJobPoints(job.value.kind);
  const ref = db.doc(CATALOG_BUDGET_PATH);
  return db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const sameDay = String(snapshot.data()?.day ?? "") === day;
    const used = sameDay ? Number(snapshot.data()?.estimatedPoints ?? 0) : 0;
    if (used + estimate > DAILY_CATALOG_POINT_BUDGET) return false;
    tx.set(
      ref,
      {
        day,
        estimatedPoints: used + estimate,
        lastReservedAtMs: nowMs,
        schemaVersion: 1,
      },
      { merge: true },
    );
    return true;
  });
}

async function deferForCatalogBudget(job: ClaimedJob): Promise<void> {
  const nowMs = Date.now();
  await job.ref.set(
    {
      status: "retry",
      pendingQueueBand: null,
      attempts: Math.max(0, Number(job.value.attempts ?? 1) - 1),
      leaseUntilMs: 0,
      availableAtMs: nowMs + 60 * 60 * 1000,
      updatedAtMs: nowMs,
      lastErrorCode: "CJ_CATALOG_DAILY_BUDGET",
    },
    { merge: true },
  );
}

async function completeJob(job: ClaimedJob): Promise<void> {
  const nowMs = Date.now();
  await job.ref.set(
    {
      status: "done",
      pendingQueueBand: null,
      leaseUntilMs: 0,
      completedAtMs: nowMs,
      updatedAtMs: nowMs,
      lastErrorCode: null,
    },
    { merge: true },
  );
}

async function retryJob(job: ClaimedJob, error: unknown): Promise<void> {
  const nowMs = Date.now();
  const attempts = Number(job.value.attempts ?? 1);
  const terminal = attempts >= MAX_ATTEMPTS;
  const errorCode =
    error instanceof Error ? error.message.slice(0, 80) : "unknown";
  await job.ref.set(
    {
      status: terminal ? "done" : "retry",
      pendingQueueBand: null,
      leaseUntilMs: 0,
      availableAtMs:
        nowMs + RETRY_BASE_MS * Math.min(6, Math.pow(2, attempts - 1)),
      completedAtMs: terminal ? nowMs : null,
      updatedAtMs: nowMs,
      lastErrorCode: errorCode,
    },
    { merge: true },
  );
}

async function refreshProduct(
  product: CjCatalogProduct,
  sourceQuery: string,
): Promise<void> {
  const productRef = catalogProductRef(product.productId);
  const existingSnapshot = await productRef.get();
  const existing = existingSnapshot.data() ?? {};
  const previousSourceQueries = Array.isArray(existing.sourceQueries)
    ? existing.sourceQueries.map(String)
    : [];
  try {
    const quote = await findCjProductZaDelivery(
      product.productId,
      2,
      String(existing.deliverableVariantId ?? ""),
    );
    const nowMs = Date.now();
    await productRef.set(
      buildCatalogCacheDocument(
        product,
        quote,
        nowMs,
        sourceQuery,
        previousSourceQueries,
      ),
    );
  } catch (error) {
    if (!availabilityFailure(error)) throw error;
    const nowMs = Date.now();
    const availabilityReason = error instanceof Error ? error.message : "";
    await productRef.set(
      {
        ...product,
        supplierId: "cj_dropshipping",
        destinationCountryCode: "ZA",
        active: false,
        activeSearchTokens: [],
        availabilityReason,
        sourceQuery,
        checkedAtMs: nowMs,
        nextRefreshAtMs: nowMs + CATALOG_NEGATIVE_REFRESH_MS,
        schemaVersion: 2,
      },
      { merge: true },
    );
  }
}

async function enqueueStaleProductRefreshes(nowMs: number): Promise<void> {
  const snapshot = await db
    .collection("supplierCatalogProducts")
    .where("nextRefreshAtMs", "<=", nowMs)
    .limit(8)
    .get();
  await Promise.all(
    snapshot.docs.map(async (doc) => {
      const product = asCatalogProduct(doc.data());
      if (!product) return;
      await enqueueProductRefresh({
        product: product as unknown as Record<string, unknown>,
        query: String(doc.data().sourceQuery ?? "refresh"),
        priority: 30,
      });
    }),
  );
}

async function processDiscovery(job: ClaimedJob): Promise<void> {
  const supplierQuery = job.value.query === "popular" ? "" : job.value.query;
  const supplierPage = Math.max(1, Number(job.value.supplierPage ?? 1));
  const result = await searchCjProducts({
    query: supplierQuery,
    page: supplierPage,
    size: 24,
  });
  await job.ref.set(
    { discoveredCount: result.products.length, updatedAtMs: Date.now() },
    { merge: true },
  );
  await advanceCatalogDiscoveryPage(
    job.value.query,
    supplierPage,
    result.totalPages,
  );
  if (!result.products.length) return;
  await Promise.all(
    result.products.map((product) =>
      enqueueProductRefresh({
        product: product as unknown as Record<string, unknown>,
        query: job.value.query,
        // A seller search itself stays in the demand band, while its bounded
        // per-product verification work joins the refresh band. This prevents
        // one 24-product result page from delaying every later seller search.
        priority: catalogRefreshPriority(job.value.priority),
      }),
    ),
  );
}

async function processJob(job: ClaimedJob): Promise<void> {
  if (job.value.kind === "discover_query") {
    await processDiscovery(job);
    return;
  }
  if (job.value.kind === "refresh_product") {
    const product = asCatalogProduct(job.value.product);
    if (!product) throw new Error("CJ_CATALOG_JOB_INVALID");
    await refreshProduct(product, job.value.query);
    return;
  }
  throw new Error("CJ_CATALOG_JOB_INVALID");
}

async function enqueueRotatingDiscovery(nowMs: number): Promise<boolean> {
  const stateRef = db.doc(WORKER_STATE_PATH);
  const query = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(stateRef);
    const nextDiscoveryAtMs = Number(snapshot.data()?.nextDiscoveryAtMs ?? 0);
    if (nextDiscoveryAtMs > nowMs) return "";
    const current = Number(snapshot.data()?.discoveryIndex ?? 0);
    const safe = Number.isSafeInteger(current) && current >= 0 ? current : 0;
    tx.set(
      stateRef,
      {
        discoveryIndex: (safe + 1) % DEFAULT_DISCOVERY_QUERIES.length,
        nextDiscoveryAtMs: nowMs + ROTATING_DISCOVERY_INTERVAL_MS,
        updatedAtMs: nowMs,
        schemaVersion: 1,
      },
      { merge: true },
    );
    return DEFAULT_DISCOVERY_QUERIES[safe % DEFAULT_DISCOVERY_QUERIES.length];
  });
  if (!query) return false;
  return enqueueCatalogDemand(query);
}

export async function runCjCatalogWorkerOnce() {
  const startedAtMs = Date.now();
  let processed = 0;
  let failed = 0;
  await enqueueStaleProductRefreshes(startedAtMs);
  const rotatingDiscoveryQueued = await enqueueRotatingDiscovery(startedAtMs);
  while (
    processed + failed < MAX_JOBS_PER_RUN &&
    Date.now() - startedAtMs < MAX_RUN_MS
  ) {
    // Give the two-hour rotating browse seed one fair slot ahead of routine
    // refreshes. Seller-demand discovery remains first.
    const job = await claimNextJob(catalogQueueOrder(rotatingDiscoveryQueued));
    if (!job) break;
    if (!(await reserveCatalogBudget(job))) {
      await deferForCatalogBudget(job);
      return { processed, failed, budgetLimited: true };
    }
    try {
      await processJob(job);
      await completeJob(job);
      processed += 1;
    } catch (error) {
      console.warn("CJ catalogue worker job failed", {
        jobId: job.id,
        kind: job.value.kind,
        code: error instanceof Error ? error.message : "unknown",
      });
      await retryJob(job, error);
      failed += 1;
      break;
    }
  }
  return { processed, failed };
}

/** Automatically discovers and refreshes the Spaza One supplier catalogue. */
export const syncCjSupplierCatalog = functions
  .runWith({
    secrets: ["CJ_API_KEY"],
    timeoutSeconds: 240,
    memory: "512MB",
    maxInstances: 1,
  })
  // One bounded job every five minutes stays below the free account's average
  // point replenishment while preserving capacity for real buyer-order quotes.
  .pubsub.schedule("every 5 minutes")
  .timeZone("Africa/Johannesburg")
  .onRun(runCjCatalogWorkerOnce);
