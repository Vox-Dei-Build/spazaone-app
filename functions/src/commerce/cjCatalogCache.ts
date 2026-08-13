import { createHash } from "node:crypto";
import type {
  CjCatalogProduct,
  CjLandedQuote,
  CjProductDetails,
  CjVariant,
  CjZaEligibleProduct,
} from "./cjClient";

// Match the supplier's original browse page so sellers do not have to page
// after only a handful of rows. This is still a Firestore-only read; it does
// not increase CJ traffic.
export const CATALOG_PAGE_SIZE = 24;
export const CATALOG_REFRESH_MS = 72 * 60 * 60 * 1000;
export const CATALOG_NEGATIVE_REFRESH_MS = 24 * 60 * 60 * 1000;
// Positive quotes normally refresh every 72 hours. Allow a bounded grace
// period for delayed workers, but never expose or sell from an indefinitely
// old South Africa stock/freight result.
export const CATALOG_SNAPSHOT_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;

export type CjQuoteSnapshot = Omit<CjLandedQuote, "product">;

export type CjCatalogCacheDocument = CjZaEligibleProduct & {
  supplierId: "cj_dropshipping";
  destinationCountryCode: "ZA";
  active: boolean;
  searchTokens: string[];
  activeSearchTokens: string[];
  details: CjProductDetails;
  recommendedQuote: CjQuoteSnapshot;
  sourceQuery: string;
  sourceQueries: string[];
  checkedAtMs: number;
  nextRefreshAtMs: number;
  schemaVersion: number;
};

function quoteIsInternallyConsistent(
  productId: string,
  quote: Partial<CjQuoteSnapshot> | null | undefined,
): boolean {
  return (
    Boolean(quote) &&
    Boolean(productId) &&
    quote?.currency === "ZAR" &&
    quote.variant?.productId === productId &&
    Boolean(quote.variant?.variantId) &&
    Number.isSafeInteger(quote.stock) &&
    Number(quote.stock) > 0 &&
    Number.isSafeInteger(quote.productCostMinor) &&
    Number(quote.productCostMinor) > 0 &&
    Number.isSafeInteger(quote.shippingCostMinor) &&
    Number(quote.shippingCostMinor) >= 0 &&
    Number.isSafeInteger(quote.landedCostMinor) &&
    Number(quote.landedCostMinor) ===
      Number(quote.productCostMinor) + Number(quote.shippingCostMinor)
  );
}

export function catalogSnapshotIsFresh(
  deliveryVerifiedAt: unknown,
  nowMs = Date.now(),
): boolean {
  const verifiedAtMs = Date.parse(String(deliveryVerifiedAt ?? ""));
  return (
    Number.isFinite(verifiedAtMs) &&
    verifiedAtMs <= nowMs &&
    nowMs - verifiedAtMs <= CATALOG_SNAPSHOT_MAX_AGE_MS
  );
}

function normalizedWords(value: string): string[] {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .split(/\s+/)
    .filter((word) => word.length >= 2);
}

export function catalogQueryWords(value: string): string[] {
  return [...new Set(normalizedWords(value))].slice(0, 8);
}

export function catalogSearchTokens(...values: string[]): string[] {
  const tokens = new Set<string>();
  for (const word of normalizedWords(values.join(" "))) {
    const capped = word.slice(0, 32);
    for (let length = 2; length <= capped.length; length++) {
      tokens.add(capped.slice(0, length));
      if (tokens.size >= 240) return [...tokens];
    }
  }
  return [...tokens];
}

function quoteSnapshot(quote: CjLandedQuote): CjQuoteSnapshot {
  return {
    variant: quote.variant,
    originCountryCode: quote.originCountryCode,
    stock: quote.stock,
    quantity: quote.quantity,
    logisticName: quote.logisticName,
    logisticAging: quote.logisticAging,
    productCostUsdMinor: quote.productCostUsdMinor,
    shippingCostUsdMinor: quote.shippingCostUsdMinor,
    productCostMinor: quote.productCostMinor,
    shippingCostMinor: quote.shippingCostMinor,
    landedCostMinor: quote.landedCostMinor,
    currency: quote.currency,
    fx: quote.fx,
    verifiedAt: quote.verifiedAt,
  };
}

function prioritizedVariants(
  variants: CjVariant[],
  recommendedVariantId: string,
): CjVariant[] {
  const recommended = variants.find(
    (variant) => variant.variantId === recommendedVariantId,
  );
  const ordered = recommended
    ? [recommended, ...variants.filter((variant) => variant !== recommended)]
    : variants;
  return ordered.slice(0, 60);
}

export function buildCatalogCacheDocument(
  product: CjCatalogProduct,
  quote: CjLandedQuote,
  nowMs: number,
  sourceQuery = "",
  previousSourceQueries: string[] = [],
): CjCatalogCacheDocument {
  const snapshot = quoteSnapshot(quote);
  if (
    quote.product.productId !== product.productId ||
    !quote.product.variants.some(
      (variant) => variant.variantId === quote.variant.variantId,
    ) ||
    !quoteIsInternallyConsistent(product.productId, snapshot)
  ) {
    throw new Error("CJ_QUOTE_INVALID");
  }
  const canonicalProduct: CjCatalogProduct = {
    productId: quote.product.productId,
    productSku: quote.product.productSku || product.productSku,
    title: quote.product.title || product.title,
    image: quote.variant.image || quote.product.images[0] || product.image,
    category: quote.product.category || product.category,
    productCostUsdMinor: quote.productCostUsdMinor,
    estimatedProductCostMinor: quote.productCostMinor,
  };
  const details: CjProductDetails = {
    ...quote.product,
    variants: prioritizedVariants(
      quote.product.variants,
      quote.variant.variantId,
    ),
  };
  const sourceQueries = [...previousSourceQueries, sourceQuery]
    .map((value) => catalogQueryWords(value).join(" "))
    .filter(Boolean)
    .filter((value, index, all) => all.indexOf(value) === index)
    .slice(-8);
  const searchTokens = catalogSearchTokens(
    canonicalProduct.title,
    canonicalProduct.category,
    canonicalProduct.productSku,
    quote.variant.option,
    quote.variant.name,
    // Demand queries are useful synonyms, but core product fields must be
    // tokenised first so a long query history cannot crowd the title/category
    // out of Firestore's bounded token array.
    sourceQueries.join(" "),
  );
  return {
    ...canonicalProduct,
    supplierId: "cj_dropshipping",
    destinationCountryCode: "ZA",
    active: true,
    deliverableVariantId: quote.variant.variantId,
    estimatedProductCostMinor: quote.productCostMinor,
    estimatedDeliveryCostMinor: quote.shippingCostMinor,
    estimatedLandedCostMinor: quote.landedCostMinor,
    logisticAging: quote.logisticAging,
    deliveryVerifiedAt: quote.verifiedAt,
    searchTokens,
    activeSearchTokens: searchTokens,
    details,
    recommendedQuote: snapshot,
    sourceQuery,
    sourceQueries,
    checkedAtMs: nowMs,
    nextRefreshAtMs: nowMs + CATALOG_REFRESH_MS,
    schemaVersion: 2,
  };
}

export function isUsableCatalogDocument(
  value: Partial<CjCatalogCacheDocument>,
  nowMs = Date.now(),
): value is CjCatalogCacheDocument {
  return (
    value.active === true &&
    Boolean(value.productId) &&
    Boolean(value.deliverableVariantId) &&
    Number(value.estimatedLandedCostMinor) > 0 &&
    value.deliveryVerifiedAt === value.recommendedQuote?.verifiedAt &&
    catalogSnapshotIsFresh(value.deliveryVerifiedAt, nowMs) &&
    value.deliverableVariantId === value.recommendedQuote?.variant.variantId &&
    quoteIsInternallyConsistent(
      String(value.productId ?? ""),
      value.recommendedQuote,
    ) &&
    value.details?.productId === value.productId
  );
}

export function catalogPreview(
  value: CjCatalogCacheDocument,
): CjZaEligibleProduct & { catalogQuoteVersion: string } {
  return {
    productId: value.productId,
    productSku: value.productSku,
    title: value.title,
    image: value.image,
    category: value.category,
    productCostUsdMinor: value.productCostUsdMinor,
    estimatedProductCostMinor: value.estimatedProductCostMinor,
    deliverableVariantId: value.deliverableVariantId,
    estimatedDeliveryCostMinor: value.estimatedDeliveryCostMinor,
    estimatedLandedCostMinor: value.estimatedLandedCostMinor,
    logisticAging: value.logisticAging,
    deliveryVerifiedAt: value.deliveryVerifiedAt,
    catalogQuoteVersion: catalogQuoteVersion(value),
  };
}

export function catalogQuoteVersion(value: CjCatalogCacheDocument): string {
  const quote = value.recommendedQuote;
  return createHash("sha256")
    .update(
      [
        value.productId,
        value.deliverableVariantId,
        quote.productCostMinor,
        quote.shippingCostMinor,
        quote.landedCostMinor,
        quote.stock,
        quote.logisticAging,
        quote.verifiedAt,
      ].join("|"),
    )
    .digest("hex")
    .slice(0, 32);
}

/** Sanitizes a device bookmark snapshot; it is never accepted for pricing. */
export function savedCatalogSnapshot(
  value: unknown,
  productId: string,
): Record<string, unknown> {
  const input =
    value && typeof value === "object"
      ? (value as Record<string, unknown>)
      : {};
  const text = (field: string, max: number): string =>
    String(input[field] ?? "")
      .trim()
      .slice(0, max);
  const minor = (field: string): number => {
    const amount = Number(input[field] ?? 0);
    return Number.isSafeInteger(amount) && amount >= 0 ? amount : 0;
  };
  const productCostMinor = minor("estimatedProductCostMinor");
  const deliveryCostMinor = minor("estimatedDeliveryCostMinor");
  const landedCostMinor = minor("estimatedLandedCostMinor");
  const costsAreConsistent =
    productCostMinor > 0 &&
    landedCostMinor === productCostMinor + deliveryCostMinor;
  const rawImage = text("image", 2048);
  const variantId = text("deliverableVariantId", 200);
  const deliveryVerifiedAt = text("deliveryVerifiedAt", 80);
  return {
    productId,
    productSku: text("productSku", 100),
    title: text("title", 160) || "Saved product",
    image: /^https?:\/\//i.test(rawImage) ? rawImage : "",
    category: text("category", 100),
    productCostUsdMinor: minor("productCostUsdMinor"),
    estimatedProductCostMinor: costsAreConsistent ? productCostMinor : 0,
    deliverableVariantId: /^[A-Za-z0-9_-]{1,200}$/.test(variantId)
      ? variantId
      : "",
    estimatedDeliveryCostMinor: costsAreConsistent ? deliveryCostMinor : 0,
    estimatedLandedCostMinor: costsAreConsistent ? landedCostMinor : 0,
    logisticAging: text("logisticAging", 60),
    deliveryVerifiedAt: Number.isFinite(Date.parse(deliveryVerifiedAt))
      ? deliveryVerifiedAt
      : "",
    catalogQuoteVersion: text("catalogQuoteVersion", 80),
  };
}

export type CatalogListingState =
  | { status: "ready"; document: CjCatalogCacheDocument }
  | { status: "quote_changed"; product: ReturnType<typeof catalogPreview> }
  | { status: "refreshing" }
  | { status: "unavailable" };

/**
 * Uses the same catalogue usability predicate for browse and listing creation.
 * A selected quote version turns an otherwise valid but changed row into a
 * reviewable update instead of the generic "product unavailable" dead end.
 */
export function catalogListingState(
  value: Partial<CjCatalogCacheDocument> | null | undefined,
  selectedVariantId: string,
  selectedQuoteVersion: string,
  nowMs = Date.now(),
): CatalogListingState {
  if (!value || value.active === false) return { status: "unavailable" };
  if (!isUsableCatalogDocument(value, nowMs)) {
    return { status: "refreshing" };
  }
  if (
    value.deliverableVariantId !== selectedVariantId ||
    (selectedQuoteVersion &&
      value.deliveryVerifiedAt !== selectedQuoteVersion &&
      catalogQuoteVersion(value) !== selectedQuoteVersion)
  ) {
    return {
      status: "quote_changed",
      product: catalogPreview(value),
    };
  }
  return { status: "ready", document: value };
}

export function catalogDetailsPayload(value: CjCatalogCacheDocument) {
  const verifiedVariant =
    value.details.variants.find(
      (variant) => variant.variantId === value.deliverableVariantId,
    ) ?? value.recommendedQuote.variant;
  return {
    ...value.details,
    // Older released apps rendered every returned variant and live-quoted the
    // selection. Expose only the cached ZA-verified option so they also stay on
    // the zero-CJ-call browse path during a rolling release.
    variants: [verifiedVariant],
    recommendedVariantId: value.deliverableVariantId,
    recommendedQuote: value.recommendedQuote,
    catalogueSnapshot: true,
  };
}
