import { createHash } from "crypto";
import { db } from "../config/main";
import { merchantBotFeatureDecision } from "../ecommerce/merchantBotFeatureAccess";
import { buildMerchantCatalogDecision } from "./catalogProjection";
import {
  WHATSAPP_CATALOG_MAPPINGS,
  WHATSAPP_CATALOG_OUTBOX,
} from "./catalogQueue";

export type MerchantCatalogCompletenessProduct = {
  id: string;
  data: Record<string, unknown>;
};

export type MerchantCatalogCompletenessMapping = {
  merchantId: unknown;
  productId: unknown;
  retailerId: unknown;
  status: unknown;
  metaPolicyStatus: unknown;
  lastAppliedRevision: unknown;
  lastSubmittedRevision?: unknown;
};

export type MerchantWhatsAppCatalogCompleteness = {
  merchantId: string;
  eligibleProducts: number;
  activeAcceptedProducts: number;
  missingProducts: number;
  staleProducts: number;
  unexpectedActiveMappings: number;
  pendingOutboxJobs: number;
  eligibleSetDigest: string;
  activeAcceptedSetDigest: string;
  complete: boolean;
};

function setDigest(values: readonly string[]): string {
  return createHash("sha256")
    .update([...values].sort().join("\n"))
    .digest("hex");
}

/**
 * Compares exact product/revision identities, not counts alone. An accepted
 * mapping for a stale, foreign, or no-longer-eligible product cannot make an
 * incomplete merchant look ready.
 */
export function summarizeMerchantWhatsAppCatalogCompleteness(input: {
  merchantId: string;
  merchant: Record<string, unknown>;
  products: readonly MerchantCatalogCompletenessProduct[];
  mappings: readonly MerchantCatalogCompletenessMapping[];
  outboxStatuses?: readonly unknown[];
  supplierOrdersEnabled?: boolean;
}): MerchantWhatsAppCatalogCompleteness {
  const eligible = new Map<string, { productId: string; revision: string }>();
  const excludedSupplierRetailerIds = new Set<string>();
  for (const product of input.products) {
    const decision = buildMerchantCatalogDecision({
      merchantId: input.merchantId,
      productId: product.id,
      product: product.data,
      merchant: input.merchant,
    });
    if (
      product.data.isDropshipListing === true &&
      input.supplierOrdersEnabled === false
    ) {
      excludedSupplierRetailerIds.add(decision.retailerId);
      continue;
    }
    if (decision.action === "upsert") {
      eligible.set(decision.retailerId, {
        productId: product.id,
        revision: decision.revision,
      });
    }
  }

  const accepted = new Set<string>();
  const acceptedRevisions: string[] = [];
  let staleProducts = 0;
  let unexpectedActiveMappings = 0;
  for (const mapping of input.mappings) {
    const status = String(mapping.status ?? "");
    const retailerId = String(mapping.retailerId ?? "").trim();
    if (excludedSupplierRetailerIds.has(retailerId)) continue;
    const providerMayContainMapping =
      mapping.metaPolicyStatus === "accepted" ||
      Boolean(String(mapping.lastAppliedRevision ?? "").trim()) ||
      Boolean(String(mapping.lastSubmittedRevision ?? "").trim());
    if (status !== "active") {
      if (
        providerMayContainMapping &&
        !(status === "deleted" && mapping.metaPolicyStatus === "removed")
      ) {
        unexpectedActiveMappings += 1;
      }
      continue;
    }
    const expected = eligible.get(retailerId);
    if (
      String(mapping.merchantId ?? "").trim() !== input.merchantId ||
      !expected ||
      String(mapping.productId ?? "").trim() !== expected.productId
    ) {
      unexpectedActiveMappings += 1;
      continue;
    }
    if (
      mapping.metaPolicyStatus !== "accepted" ||
      String(mapping.lastAppliedRevision ?? "").trim() !== expected.revision
    ) {
      staleProducts += 1;
      continue;
    }
    accepted.add(retailerId);
    acceptedRevisions.push(`${retailerId}:${expected.revision}`);
  }

  const missingProducts = Math.max(0, eligible.size - accepted.size);
  const eligibleRevisions = [...eligible.entries()].map(
    ([retailerId, value]) => `${retailerId}:${value.revision}`,
  );
  const eligibleSetDigest = setDigest(eligibleRevisions);
  const activeAcceptedSetDigest = setDigest(acceptedRevisions);
  const pendingOutboxJobs = (input.outboxStatuses ?? []).filter((status) =>
    ["pending", "retry", "processing", "submitted"].includes(
      String(status ?? ""),
    ),
  ).length;
  return {
    merchantId: input.merchantId,
    eligibleProducts: eligible.size,
    activeAcceptedProducts: accepted.size,
    missingProducts,
    staleProducts,
    unexpectedActiveMappings,
    pendingOutboxJobs,
    eligibleSetDigest,
    activeAcceptedSetDigest,
    complete:
      missingProducts === 0 &&
      staleProducts === 0 &&
      unexpectedActiveMappings === 0 &&
      pendingOutboxJobs === 0 &&
      eligibleSetDigest === activeAcceptedSetDigest,
  };
}

/** Live fail-closed readiness check for new catalogue sessions and audits. */
export async function reconcileMerchantWhatsAppCatalogCompleteness(
  merchantId: string,
): Promise<MerchantWhatsAppCatalogCompleteness> {
  const [merchant, products, mappings, outbox, supplierAccess] =
    await Promise.all([
      db.doc(`users/${merchantId}`).get(),
      db.collection(`users/${merchantId}/products`).get(),
      db
        .collection(WHATSAPP_CATALOG_MAPPINGS)
        .where("merchantId", "==", merchantId)
        .get(),
      db
        .collection(WHATSAPP_CATALOG_OUTBOX)
        .where("merchantId", "==", merchantId)
        .get(),
      merchantBotFeatureDecision(merchantId, "supplierOrders"),
    ]);
  return summarizeMerchantWhatsAppCatalogCompleteness({
    merchantId,
    merchant: merchant.data() ?? {},
    products: products.docs.map((product) => ({
      id: product.id,
      data: product.data() ?? {},
    })),
    mappings: mappings.docs.map((mapping) => ({
      merchantId: mapping.data().merchantId,
      productId: mapping.data().productId,
      retailerId: mapping.data().retailerId ?? mapping.id,
      status: mapping.data().status,
      metaPolicyStatus: mapping.data().metaPolicyStatus,
      lastAppliedRevision: mapping.data().lastAppliedRevision,
      lastSubmittedRevision: mapping.data().lastSubmittedRevision,
    })),
    outboxStatuses: outbox.docs.map((job) => job.data().status),
    supplierOrdersEnabled: supplierAccess.enabled,
  });
}
