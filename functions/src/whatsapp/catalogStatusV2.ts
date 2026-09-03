import { createHash, createHmac, timingSafeEqual } from "crypto";
import { buildMerchantCatalogDecision } from "./catalogProjection";

export type WhatsAppCatalogProductStatus =
  | "not_listed"
  | "needs_attention"
  | "syncing"
  | "live"
  | "stale"
  | "review_required"
  | "removal_syncing"
  | "support_review";

export type WhatsAppCatalogProductAction =
  | "none"
  | "edit_product"
  | "complete_shop_link"
  | "refresh"
  | "contact_support";

export type WhatsAppCatalogProductStatusV2 = {
  productId: string;
  status: WhatsAppCatalogProductStatus;
  reasonCodes: string[];
  action: WhatsAppCatalogProductAction;
  updatedAtMs: number;
  supportReference?: string;
};

export type WhatsAppCatalogStatusSummaryV2 = {
  totalProducts: number;
  eligible: number;
  live: number;
  syncing: number;
  needsAttention: number;
  removalSyncing: number;
  supportReview: number;
  canBrowseFive: boolean;
  canBrowseTen: boolean;
};

export type WhatsAppCatalogStatusSource = {
  merchantId?: unknown;
  retailerId?: unknown;
  productId?: unknown;
  status?: unknown;
  desiredAction?: unknown;
  desiredRevision?: unknown;
  processingRevision?: unknown;
  lastAppliedRevision?: unknown;
  lastSubmittedRevision?: unknown;
  metaPolicyStatus?: unknown;
  updatedAtMs?: unknown;
};

export type WhatsAppCatalogStatusV2Input = {
  merchantId: string;
  merchant: Record<string, unknown>;
  products: ReadonlyArray<{
    id: string;
    data: Record<string, unknown>;
  }>;
  mappings: readonly WhatsAppCatalogStatusSource[];
  outbox: readonly WhatsAppCatalogStatusSource[];
  rolloutEnabled: boolean;
  checkedAtMs: number;
};

export type WhatsAppCatalogStatusV2Snapshot = {
  catalogVersion: string;
  summary: WhatsAppCatalogStatusSummaryV2;
  products: WhatsAppCatalogProductStatusV2[];
};

type CatalogCursor = {
  uid: string;
  storeId: string;
  catalogVersion: string;
  lastProductId: string;
};

const SYNCING_STATES = new Set(["pending", "processing", "submitted", "retry"]);
const KNOWN_MAPPING_STATES = new Set([
  "pending",
  "pending_delete",
  "processing",
  "submitted",
  "retry",
  "active",
  "deleted",
  "blocked",
  "rejected",
  "failed",
]);
const KNOWN_OUTBOX_STATES = new Set([
  "pending",
  "pending_delete",
  "processing",
  "submitted",
  "retry",
  "active",
  "deleted",
  "blocked",
  "rejected",
  "failed",
]);
const KNOWN_PROVIDER_STATES = new Set(["accepted", "rejected", "removed"]);

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function updatedAtMs(...values: unknown[]): number {
  return values.reduce<number>((latest, value) => {
    const candidate = Number(value ?? 0);
    return Number.isFinite(candidate) ? Math.max(latest, candidate) : latest;
  }, 0);
}

function groupByProductId(
  values: readonly WhatsAppCatalogStatusSource[],
): Map<string, WhatsAppCatalogStatusSource[]> {
  const grouped = new Map<string, WhatsAppCatalogStatusSource[]>();
  for (const value of values) {
    const productId = text(value.productId);
    if (!productId) continue;
    grouped.set(productId, [...(grouped.get(productId) ?? []), value]);
  }
  return grouped;
}

function providerMayContainProduct(
  mapping: WhatsAppCatalogStatusSource | undefined,
  outbox: WhatsAppCatalogStatusSource | undefined,
): boolean {
  return Boolean(
    text(mapping?.lastAppliedRevision) ||
      text(mapping?.lastSubmittedRevision) ||
      text(outbox?.processingRevision) ||
      text(outbox?.lastAppliedRevision) ||
      text(outbox?.lastSubmittedRevision) ||
      text(mapping?.metaPolicyStatus) === "accepted",
  );
}

function supportReference(
  merchantId: string,
  productId: string,
  revision: string,
): string {
  return `CAT-${createHash("sha256")
    .update(`${merchantId}\n${productId}\n${revision}`)
    .digest("hex")
    .slice(0, 10)
    .toUpperCase()}`;
}

function attentionAction(
  reasonCodes: readonly string[],
): WhatsAppCatalogProductAction {
  return reasonCodes.includes("missing_product_link")
    ? "complete_shop_link"
    : "edit_product";
}

function productStatus(input: {
  merchantId: string;
  productId: string;
  product: Record<string, unknown>;
  merchant: Record<string, unknown>;
  mappings: readonly WhatsAppCatalogStatusSource[];
  outbox: readonly WhatsAppCatalogStatusSource[];
  rolloutEnabled: boolean;
  checkedAtMs: number;
}): WhatsAppCatalogProductStatusV2 {
  const decision = buildMerchantCatalogDecision({
    merchantId: input.merchantId,
    productId: input.productId,
    product: input.product,
    merchant: input.merchant,
  });
  const mapping = input.mappings[0];
  const job = input.outbox[0];
  const mappingStatus = text(mapping?.status);
  const outboxStatus = text(job?.status);
  const providerStatus = text(mapping?.metaPolicyStatus);
  const lastUpdatedAtMs =
    updatedAtMs(mapping?.updatedAtMs, job?.updatedAtMs) || input.checkedAtMs;
  const inconsistent = input.mappings.length > 1 || input.outbox.length > 1;
  const support = () => ({
    productId: input.productId,
    status: "support_review" as const,
    reasonCodes: ["inconsistent_state"],
    action: "contact_support" as const,
    updatedAtMs: lastUpdatedAtMs,
    supportReference: supportReference(
      input.merchantId,
      input.productId,
      decision.revision,
    ),
  });

  if (inconsistent) return support();
  if (
    (mappingStatus && !KNOWN_MAPPING_STATES.has(mappingStatus)) ||
    (outboxStatus && !KNOWN_OUTBOX_STATES.has(outboxStatus)) ||
    (providerStatus && !KNOWN_PROVIDER_STATES.has(providerStatus)) ||
    (text(mapping?.merchantId) &&
      text(mapping?.merchantId) !== input.merchantId) ||
    (text(mapping?.retailerId) &&
      text(mapping?.retailerId) !== decision.retailerId) ||
    (text(job?.merchantId) && text(job?.merchantId) !== input.merchantId) ||
    (text(job?.retailerId) && text(job?.retailerId) !== decision.retailerId)
  ) {
    return support();
  }

  const optedOut = decision.reasons.some((reason) =>
    ["not_whatsapp_listed", "internal_product"].includes(reason),
  );
  if (decision.action === "delete") {
    const removalInFlight =
      mappingStatus === "pending_delete" ||
      (text(job?.desiredAction) === "delete" &&
        SYNCING_STATES.has(outboxStatus));
    if (
      removalInFlight ||
      (optedOut &&
        providerMayContainProduct(mapping, job) &&
        mappingStatus !== "deleted" &&
        providerStatus !== "removed")
    ) {
      return {
        productId: input.productId,
        status: "removal_syncing",
        reasonCodes: ["removal_pending"],
        action: "none",
        updatedAtMs: lastUpdatedAtMs,
      };
    }
    if (optedOut) {
      return {
        productId: input.productId,
        status: "not_listed",
        reasonCodes: decision.reasons.filter((reason) =>
          ["not_whatsapp_listed", "internal_product"].includes(reason),
        ),
        action: "none",
        updatedAtMs: lastUpdatedAtMs,
      };
    }
    if (decision.reasons.includes("policy_review_required")) {
      return {
        productId: input.productId,
        status: "review_required",
        reasonCodes: ["policy_review_required"],
        action: "contact_support",
        updatedAtMs: lastUpdatedAtMs,
        supportReference: supportReference(
          input.merchantId,
          input.productId,
          decision.revision,
        ),
      };
    }
    return {
      productId: input.productId,
      status: "needs_attention",
      reasonCodes: [...decision.reasons],
      action: attentionAction(decision.reasons),
      updatedAtMs: lastUpdatedAtMs,
    };
  }

  if (!input.rolloutEnabled) {
    return {
      productId: input.productId,
      status: "syncing",
      reasonCodes: ["catalogue_not_enabled"],
      action: "none",
      updatedAtMs: lastUpdatedAtMs,
    };
  }
  if (
    mappingStatus === "rejected" ||
    outboxStatus === "rejected" ||
    providerStatus === "rejected"
  ) {
    return {
      productId: input.productId,
      status: "review_required",
      reasonCodes: ["provider_rejected"],
      action: "contact_support",
      updatedAtMs: lastUpdatedAtMs,
      supportReference: supportReference(
        input.merchantId,
        input.productId,
        decision.revision,
      ),
    };
  }
  if (
    mappingStatus === "active" &&
    providerStatus === "accepted" &&
    text(mapping?.lastAppliedRevision) === decision.revision
  ) {
    return {
      productId: input.productId,
      status: "live",
      reasonCodes: [],
      action: "none",
      updatedAtMs: lastUpdatedAtMs,
    };
  }
  if (mappingStatus === "active") {
    if (providerStatus !== "accepted") return support();
    return {
      productId: input.productId,
      status: "stale",
      reasonCodes: ["stale_revision"],
      action: "refresh",
      updatedAtMs: lastUpdatedAtMs,
    };
  }
  if (mappingStatus === "blocked" || outboxStatus === "blocked") {
    return {
      productId: input.productId,
      status: "needs_attention",
      reasonCodes: ["catalog_item_unavailable"],
      action: "edit_product",
      updatedAtMs: lastUpdatedAtMs,
    };
  }
  if (
    (!mapping && !job) ||
    ["deleted", "pending"].includes(mappingStatus) ||
    SYNCING_STATES.has(mappingStatus) ||
    SYNCING_STATES.has(outboxStatus)
  ) {
    return {
      productId: input.productId,
      status: "syncing",
      reasonCodes: ["sync_pending"],
      action: "none",
      updatedAtMs: lastUpdatedAtMs,
    };
  }
  return support();
}

export function summarizeWhatsAppCatalogStatusV2(
  input: WhatsAppCatalogStatusV2Input,
): WhatsAppCatalogStatusV2Snapshot {
  const mappingsByProduct = groupByProductId(input.mappings);
  const outboxByProduct = groupByProductId(input.outbox);
  let eligible = 0;
  const evaluated = [...input.products]
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .map((product) => {
      const decision = buildMerchantCatalogDecision({
        merchantId: input.merchantId,
        productId: product.id,
        product: product.data,
        merchant: input.merchant,
      });
      if (decision.action === "upsert") eligible += 1;
      const status = productStatus({
        merchantId: input.merchantId,
        productId: product.id,
        product: product.data,
        merchant: input.merchant,
        mappings: mappingsByProduct.get(product.id) ?? [],
        outbox: outboxByProduct.get(product.id) ?? [],
        rolloutEnabled: input.rolloutEnabled,
        checkedAtMs: input.checkedAtMs,
      });
      return { status, decisionRevision: decision.revision };
    });
  const products = evaluated.map((product) => product.status);
  const count = (status: WhatsAppCatalogProductStatus) =>
    products.filter((product) => product.status === status).length;
  const live = count("live");
  const syncing = count("syncing");
  const removalSyncing = count("removal_syncing");
  const supportReview = count("support_review");
  const needsAttention = products.filter((product) =>
    ["needs_attention", "stale", "review_required", "support_review"].includes(
      product.status,
    ),
  ).length;
  const catalogVersion = createHash("sha256")
    .update(
      JSON.stringify({
        rolloutEnabled: input.rolloutEnabled,
        products: evaluated.map((product) => ({
          productId: product.status.productId,
          decisionRevision: product.decisionRevision,
          status: product.status.status,
          reasonCodes: product.status.reasonCodes,
          action: product.status.action,
        })),
      }),
    )
    .digest("hex");
  return {
    catalogVersion,
    summary: {
      totalProducts: products.length,
      eligible,
      live,
      syncing,
      needsAttention,
      removalSyncing,
      supportReview,
      canBrowseFive: live >= 5,
      canBrowseTen: live >= 10,
    },
    products,
  };
}

export function encodeWhatsAppCatalogCursor(
  cursor: CatalogCursor,
  secret: string,
): string {
  const payload = Buffer.from(JSON.stringify(cursor)).toString("base64url");
  const signature = createHmac("sha256", secret)
    .update(payload)
    .digest("base64url");
  return `${payload}.${signature}`;
}

export function decodeWhatsAppCatalogCursor(
  value: string,
  secret: string,
): CatalogCursor | null {
  try {
    const [payload, suppliedSignature, extra] = value.split(".");
    if (!payload || !suppliedSignature || extra !== undefined) return null;
    const expectedSignature = createHmac("sha256", secret)
      .update(payload)
      .digest("base64url");
    const supplied = Buffer.from(suppliedSignature);
    const expected = Buffer.from(expectedSignature);
    if (
      supplied.length !== expected.length ||
      !timingSafeEqual(supplied, expected)
    ) {
      return null;
    }
    const parsed = JSON.parse(
      Buffer.from(payload, "base64url").toString("utf8"),
    ) as Partial<CatalogCursor>;
    if (
      !text(parsed.uid) ||
      !text(parsed.storeId) ||
      !/^[a-f0-9]{64}$/.test(text(parsed.catalogVersion)) ||
      !text(parsed.lastProductId)
    ) {
      return null;
    }
    return {
      uid: text(parsed.uid),
      storeId: text(parsed.storeId),
      catalogVersion: text(parsed.catalogVersion),
      lastProductId: text(parsed.lastProductId),
    };
  } catch (_) {
    return null;
  }
}
