import { createHash } from "crypto";

export const WHATSAPP_CATALOG_SCHEMA_VERSION = 1;

export type CatalogEligibilityReason =
  | "product_deleted"
  | "internal_product"
  | "not_whatsapp_listed"
  | "missing_name"
  | "invalid_price"
  | "missing_image"
  | "invalid_image_url"
  | "missing_product_link"
  | "policy_review_required";

export type CatalogPolicyReviewReason =
  | "alcohol"
  | "animals"
  | "gambling"
  | "regulated_drugs"
  | "tobacco"
  | "weapons";

export type MerchantCatalogProjection = {
  retailerId: string;
  title: string;
  description: string;
  imageUrl: string;
  link: string;
  priceMinor: number;
  currency: "ZAR";
  availability: "in stock" | "out of stock";
  condition: "new";
  brand: string;
  popularityScore: number;
  schemaVersion: number;
};

export type MerchantProductEligibility = {
  eligible: boolean;
  reasons: CatalogEligibilityReason[];
  policyReviewReasons: CatalogPolicyReviewReason[];
  name: string;
  priceMinor: number | null;
  imageUrl: string;
};

export type MerchantCatalogDecision = {
  action: "upsert" | "delete";
  eligible: boolean;
  reasons: CatalogEligibilityReason[];
  policyReviewReasons: CatalogPolicyReviewReason[];
  retailerId: string;
  revision: string;
  projection: MerchantCatalogProjection | null;
};

const POLICY_PATTERNS: ReadonlyArray<{
  reason: CatalogPolicyReviewReason;
  pattern: RegExp;
}> = [
  {
    reason: "tobacco",
    pattern: /\b(tobacco|cigarette|cigar|vape|vaping|nicotine)\b/i,
  },
  {
    reason: "weapons",
    pattern: /\b(firearm|gun|rifle|pistol|ammunition|ammo|weapon)\b/i,
  },
  {
    reason: "alcohol",
    pattern:
      /\b(beer|wine|whisky|whiskey|vodka|gin|rum|brandy|liqueur|alcohol)\b/i,
  },
  {
    reason: "regulated_drugs",
    pattern: /\b(cannabis|marijuana|weed|cbd|non-medical drug)\b/i,
  },
  {
    reason: "gambling",
    pattern: /\b(gambling|betting|lottery)\b/i,
  },
  {
    reason: "animals",
    pattern: /\blive\s+animal\b/i,
  },
];

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object"
    ? (value as Record<string, unknown>)
    : undefined;
}

function compactText(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  const withoutControls = Array.from(value, (character) => {
    const code = character.charCodeAt(0);
    return code <= 31 || code === 127 ? " " : character;
  }).join("");
  return withoutControls.replace(/\s+/g, " ").trim().slice(0, max).trim();
}

function firstText(
  source: Record<string, unknown>,
  keys: readonly string[],
  max: number,
): string {
  for (const key of keys) {
    const text = compactText(source[key], max);
    if (text) return text;
  }
  return "";
}

function safeHttpsUrl(value: unknown): string {
  const raw = compactText(value, 2048);
  if (!raw) return "";
  try {
    const url = new URL(raw);
    return url.protocol === "https:" ? url.toString() : "";
  } catch (_) {
    return "";
  }
}

function imageCandidates(product: Record<string, unknown>): string[] {
  const candidates: unknown[] = [
    product.imageUrl,
    product.image,
    product.photoUrl,
  ];
  if (Array.isArray(product.images)) candidates.push(...product.images);
  return candidates
    .map((value) => (typeof value === "string" ? value.trim() : ""))
    .filter(Boolean);
}

function productImage(product: Record<string, unknown>): {
  present: boolean;
  url: string;
} {
  const candidates = imageCandidates(product);
  return {
    present: candidates.length > 0,
    url: candidates.map(safeHttpsUrl).find(Boolean) ?? "",
  };
}

export function merchantProductSellPriceMinor(
  product: Record<string, unknown>,
): number | null {
  if (product.sellPriceMinor !== undefined) {
    const minor = Number(product.sellPriceMinor);
    return Number.isSafeInteger(minor) && minor > 0 && minor <= 100_000_000
      ? minor
      : null;
  }
  for (const value of [
    product.sellingPrice,
    product.price,
    product.productPrice,
  ]) {
    if (value === undefined || value === null || value === "") continue;
    const major = Number(value);
    const minor = Math.round(major * 100);
    return Number.isFinite(major) &&
      major > 0 &&
      Number.isSafeInteger(minor) &&
      minor <= 100_000_000
      ? minor
      : null;
  }
  return null;
}

function isWhatsAppListed(product: Record<string, unknown>): boolean {
  return (
    product.whatsappListed === true ||
    product.whatsappEnabled === true ||
    product.availableOnWhatsApp === true
  );
}

const NON_CUSTOMER_LISTING_STATES = new Set([
  "internal",
  "paused",
  "hidden",
  "private",
  "draft",
  "archived",
  "deleted",
]);

/**
 * A public WhatsApp flag must never override an explicit inventory decision to
 * keep a product internal. `dropshipListingState` is the current app field;
 * the remaining markers make the projection fail closed for older/imported
 * product documents without treating ordinary out-of-stock items as internal.
 */
function isExplicitlyInternal(product: Record<string, unknown>): boolean {
  if (
    product.isInternal === true ||
    product.internalOnly === true ||
    product.customerVisible === false ||
    product.archived === true ||
    product.isArchived === true
  ) {
    return true;
  }
  return [
    product.dropshipListingState,
    product.listingState,
    product.catalogVisibility,
    product.storefrontVisibility,
    product.visibility,
  ].some((value) =>
    NON_CUSTOMER_LISTING_STATES.has(
      typeof value === "string" ? value.trim().toLowerCase() : "",
    ),
  );
}

export function isMerchantProductCustomerVisible(
  product: Record<string, unknown>,
): boolean {
  return isWhatsAppListed(product) && !isExplicitlyInternal(product);
}

function policyReviewReasons(
  product: Record<string, unknown>,
  name: string,
): CatalogPolicyReviewReason[] {
  const text = [
    name,
    firstText(product, ["description"], 5000),
    firstText(product, ["group", "category"], 240),
  ].join(" ");
  return POLICY_PATTERNS.filter(({ pattern }) => pattern.test(text)).map(
    ({ reason }) => reason,
  );
}

/**
 * Deterministic local preflight only. Meta ingestion remains authoritative for
 * content-policy acceptance and image processing.
 */
export function evaluateMerchantProductEligibility(
  value: Record<string, unknown> | undefined,
): MerchantProductEligibility {
  if (!value) {
    return {
      eligible: false,
      reasons: ["product_deleted"],
      policyReviewReasons: [],
      name: "",
      priceMinor: null,
      imageUrl: "",
    };
  }
  const reasons: CatalogEligibilityReason[] = [];
  const name = firstText(value, ["name", "productName", "title"], 150);
  const priceMinor = merchantProductSellPriceMinor(value);
  const image = productImage(value);
  if (isExplicitlyInternal(value)) reasons.push("internal_product");
  else if (!isWhatsAppListed(value)) reasons.push("not_whatsapp_listed");
  if (!name) reasons.push("missing_name");
  if (priceMinor === null) reasons.push("invalid_price");
  if (!image.present) reasons.push("missing_image");
  else if (!image.url) reasons.push("invalid_image_url");
  const reviews = policyReviewReasons(value, name);
  if (reviews.length) reasons.push("policy_review_required");
  return {
    eligible: reasons.length === 0,
    reasons,
    policyReviewReasons: reviews,
    name,
    priceMinor,
    imageUrl: image.url,
  };
}

export function catalogRetailerId(
  merchantId: string,
  productId: string,
): string {
  const digest = createHash("sha256")
    .update(`${merchantId.trim()}\u0000${productId.trim()}`)
    .digest("hex")
    .slice(0, 32);
  return `spz_${digest}`;
}

function productLink(
  product: Record<string, unknown>,
  merchant: Record<string, unknown> | undefined,
): string {
  const direct = [
    product.checkoutUrl,
    product.productUrl,
    product.url,
    product.link,
  ]
    .map(safeHttpsUrl)
    .find(Boolean);
  if (direct) return direct;
  const ordering = asRecord(merchant?.whatsappOrdering);
  return safeHttpsUrl(ordering?.orderingUrl);
}

function availability(
  product: Record<string, unknown>,
): "in stock" | "out of stock" {
  for (const value of [product.quantity, product.stockQuantity]) {
    if (value === undefined || value === null || value === "") continue;
    const quantity = Number(value);
    if (Number.isFinite(quantity))
      return quantity > 0 ? "in stock" : "out of stock";
  }
  return "in stock";
}

function stableRevision(value: Record<string, unknown>): string {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

export function buildMerchantCatalogDecision(input: {
  merchantId: string;
  productId: string;
  product: Record<string, unknown> | undefined;
  merchant?: Record<string, unknown>;
}): MerchantCatalogDecision {
  const retailerId = catalogRetailerId(input.merchantId, input.productId);
  const local = evaluateMerchantProductEligibility(input.product);
  const reasons = [...local.reasons];
  if (!input.product) {
    const revision = stableRevision({ retailerId, action: "delete" });
    return {
      action: "delete",
      eligible: false,
      reasons,
      policyReviewReasons: [],
      retailerId,
      revision,
      projection: null,
    };
  }

  const link = productLink(input.product, input.merchant);
  if (!link) reasons.push("missing_product_link");
  if (reasons.length) {
    const revision = stableRevision({
      retailerId,
      action: "delete",
      reasons: [...reasons].sort(),
      policyReviewReasons: [...local.policyReviewReasons].sort(),
    });
    return {
      action: "delete",
      eligible: false,
      reasons,
      policyReviewReasons: local.policyReviewReasons,
      retailerId,
      revision,
      projection: null,
    };
  }

  const product = input.product;
  const merchant = input.merchant ?? {};
  const description = firstText(product, ["description"], 5000) || local.name;
  const brand =
    firstText(product, ["brand", "company"], 100) ||
    firstText(
      merchant,
      ["businessName", "companyName", "shopName", "name"],
      100,
    ) ||
    "Spaza One merchant";
  const score = Number(product.whatsappPopularityScore ?? 0);
  const projection: MerchantCatalogProjection = {
    retailerId,
    title: local.name,
    description,
    imageUrl: local.imageUrl,
    link,
    priceMinor: local.priceMinor ?? 0,
    currency: "ZAR",
    availability: availability(product),
    condition: "new",
    brand,
    popularityScore: Number.isFinite(score) && score > 0 ? score : 0,
    schemaVersion: WHATSAPP_CATALOG_SCHEMA_VERSION,
  };
  return {
    action: "upsert",
    eligible: true,
    reasons: [],
    policyReviewReasons: [],
    retailerId,
    revision: stableRevision(projection),
    projection,
  };
}
