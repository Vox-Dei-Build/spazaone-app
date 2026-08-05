import { createHash } from "node:crypto";
import { FieldPath, FieldValue } from "firebase-admin/firestore";
import { db } from "../config/main";
import {
  CATALOG_PAGE_SIZE,
  catalogPreview,
  catalogDetailsPayload,
  catalogQueryWords,
  catalogSearchTokens,
  CjCatalogCacheDocument,
  isUsableCatalogDocument,
} from "./cjCatalogCache";

export const CATALOG_COLLECTION = "supplierCatalogProducts";
export const CATALOG_JOBS_COLLECTION = "supplierCatalogJobs";
const CATALOG_DEMAND_COLLECTION = "supplierCatalogDemand";
const DEMAND_REFRESH_MS = 6 * 60 * 60 * 1000;
const SELLER_DISCOVERY_LIMIT_PER_DAY = 6;
const REFRESH_QUEUE_LEASE_MS = 6 * 60 * 60 * 1000;
// Discovery advances one page per bounded background job. A wider ceiling
// grows useful searches over time without adding any supplier calls to the
// seller's browse request.
export const MAX_SUPPLIER_PAGES_PER_QUERY = 50;
export const CATALOG_DISCOVERY_TARGET = CATALOG_PAGE_SIZE * 4;

export type CatalogJobKind = "discover_query" | "refresh_product";
export type CatalogQueueBand = "demand" | "refresh" | "background";

export type CatalogJob = {
  kind: CatalogJobKind;
  status: "pending" | "retry" | "working" | "done";
  queueBand: CatalogQueueBand;
  pendingQueueBand: CatalogQueueBand | null;
  priority: number;
  query: string;
  product?: Record<string, unknown>;
  attempts: number;
  availableAtMs: number;
  leaseUntilMs: number;
  createdAtMs: number;
  updatedAtMs: number;
  completedAtMs?: number;
  discoveredCount?: number;
  supplierPage?: number;
  lastErrorCode?: string;
};

function normalizedQuery(value: string): string {
  return catalogQueryWords(value).join(" ").slice(0, 100);
}

function hash(value: string): string {
  return createHash("sha256").update(value).digest("hex").slice(0, 40);
}

function zaCalendarDay(nowMs: number): string {
  return new Date(nowMs + 2 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

export function catalogJobId(kind: CatalogJobKind, key: string): string {
  return `${kind}_${hash(key)}`;
}

export function catalogProductRef(productId: string) {
  return db.doc(`${CATALOG_COLLECTION}/cj_${productId}`);
}

export async function searchCachedCatalog(
  query: string,
  page: number,
  cursor = "",
) {
  const words = catalogQueryWords(query);
  const primary = [...words].sort((a, b) => b.length - a.length)[0];
  const collection = db.collection(CATALOG_COLLECTION);
  const catalogQuery = primary
    ? collection.where("activeSearchTokens", "array-contains", primary)
    : collection.where("active", "==", true);
  const countSnapshot = await catalogQuery.count().get();
  const totalProducts = Number(countSnapshot.data().count ?? 0);
  const totalPages = Math.max(1, Math.ceil(totalProducts / CATALOG_PAGE_SIZE));
  const safePage = Math.min(Math.max(1, page), totalPages);
  let pageQuery = catalogQuery.orderBy(FieldPath.documentId());
  if (cursor) {
    pageQuery = pageQuery.startAfter(cursor);
  } else if (safePage > 1) {
    // Released apps know only page numbers. Keep their path compatible while
    // new apps use the cursor response and avoid billed deep offsets.
    pageQuery = pageQuery.offset((safePage - 1) * CATALOG_PAGE_SIZE);
  }
  const snapshot = await pageQuery.limit(CATALOG_PAGE_SIZE + 1).get();
  const pageDocuments = snapshot.docs.slice(0, CATALOG_PAGE_SIZE);
  const products = pageDocuments
    .map((doc) => doc.data() as Partial<CjCatalogCacheDocument>)
    .filter(isUsableCatalogDocument)
    .map(catalogPreview);
  const hasMore = snapshot.docs.length > CATALOG_PAGE_SIZE;
  return {
    products,
    page: safePage,
    totalPages,
    totalProducts,
    hasMore,
    nextCursor: hasMore
      ? String(pageDocuments[pageDocuments.length - 1]?.id ?? "")
      : "",
  };
}

export async function getCachedCatalogProduct(productId: string) {
  const snapshot = await catalogProductRef(productId).get();
  const value = snapshot.data() as Partial<CjCatalogCacheDocument> | undefined;
  return value && isUsableCatalogDocument(value)
    ? catalogDetailsPayload(value)
    : null;
}

export async function getCachedCatalogDocument(productId: string) {
  const snapshot = await catalogProductRef(productId).get();
  const value = snapshot.data() as Partial<CjCatalogCacheDocument> | undefined;
  return value && isUsableCatalogDocument(value) ? value : null;
}

/**
 * Records aggregate product demand and idempotently asks the worker to discover
 * that query. No seller/customer identifiers are stored in these documents.
 */
export async function enqueueCatalogDemand(
  rawQuery: string,
  options: { requesterStoreId?: string } = {},
): Promise<boolean> {
  const query = normalizedQuery(rawQuery) || "popular";
  const demandId = hash(query);
  const demandRef = db.doc(`${CATALOG_DEMAND_COLLECTION}/${demandId}`);
  const jobRef = db.doc(
    `${CATALOG_JOBS_COLLECTION}/${catalogJobId("discover_query", query)}`,
  );
  const nowMs = Date.now();
  const requesterStoreId = String(options.requesterStoreId ?? "").trim();
  const quotaRef = requesterStoreId
    ? db.doc(`supplierIntegrationState/cjDemandQuota_${hash(requesterStoreId)}`)
    : null;
  return db.runTransaction(async (tx) => {
    const job = await tx.get(jobRef);
    const existing = job.data() as Partial<CatalogJob> | undefined;
    if (
      job.exists &&
      (existing?.status === "pending" || existing?.status === "working")
    ) {
      return true;
    }
    if (
      existing?.status === "done" &&
      Number(existing.discoveredCount ?? 0) > 0 &&
      nowMs - Number(existing.completedAtMs ?? 0) < 30 * 60 * 1000
    ) {
      return true;
    }
    const canRequeue =
      !job.exists ||
      (existing?.status === "done" &&
        nowMs - Number(existing.completedAtMs ?? 0) >= DEMAND_REFRESH_MS);
    if (!canRequeue) return false;

    const demand = await tx.get(demandRef);
    const storedSupplierPage = Number(demand.data()?.nextSupplierPage ?? 1);
    const supplierPage =
      Number.isSafeInteger(storedSupplierPage) && storedSupplierPage > 0
        ? Math.min(MAX_SUPPLIER_PAGES_PER_QUERY, storedSupplierPage)
        : 1;
    let quotaDay = "";
    let quotaCount = 0;
    if (quotaRef) {
      const quota = await tx.get(quotaRef);
      quotaDay = zaCalendarDay(nowMs);
      quotaCount =
        String(quota.data()?.day ?? "") === quotaDay
          ? Number(quota.data()?.count ?? 0)
          : 0;
      if (quotaCount >= SELLER_DISCOVERY_LIMIT_PER_DAY) return false;
    }

    tx.set(
      demandRef,
      {
        query,
        count: FieldValue.increment(1),
        lastRequestedAtMs: nowMs,
        schemaVersion: 1,
      },
      { merge: true },
    );
    if (quotaRef) {
      tx.set(
        quotaRef,
        {
          day: quotaDay,
          count: quotaCount + 1,
          updatedAtMs: nowMs,
          schemaVersion: 1,
        },
        { merge: true },
      );
    }
    tx.set(
      jobRef,
      {
        kind: "discover_query",
        status: "pending",
        queueBand: requesterStoreId ? "demand" : "background",
        pendingQueueBand: requesterStoreId ? "demand" : "background",
        priority: requesterStoreId ? 50 : 10,
        query,
        supplierPage,
        attempts: 0,
        discoveredCount: 0,
        availableAtMs: nowMs,
        leaseUntilMs: 0,
        createdAtMs: Number(existing?.createdAtMs ?? nowMs),
        updatedAtMs: nowMs,
        schemaVersion: 1,
      },
      { merge: true },
    );
    return true;
  });
}

export async function advanceCatalogDiscoveryPage(
  rawQuery: string,
  currentPage: number,
  totalPages: number,
): Promise<void> {
  const query = normalizedQuery(rawQuery) || "popular";
  const demandRef = db.doc(`${CATALOG_DEMAND_COLLECTION}/${hash(query)}`);
  const lastPage = Math.max(
    1,
    Math.min(MAX_SUPPLIER_PAGES_PER_QUERY, Math.floor(totalPages)),
  );
  const nextSupplierPage = currentPage >= lastPage ? 1 : currentPage + 1;
  await demandRef.set(
    {
      query,
      nextSupplierPage,
      lastSupplierPage: currentPage,
      lastSupplierTotalPages: totalPages,
      updatedAtMs: Date.now(),
      schemaVersion: 1,
    },
    { merge: true },
  );
}

export async function enqueueProductRefresh(input: {
  product: Record<string, unknown>;
  query: string;
  priority?: number;
}): Promise<void> {
  const productId = String(input.product.productId ?? "").trim();
  if (!productId) return;
  const jobRef = db.doc(
    `${CATALOG_JOBS_COLLECTION}/${catalogJobId("refresh_product", productId)}`,
  );
  const cacheRef = catalogProductRef(productId);
  const nowMs = Date.now();
  const queueBand: CatalogQueueBand =
    (input.priority ?? 30) >= 40
      ? "demand"
      : (input.priority ?? 30) >= 20
        ? "refresh"
        : "background";
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(jobRef);
    const cache = await tx.get(cacheRef);
    const existing = snapshot.data() as Partial<CatalogJob> | undefined;
    const cached = cache.data() as Partial<CjCatalogCacheDocument> | undefined;
    if (Number(cached?.nextRefreshAtMs ?? 0) > nowMs) {
      const sourceQuery = normalizedQuery(input.query);
      const existingSourceQueries = Array.isArray(cached?.sourceQueries)
        ? cached.sourceQueries
        : [];
      const sourceQueries = [...existingSourceQueries, sourceQuery]
        .filter(Boolean)
        .filter((value, index, all) => all.indexOf(value) === index)
        .slice(-8);
      if (sourceQuery && !existingSourceQueries.includes(sourceQuery)) {
        const searchTokens = catalogSearchTokens(
          String(cached?.title ?? ""),
          String(cached?.category ?? ""),
          String(cached?.productSku ?? ""),
          String(cached?.recommendedQuote?.variant.option ?? ""),
          String(cached?.recommendedQuote?.variant.name ?? ""),
          sourceQueries.join(" "),
        );
        tx.set(
          cacheRef,
          {
            sourceQueries,
            searchTokens,
            activeSearchTokens: searchTokens,
          },
          { merge: true },
        );
      }
      return;
    }
    if (
      snapshot.exists &&
      (existing?.status === "pending" ||
        existing?.status === "working" ||
        existing?.status === "retry")
    ) {
      return;
    }
    if (cache.exists) {
      // Move this stale document out of the sweeper's first page while its
      // idempotent job is queued. A successful or unavailable result replaces
      // this with the normal 72-hour refresh time.
      tx.set(
        cacheRef,
        {
          refreshQueuedAtMs: nowMs,
          nextRefreshAtMs: nowMs + REFRESH_QUEUE_LEASE_MS,
        },
        { merge: true },
      );
    }
    tx.set(
      jobRef,
      {
        kind: "refresh_product",
        status: "pending",
        queueBand,
        pendingQueueBand: queueBand,
        priority: input.priority ?? 30,
        query: normalizedQuery(input.query),
        product: input.product,
        attempts: 0,
        availableAtMs: nowMs,
        leaseUntilMs: 0,
        createdAtMs: Number(existing?.createdAtMs ?? nowMs),
        updatedAtMs: nowMs,
        schemaVersion: 1,
      },
      { merge: true },
    );
  });
}
