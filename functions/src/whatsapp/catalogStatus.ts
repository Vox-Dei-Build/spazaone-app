import { db, functions } from "../config/main";
import { requireBotRequest } from "../security/requestAuth";
import { assertCallableStoreAccess } from "../stores/storeAccess";
import {
  whatsappCatalogMerchantAllowed,
  whatsappCatalogRuntimeConfig,
} from "./catalogConfig";
import { WHATSAPP_CATALOG_MAPPINGS } from "./catalogQueue";

type MappingSummary = {
  productId: string;
  retailerId: string;
  status: string;
  popularityScore: number;
  updatedAtMs: number;
};

function summarizeMapping(
  doc: FirebaseFirestore.QueryDocumentSnapshot,
): MappingSummary {
  const value = doc.data();
  return {
    productId: String(value.productId ?? ""),
    retailerId: String(value.retailerId ?? doc.id),
    status: String(value.status ?? "unknown"),
    popularityScore: Number(value.popularityScore ?? 0),
    updatedAtMs: Number(value.updatedAtMs ?? 0),
  };
}

async function merchantMappings(merchantId: string): Promise<MappingSummary[]> {
  const snapshot = await db
    .collection(WHATSAPP_CATALOG_MAPPINGS)
    .where("merchantId", "==", merchantId)
    .limit(2000)
    .get();
  return snapshot.docs.map(summarizeMapping);
}

function merchantStatusMessage(input: {
  active: number;
  pending: number;
  blocked: number;
}): string {
  if (input.active >= 10) {
    return `${input.active} products are ready for WhatsApp browsing.`;
  }
  if (input.active >= 5) {
    return `${input.active} products are ready. Add valid pictures to reach a ten-product view.`;
  }
  if (input.pending > 0) {
    return "Your WhatsApp product view is still syncing. No action is needed yet.";
  }
  if (input.blocked > 0) {
    return "Some products need a valid price, public picture, ordering link, or WhatsApp listing before they can appear.";
  }
  return "Add at least five WhatsApp-listed products with valid prices and pictures.";
}

export const getWhatsAppCatalogSyncStatusV1 = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in to view catalogue status.",
      );
    }
    if (!context.app) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "App verification is required.",
      );
    }
    const storeId = String(data?.storeId ?? context.auth.uid).trim();
    await assertCallableStoreAccess(context, storeId);
    const mappings = await merchantMappings(storeId);
    const counts: Record<string, number> = {};
    for (const item of mappings) {
      counts[item.status] = (counts[item.status] ?? 0) + 1;
    }
    const active = counts.active ?? 0;
    const pending = ["pending", "pending_delete", "processing", "submitted"]
      .map((status) => counts[status] ?? 0)
      .reduce((sum, count) => sum + count, 0);
    const blocked = ["blocked", "failed", "rejected"]
      .map((status) => counts[status] ?? 0)
      .reduce((sum, count) => sum + count, 0);
    return {
      activeProducts: active,
      pendingProducts: pending,
      blockedProducts: blocked,
      canBrowseFive: active >= 5,
      canBrowseTen: active >= 10,
      message: merchantStatusMessage({ active, pending, blocked }),
    };
  },
);

/** Trusted Botpress read: only active retailer IDs for the requested merchant. */
export const getMerchantWhatsAppProductListBotHttp = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    if (req.method !== "POST") {
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }
    const merchantId = String(req.body?.merchantId ?? "").trim();
    const requested = Number(req.body?.limit ?? 10);
    if (!merchantId) {
      res.status(400).json({ error: "merchantId is required" });
      return;
    }
    const limit = Number.isSafeInteger(requested)
      ? Math.max(5, Math.min(10, requested))
      : 10;
    const config = whatsappCatalogRuntimeConfig();
    if (!whatsappCatalogMerchantAllowed(config, merchantId)) {
      res.status(403).json({
        catalogId: null,
        merchantId,
        requestedLimit: limit,
        availableProducts: 0,
        ready: false,
        productItems: [],
        reason: "merchant_not_allowed",
      });
      return;
    }
    const mappings = (await merchantMappings(merchantId))
      .filter((item) => item.status === "active" && item.retailerId)
      .sort(
        (a, b) =>
          b.popularityScore - a.popularityScore ||
          b.updatedAtMs - a.updatedAtMs ||
          a.retailerId.localeCompare(b.retailerId),
      );
    res.status(200).json({
      catalogId: config.catalogId || null,
      merchantId,
      requestedLimit: limit,
      availableProducts: mappings.length,
      ready: mappings.length >= 5,
      productItems: mappings.slice(0, limit).map((item) => ({
        productId: item.productId,
        productRetailerId: item.retailerId,
      })),
    });
  });
