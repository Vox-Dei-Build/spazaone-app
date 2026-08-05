import { db, functions } from "../config/main";
import { assertCallableStoreAccess } from "../stores/storeAccess";
import {
  catalogProductWithZaDelivery,
  CjCatalogProduct,
  CjZaEligibleProduct,
  findCjProductZaDelivery,
  findCjProductZaDeliveryFromDetails,
  getCjProductDetails,
  quoteCjVariant,
  searchCjProducts,
} from "./cjClient";
import { commercePaymentsEnabled } from "./readiness";

const cjRuntime = functions.runWith({
  secrets: ["CJ_API_KEY"],
  timeoutSeconds: 120,
  memory: "512MB",
});
const ELIGIBILITY_COLLECTION = "supplierCatalogEligibility";
const POSITIVE_CACHE_MS = 30 * 60 * 1000;
const NEGATIVE_CACHE_MS = 15 * 60 * 1000;
const MAX_LIVE_CHECKS = 4;
const LIVE_CHECK_CONCURRENCY = 1;

type EligibilityCache = {
  eligible: boolean;
  checkedAtMs: number;
  deliverableVariantId: string;
  estimatedDeliveryCostMinor: number;
  estimatedLandedCostMinor: number;
  logisticAging: string;
  deliveryVerifiedAt: string;
};

function cacheRef(productId: string) {
  return db.doc(`${ELIGIBILITY_COLLECTION}/cj_za_${productId}`);
}

function cacheValue(value: FirebaseFirestore.DocumentData): EligibilityCache {
  return {
    eligible: value.eligible === true,
    checkedAtMs: Number(value.checkedAtMs ?? 0),
    deliverableVariantId: String(value.deliverableVariantId ?? ""),
    estimatedDeliveryCostMinor: Number(value.estimatedDeliveryCostMinor ?? 0),
    estimatedLandedCostMinor: Number(value.estimatedLandedCostMinor ?? 0),
    logisticAging: String(value.logisticAging ?? ""),
    deliveryVerifiedAt: String(value.deliveryVerifiedAt ?? ""),
  };
}

function cacheIsFresh(cache: EligibilityCache, nowMs: number): boolean {
  const ttl = cache.eligible ? POSITIVE_CACHE_MS : NEGATIVE_CACHE_MS;
  return cache.checkedAtMs > 0 && nowMs - cache.checkedAtMs < ttl;
}

function productFromCache(
  product: CjCatalogProduct,
  cache: EligibilityCache,
): CjZaEligibleProduct | null {
  if (
    !cache.eligible ||
    !cache.deliverableVariantId ||
    cache.estimatedLandedCostMinor <= 0
  ) {
    return null;
  }
  return {
    ...product,
    deliverableVariantId: cache.deliverableVariantId,
    estimatedDeliveryCostMinor: cache.estimatedDeliveryCostMinor,
    estimatedLandedCostMinor: cache.estimatedLandedCostMinor,
    logisticAging: cache.logisticAging,
    deliveryVerifiedAt: cache.deliveryVerifiedAt,
  };
}

async function mapWithConcurrency<T, R>(
  values: T[],
  concurrency: number,
  task: (value: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(values.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(concurrency, values.length) }, async () => {
      while (next < values.length) {
        const index = next++;
        results[index] = await task(values[index]);
      }
    }),
  );
  return results;
}

function isProductEligibilityFailure(error: unknown): boolean {
  const code = error instanceof Error ? error.message : "";
  return [
    "CJ_NO_SHIPPING_TO_ZA",
    "CJ_OUT_OF_STOCK",
    "CJ_PRODUCT_UNAVAILABLE",
    "CJ_PRODUCT_INVALID",
    "CJ_VARIANTS_UNAVAILABLE",
  ].includes(code);
}

async function searchZaEligibleProducts(input: {
  query: string;
  page: number;
}) {
  const search = await searchCjProducts({ ...input, size: 24 });
  if (!search.products.length) {
    return { ...search, products: [], checkedCount: 0 };
  }

  const nowMs = Date.now();
  const snapshots = await db.getAll(
    ...search.products.map((product) => cacheRef(product.productId)),
  );
  const caches = new Map<string, EligibilityCache>();
  snapshots.forEach((snapshot, index) => {
    if (snapshot.exists) {
      caches.set(
        search.products[index].productId,
        cacheValue(snapshot.data() ?? {}),
      );
    }
  });

  const eligible = new Map<string, CjZaEligibleProduct>();
  for (const product of search.products) {
    const cache = caches.get(product.productId);
    if (!cache || !cacheIsFresh(cache, nowMs)) continue;
    const cachedProduct = productFromCache(product, cache);
    if (cachedProduct) eligible.set(product.productId, cachedProduct);
  }

  const candidates = search.products
    .filter((product) => {
      const cache = caches.get(product.productId);
      return !cache || !cacheIsFresh(cache, nowMs);
    })
    .slice(0, MAX_LIVE_CHECKS);
  let firstTransientFailure: unknown;

  const checked = await mapWithConcurrency(
    candidates,
    LIVE_CHECK_CONCURRENCY,
    async (product): Promise<CjZaEligibleProduct | null> => {
      try {
        const quote = await findCjProductZaDelivery(product.productId);
        const verified = catalogProductWithZaDelivery(product, quote);
        await cacheRef(product.productId).set({
          supplierId: "cj_dropshipping",
          supplierProductId: product.productId,
          destinationCountryCode: "ZA",
          eligible: true,
          checkedAtMs: nowMs,
          deliverableVariantId: verified.deliverableVariantId,
          estimatedDeliveryCostMinor: verified.estimatedDeliveryCostMinor,
          estimatedLandedCostMinor: verified.estimatedLandedCostMinor,
          logisticAging: verified.logisticAging,
          deliveryVerifiedAt: verified.deliveryVerifiedAt,
          schemaVersion: 1,
        });
        return verified;
      } catch (error) {
        if (isProductEligibilityFailure(error)) {
          await cacheRef(product.productId).set({
            supplierId: "cj_dropshipping",
            supplierProductId: product.productId,
            destinationCountryCode: "ZA",
            eligible: false,
            checkedAtMs: nowMs,
            schemaVersion: 1,
          });
          return null;
        }
        console.warn("CJ ZA eligibility check skipped", {
          productId: product.productId,
          code: error instanceof Error ? error.message : "unknown",
        });
        firstTransientFailure ??= error;
        return null;
      }
    },
  );
  checked.forEach((product) => {
    if (product) eligible.set(product.productId, product);
  });
  if (!eligible.size && firstTransientFailure) {
    throw firstTransientFailure;
  }

  return {
    ...search,
    products: search.products
      .map((product) => eligible.get(product.productId))
      .filter((product): product is CjZaEligibleProduct => Boolean(product)),
    checkedCount: candidates.length,
  };
}

function cleanId(value: unknown, field: string): string {
  const id = String(value ?? "").trim();
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(id)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `A valid ${field} is required.`,
    );
  }
  return id;
}

export function publicCjError(error: unknown): functions.https.HttpsError {
  const code = error instanceof Error ? error.message : "";
  if (code === "CJ_NOT_CONFIGURED" || code === "CJ_AUTH_FAILED") {
    return new functions.https.HttpsError(
      "failed-precondition",
      "The Spaza One supplier catalogue is temporarily unavailable.",
    );
  }
  if (code === "CJ_OUT_OF_STOCK") {
    return new functions.https.HttpsError(
      "failed-precondition",
      "That variant is currently out of stock.",
    );
  }
  if (code === "CJ_NO_SHIPPING_TO_ZA") {
    return new functions.https.HttpsError(
      "failed-precondition",
      "That variant cannot currently be delivered to South Africa.",
    );
  }
  if (code.includes("VARIANT") || code.includes("PRODUCT")) {
    return new functions.https.HttpsError(
      "not-found",
      "That supplier product is no longer available.",
    );
  }
  if (code.startsWith("CJ_FX")) {
    return new functions.https.HttpsError(
      "unavailable",
      "Live supplier pricing is temporarily unavailable. Please try again.",
    );
  }
  if (code === "CJ_RATE_LIMITED") {
    return new functions.https.HttpsError(
      "resource-exhausted",
      "Supplier pricing is busy right now. Please wait a moment and try again.",
    );
  }
  return new functions.https.HttpsError(
    "unavailable",
    "Spaza One could not refresh supplier availability right now. Please try again in a moment.",
  );
}

async function authorize(
  data: unknown,
  context: functions.https.CallableContext,
): Promise<Record<string, unknown>> {
  const input =
    data && typeof data === "object" ? (data as Record<string, unknown>) : {};
  await assertCallableStoreAccess(context, input.storeId);
  return input;
}

/** Seller-authenticated CJ catalog search; credentials remain server-side. */
export const searchCjSupplierCatalog = cjRuntime.https.onCall(
  async (data, context) => {
    const input = await authorize(data, context);
    const query = String(input.query ?? "")
      .trim()
      .slice(0, 100);
    const page = Number(input.page ?? 1);
    if (!Number.isSafeInteger(page) || page < 1 || page > 1000) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Choose a valid catalog page.",
      );
    }
    try {
      const result = await searchZaEligibleProducts({ query, page });
      return {
        ...result,
        digitalPaymentsEnabled: commercePaymentsEnabled(),
      };
    } catch (error) {
      console.error("searchCjSupplierCatalog failed", error);
      throw publicCjError(error);
    }
  },
);

/** Returns current CJ variants and server-converted product estimates. */
export const getCjSupplierProduct = cjRuntime.https.onCall(
  async (data, context) => {
    const input = await authorize(data, context);
    const productId = cleanId(input.productId, "productId");
    const preferredVariantId = String(input.preferredVariantId ?? "").trim();
    if (
      preferredVariantId &&
      !/^[A-Za-z0-9_-]{1,200}$/.test(preferredVariantId)
    ) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Choose a valid product variant.",
      );
    }
    try {
      const product = await getCjProductDetails(productId);
      const quote = await findCjProductZaDeliveryFromDetails(
        product,
        5,
        preferredVariantId,
      );
      return {
        ...product,
        recommendedVariantId: quote.variant.variantId,
        recommendedQuote: quote,
      };
    } catch (error) {
      console.error("getCjSupplierProduct failed", error);
      throw publicCjError(error);
    }
  },
);

/** Calculates a current landed-cost quote to South Africa. */
export const quoteCjSupplierVariant = cjRuntime.https.onCall(
  async (data, context) => {
    const input = await authorize(data, context);
    const productId = cleanId(input.productId, "productId");
    const variantId = cleanId(input.variantId, "variantId");
    const postalCode = String(input.postalCode ?? "").trim();
    if (postalCode && !/^\d{4}$/.test(postalCode)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Enter a valid four-digit South African postal code.",
      );
    }
    try {
      return await quoteCjVariant({ productId, variantId, postalCode });
    } catch (error) {
      console.error("quoteCjSupplierVariant failed", error);
      throw publicCjError(error);
    }
  },
);
