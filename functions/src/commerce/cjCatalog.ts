import { functions } from "../config/main";
import { assertCallableStoreAccess } from "../stores/storeAccess";
import { quoteCjVariant } from "./cjClient";
import {
  CATALOG_DISCOVERY_TARGET,
  enqueueCatalogDemand,
  getCachedCatalogDocument,
  getCachedCatalogProduct,
  searchCachedCatalog,
} from "./cjCatalogRepository";
import { commercePaymentsEnabled } from "./readiness";

const catalogRuntime = functions.runWith({
  timeoutSeconds: 30,
  memory: "256MB",
});
const quoteRuntime = functions.runWith({
  secrets: ["CJ_API_KEY"],
  timeoutSeconds: 120,
  memory: "512MB",
});

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
      "That option is currently out of stock.",
    );
  }
  if (code === "CJ_NO_SHIPPING_TO_ZA") {
    return new functions.https.HttpsError(
      "failed-precondition",
      "That option cannot currently be delivered to South Africa.",
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

/**
 * Seller-authenticated catalogue search. This path reads only Spaza One's
 * materialised Firestore catalogue and never waits on the supplier API.
 */
export const searchCjSupplierCatalog = catalogRuntime.https.onCall(
  async (data, context) => {
    const input = await authorize(data, context);
    const query = String(input.query ?? "")
      .trim()
      .slice(0, 100);
    const page = Number(input.page ?? 1);
    const cursor = String(input.cursor ?? "").trim();
    const maxPage = cursor ? 1000 : 13;
    if (!Number.isSafeInteger(page) || page < 1 || page > maxPage) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Choose a valid catalogue page.",
      );
    }
    if (cursor && !/^[A-Za-z0-9_-]{1,240}$/.test(cursor)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Choose a valid catalogue position.",
      );
    }
    try {
      const result = await searchCachedCatalog(query, page, cursor);
      let catalogueRefreshing = false;
      // Keep advancing the supplier search well beyond a single app page.
      // The queue is store-throttled and processed in the background, so this
      // broadens the cache without reintroducing browse-time CJ checks.
      if (result.totalProducts < CATALOG_DISCOVERY_TARGET) {
        catalogueRefreshing = await enqueueCatalogDemand(query, {
          requesterStoreId: String(input.storeId ?? ""),
        });
      }
      return {
        ...result,
        totalPages: cursor
          ? result.totalPages
          : Math.min(13, result.totalPages),
        catalogueRefreshing,
        digitalPaymentsEnabled: commercePaymentsEnabled(),
      };
    } catch (error) {
      console.error("searchCjSupplierCatalog failed", error);
      throw new functions.https.HttpsError(
        "unavailable",
        "Spaza One could not load supplier products right now. Please try again.",
      );
    }
  },
);

/** Returns cached product details and its verified South Africa option. */
export const getCjSupplierProduct = catalogRuntime.https.onCall(
  async (data, context) => {
    const input = await authorize(data, context);
    const productId = cleanId(input.productId, "productId");
    try {
      const product = await getCachedCatalogProduct(productId);
      if (!product) {
        throw new functions.https.HttpsError(
          "not-found",
          "That product is being refreshed. Choose another product for now.",
        );
      }
      return product;
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      console.error("getCjSupplierProduct failed", error);
      throw new functions.https.HttpsError(
        "unavailable",
        "Spaza One could not load that product right now. Please try again.",
      );
    }
  },
);

/**
 * Legacy compatibility endpoint. New catalogue UI does not call this while
 * browsing; final listing/order operations remain server-authoritative.
 */
export const quoteCjSupplierVariant = quoteRuntime.https.onCall(
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
      if (!postalCode) {
        const cached = await getCachedCatalogDocument(productId);
        if (
          cached?.deliverableVariantId === variantId &&
          cached.recommendedQuote.variant.variantId === variantId
        ) {
          return cached.recommendedQuote;
        }
      }
      return await quoteCjVariant({ productId, variantId, postalCode });
    } catch (error) {
      console.error("quoteCjSupplierVariant failed", error);
      throw publicCjError(error);
    }
  },
);
