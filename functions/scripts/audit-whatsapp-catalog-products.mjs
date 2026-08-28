#!/usr/bin/env node

/**
 * Read-only merchant-product census. It never prints merchant/product IDs,
 * names, descriptions, image URLs, or provider credentials.
 */
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

import {
  buildMerchantCatalogDecision,
  evaluateMerchantProductEligibility,
} from "../lib/whatsapp/catalogProjection.js";
import { probeCatalogImageUrl } from "../lib/whatsapp/catalogImage.js";

const args = new Map();
for (let index = 2; index < process.argv.length; index += 1) {
  const argument = process.argv[index];
  if (!argument.startsWith("--")) continue;
  const [key, inline] = argument.slice(2).split("=", 2);
  const next = process.argv[index + 1];
  if (inline !== undefined) args.set(key, inline);
  else if (next && !next.startsWith("--")) {
    args.set(key, next);
    index += 1;
  } else args.set(key, "true");
}

const projectId = String(args.get("project-id") ?? "").trim();
if (
  !/^(pasella-ledger|spazaone-dev|spazaone-dev-za|demo-[a-z0-9-]+)$/.test(
    projectId,
  )
) {
  throw new Error("Pass an explicit registered --project-id.");
}
const checkImages = args.get("check-images") === "true";
initializeApp({ credential: applicationDefault(), projectId });
const db = getFirestore();

const snapshot = await db.collectionGroup("products").get();
const products = snapshot.docs
  .map((doc) => {
    const match = doc.ref.path.match(/^users\/([^/]+)\/products\/([^/]+)$/);
    return match
      ? {
          merchantId: match[1],
          productId: match[2],
          data: doc.data(),
        }
      : null;
  })
  .filter(Boolean);
const merchantIds = [...new Set(products.map((product) => product.merchantId))];
const merchantSnapshots = await Promise.all(
  merchantIds.map((merchantId) => db.doc(`users/${merchantId}`).get()),
);
const merchants = new Map(
  merchantSnapshots.map((merchant) => [merchant.id, merchant.data() ?? {}]),
);

const aggregate = {
  totalProducts: products.length,
  merchants: merchantIds.length,
  whatsappFlagged: 0,
  explicitlyInternalOrPaused: 0,
  internalWithWhatsAppFlag: 0,
  structurallyEligible: 0,
  providerPayloadReady: 0,
  policyReviewRequired: 0,
  policyReviewAmongWhatsAppFlagged: 0,
  reachableImageReady: checkImages ? 0 : null,
  imageProbeFailures: checkImages ? 0 : null,
  uniqueCandidateImages: checkImages ? 0 : null,
  uniqueReachableImages: checkImages ? 0 : null,
  uniqueFailedImages: checkImages ? 0 : null,
  reasons: {},
};
const candidates = [];
for (const product of products) {
  const whatsappFlagged =
    product.data.whatsappListed === true ||
    product.data.whatsappEnabled === true ||
    product.data.availableOnWhatsApp === true;
  if (whatsappFlagged) aggregate.whatsappFlagged += 1;
  const local = evaluateMerchantProductEligibility(product.data);
  if (local.reasons.includes("internal_product")) {
    aggregate.explicitlyInternalOrPaused += 1;
    if (whatsappFlagged) aggregate.internalWithWhatsAppFlag += 1;
  }
  if (local.eligible) aggregate.structurallyEligible += 1;
  if (local.policyReviewReasons.length) {
    aggregate.policyReviewRequired += 1;
    if (whatsappFlagged) aggregate.policyReviewAmongWhatsAppFlagged += 1;
  }
  const decision = buildMerchantCatalogDecision({
    merchantId: product.merchantId,
    productId: product.productId,
    product: product.data,
    merchant: merchants.get(product.merchantId),
  });
  for (const reason of decision.reasons) {
    aggregate.reasons[reason] = (aggregate.reasons[reason] ?? 0) + 1;
  }
  if (decision.action !== "upsert") continue;
  aggregate.providerPayloadReady += 1;
  candidates.push({
    merchantId: product.merchantId,
    imageUrl: decision.projection.imageUrl,
  });
}

if (checkImages) {
  const cache = new Map();
  const readyByMerchant = new Map(merchantIds.map((id) => [id, 0]));
  let next = 0;
  const workers = Array.from(
    { length: Math.min(12, candidates.length) },
    async () => {
      while (next < candidates.length) {
        const item = candidates[next++];
        if (!cache.has(item.imageUrl)) {
          cache.set(item.imageUrl, probeCatalogImageUrl(item.imageUrl));
        }
        const result = await cache.get(item.imageUrl);
        if (result.state === "valid") {
          aggregate.reachableImageReady += 1;
          readyByMerchant.set(
            item.merchantId,
            (readyByMerchant.get(item.merchantId) ?? 0) + 1,
          );
        } else aggregate.imageProbeFailures += 1;
      }
    },
  );
  await Promise.all(workers);
  const uniqueResults = await Promise.all(cache.values());
  aggregate.uniqueCandidateImages = uniqueResults.length;
  aggregate.uniqueReachableImages = uniqueResults.filter(
    (result) => result.state === "valid",
  ).length;
  aggregate.uniqueFailedImages =
    aggregate.uniqueCandidateImages - aggregate.uniqueReachableImages;
  const counts = [...readyByMerchant.values()];
  aggregate.merchantReadiness = {
    withAny: counts.filter((count) => count >= 1).length,
    withAtLeastFive: counts.filter((count) => count >= 5).length,
    withAtLeastTen: counts.filter((count) => count >= 10).length,
    withNone: counts.filter((count) => count === 0).length,
  };
}

process.stdout.write(`${JSON.stringify(aggregate, null, 2)}\n`);
