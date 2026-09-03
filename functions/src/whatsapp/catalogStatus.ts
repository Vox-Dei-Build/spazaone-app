import { FieldPath } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { requireBotRequest } from "../security/requestAuth";
import { assertCallableStoreAccess } from "../stores/storeAccess";
import {
  whatsappCatalogMerchantAllowed,
  whatsappCatalogRuntimeConfig,
} from "./catalogConfig";
import { reconcileMerchantWhatsAppCatalogCompleteness } from "./catalogCompleteness";
import { collectAllNativeCatalogMappingPages } from "./catalogMappingPages";
import {
  WHATSAPP_CATALOG_MAPPINGS,
  WHATSAPP_CATALOG_OUTBOX,
} from "./catalogQueue";
import {
  decodeWhatsAppCatalogCursor,
  encodeWhatsAppCatalogCursor,
  summarizeWhatsAppCatalogStatusV2,
} from "./catalogStatusV2";

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
  const documents = await collectAllNativeCatalogMappingPages(
    async (cursor, limit) => {
      let query = db
        .collection(WHATSAPP_CATALOG_MAPPINGS)
        .where("merchantId", "==", merchantId)
        .orderBy(FieldPath.documentId())
        .limit(limit);
      if (cursor) query = query.startAfter(cursor);
      return (await query.get()).docs;
    },
  );
  return documents.map(summarizeMapping);
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

const CATALOG_STATUS_PAGE_SIZE = 100;
const CATALOG_STATUS_FRESH_MS = 5 * 60 * 1000;

function catalogStatusCursorSecret(): string {
  const secret = String(
    process.env.WHATSAPP_CATALOG_STATUS_CURSOR_SECRET ?? "",
  ).trim();
  if (secret.length < 32) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Catalogue status is not configured.",
    );
  }
  return secret;
}

/**
 * Merchant-facing, sanitized catalogue status. The endpoint intentionally
 * joins server-owned projection state rather than allowing clients to read
 * mapping/outbox collections directly.
 */
export const getWhatsAppCatalogSyncStatusV2 = functions
  .runWith({ secrets: ["WHATSAPP_CATALOG_STATUS_CURSOR_SECRET"] })
  .https.onCall(async (data, context) => {
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
    const requestedPageSize = Number(
      data?.pageSize ?? CATALOG_STATUS_PAGE_SIZE,
    );
    if (
      !Number.isSafeInteger(requestedPageSize) ||
      requestedPageSize < 1 ||
      requestedPageSize > CATALOG_STATUS_PAGE_SIZE
    ) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "pageSize must be between 1 and 100.",
      );
    }
    const cursorSecret = catalogStatusCursorSecret();
    const rawPageToken = String(data?.pageToken ?? "").trim();
    const cursor = rawPageToken
      ? decodeWhatsAppCatalogCursor(rawPageToken, cursorSecret)
      : null;
    if (
      rawPageToken &&
      (!cursor || cursor.uid !== context.auth.uid || cursor.storeId !== storeId)
    ) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "The catalogue page token is invalid.",
        { reason: "INVALID_PAGE_TOKEN" },
      );
    }

    const [merchant, products, mappings, outbox] = await Promise.all([
      db.doc(`users/${storeId}`).get(),
      db.collection(`users/${storeId}/products`).get(),
      db
        .collection(WHATSAPP_CATALOG_MAPPINGS)
        .where("merchantId", "==", storeId)
        .get(),
      db
        .collection(WHATSAPP_CATALOG_OUTBOX)
        .where("merchantId", "==", storeId)
        .get(),
    ]);
    let rolloutEnabled = false;
    try {
      const config = whatsappCatalogRuntimeConfig();
      rolloutEnabled = whatsappCatalogMerchantAllowed(config, storeId);
    } catch (_) {
      // Configuration faults are intentionally represented as not enabled;
      // clients never receive environment/provider details.
    }
    const checkedAtMs = Date.now();
    const snapshot = summarizeWhatsAppCatalogStatusV2({
      merchantId: storeId,
      merchant: merchant.data() ?? {},
      products: products.docs.map((product) => ({
        id: product.id,
        data: product.data() ?? {},
      })),
      mappings: mappings.docs.map((mapping) => ({
        ...mapping.data(),
        retailerId: mapping.data().retailerId ?? mapping.id,
      })),
      outbox: outbox.docs.map((job) => ({
        ...job.data(),
        retailerId: job.data().retailerId ?? job.id,
      })),
      rolloutEnabled,
      checkedAtMs,
    });
    if (cursor && cursor.catalogVersion !== snapshot.catalogVersion) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Catalogue changed while loading. Start again.",
        { reason: "CATALOG_CHANGED" },
      );
    }
    const startIndex = cursor
      ? snapshot.products.findIndex(
          (product) => product.productId === cursor.lastProductId,
        ) + 1
      : 0;
    if (cursor && startIndex === 0) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Catalogue changed while loading. Start again.",
        { reason: "CATALOG_CHANGED" },
      );
    }
    const page = snapshot.products.slice(
      startIndex,
      startIndex + requestedPageSize,
    );
    const hasNextPage =
      startIndex + requestedPageSize < snapshot.products.length;
    const lastProductId = page.at(-1)?.productId;
    const nextPageToken =
      hasNextPage && lastProductId
        ? encodeWhatsAppCatalogCursor(
            {
              uid: context.auth.uid,
              storeId,
              catalogVersion: snapshot.catalogVersion,
              lastProductId,
            },
            cursorSecret,
          )
        : null;
    return {
      schemaVersion: 2,
      checkedAtMs,
      freshUntilMs: checkedAtMs + CATALOG_STATUS_FRESH_MS,
      rollout: rolloutEnabled ? "enabled" : "not_enabled",
      summary: snapshot.summary,
      products: page,
      nextPageToken,
      catalogVersion: snapshot.catalogVersion,
      retryPermitted: false,
    };
  });

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

/** Exact live eligibility-versus-Meta-acceptance audit for one merchant. */
export const getMerchantWhatsAppCatalogCompletenessBotHttp = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    if (req.method !== "POST") {
      res.status(405).json({
        outcome: "rejected",
        reason: "method_not_allowed",
        code: "METHOD_NOT_ALLOWED",
      });
      return;
    }
    const merchantId = String(req.body?.merchantId ?? "").trim();
    if (!/^[A-Za-z0-9_-]{1,200}$/.test(merchantId)) {
      res.status(400).json({
        outcome: "rejected",
        reason: "invalid_request",
        code: "INVALID_REQUEST",
      });
      return;
    }
    let config;
    try {
      config = whatsappCatalogRuntimeConfig();
    } catch (_) {
      res.status(503).json({
        outcome: "rejected",
        reason: "configuration_blocked",
        code: "CONFIGURATION_BLOCKED",
      });
      return;
    }
    if (!whatsappCatalogMerchantAllowed(config, merchantId)) {
      res.status(403).json({
        outcome: "rejected",
        reason: "merchant_not_allowed",
        code: "MERCHANT_NOT_ALLOWED",
      });
      return;
    }
    res.status(200).json({
      outcome: "checked",
      ...(await reconcileMerchantWhatsAppCatalogCompleteness(merchantId)),
    });
  });
