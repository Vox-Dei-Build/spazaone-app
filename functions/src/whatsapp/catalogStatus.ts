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
import { whatsappProductListMerchantRolloutAllowed } from "./nativeProductList";
import {
  decodeWhatsAppCatalogCursor,
  encodeWhatsAppCatalogCursor,
  summarizeWhatsAppCatalogStatusV2,
} from "./catalogStatusV2";
import { buildMerchantCatalogDecision } from "./catalogProjection";

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

// A merchant currently has about 430 products. The old 100-item ceiling made
// the client call this function five times for one refresh, while every page
// rebuilt the same whole-catalogue snapshot. Keep the response comfortably
// below callable limits while covering normal catalogues in one scan.
const CATALOG_STATUS_PAGE_SIZE = 1_000;
const LEGACY_CATALOG_STATUS_PAGE_SIZE = 100;
const CATALOG_STATUS_PATCH_SIZE = 100;
const CATALOG_STATUS_FRESH_MS = 5 * 60 * 1000;

function requestedProductIds(data: unknown): string[] | null {
  const value = (data as { productIds?: unknown } | null)?.productIds;
  if (value === undefined) return null;
  if (
    !Array.isArray(value) ||
    value.length < 1 ||
    value.length > CATALOG_STATUS_PATCH_SIZE ||
    value.some((item) => typeof item !== "string")
  ) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `productIds must contain 1-${CATALOG_STATUS_PATCH_SIZE} product IDs.`,
    );
  }
  const productIds = [...new Set(value)];
  if (
    productIds.length > CATALOG_STATUS_PATCH_SIZE ||
    productIds.some(
      (productId) =>
        !productId ||
        productId.trim() !== productId ||
        productId.includes("/") ||
        productId.length > 1_500,
    )
  ) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `productIds must contain at most ${CATALOG_STATUS_PATCH_SIZE} valid product IDs.`,
    );
  }
  return productIds;
}

function catalogStatusRolloutEnabled(storeId: string): boolean {
  try {
    return whatsappProductListMerchantRolloutAllowed(storeId);
  } catch (_) {
    // Configuration faults are intentionally represented as not enabled;
    // clients never receive environment/provider details.
    return false;
  }
}

/**
 * Recheck only products which the client already knows are in flight. Mapping
 * and outbox document IDs are deterministic, so direct document reads avoid
 * rescanning every merchant-owned projection for each polling tick.
 */
async function catalogStatusPatch(input: {
  storeId: string;
  productIds: readonly string[];
  rolloutEnabled: boolean;
}) {
  const merchantRef = db.doc(`users/${input.storeId}`);
  const productRefs = input.productIds.map((productId) =>
    db.doc(`users/${input.storeId}/products/${productId}`),
  );
  const [merchant, ...productDocuments] = await db.getAll(
    merchantRef,
    ...productRefs,
  );
  const products = productDocuments
    .map((product, index) => ({
      id: input.productIds[index],
      snapshot: product,
    }))
    .filter((product) => product.snapshot.exists);
  const retailerIds = products.map(
    (product) =>
      buildMerchantCatalogDecision({
        merchantId: input.storeId,
        productId: product.id,
        product: product.snapshot.data(),
        merchant: merchant.data(),
      }).retailerId,
  );
  const [mappingDocuments, outboxDocuments] = await Promise.all([
    retailerIds.length
      ? db.getAll(
          ...retailerIds.map((retailerId) =>
            db.doc(`${WHATSAPP_CATALOG_MAPPINGS}/${retailerId}`),
          ),
        )
      : [],
    retailerIds.length
      ? db.getAll(
          ...retailerIds.map((retailerId) =>
            db.doc(`${WHATSAPP_CATALOG_OUTBOX}/${retailerId}`),
          ),
        )
      : [],
  ]);
  const checkedAtMs = Date.now();
  const snapshot = summarizeWhatsAppCatalogStatusV2({
    merchantId: input.storeId,
    merchant: merchant.data() ?? {},
    products: products.map((product) => ({
      id: product.id,
      data: product.snapshot.data() ?? {},
    })),
    mappings: mappingDocuments
      .filter((mapping) => mapping.exists)
      .map((mapping) => ({
        ...mapping.data(),
        retailerId: mapping.data()?.retailerId ?? mapping.id,
      })),
    outbox: outboxDocuments
      .filter((job) => job.exists)
      .map((job) => ({
        ...job.data(),
        retailerId: job.data()?.retailerId ?? job.id,
      })),
    rolloutEnabled: input.rolloutEnabled,
    checkedAtMs,
  });
  const foundProductIds = new Set(products.map((product) => product.id));
  return {
    schemaVersion: 2,
    partial: true,
    checkedAtMs,
    freshUntilMs: checkedAtMs + CATALOG_STATUS_FRESH_MS,
    rollout: input.rolloutEnabled ? "enabled" : "not_enabled",
    summary: snapshot.summary,
    products: snapshot.products,
    removedProductIds: input.productIds.filter(
      (productId) => !foundProductIds.has(productId),
    ),
    nextPageToken: null,
    catalogVersion: snapshot.catalogVersion,
    retryPermitted: false,
  };
}

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
    const productIds = requestedProductIds(data);
    const rolloutEnabled = catalogStatusRolloutEnabled(storeId);
    if (productIds) {
      if (String(data?.pageToken ?? "").trim()) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "A partial status request cannot include a page token.",
        );
      }
      return catalogStatusPatch({ storeId, productIds, rolloutEnabled });
    }
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
        `pageSize must be between 1 and ${CATALOG_STATUS_PAGE_SIZE}.`,
      );
    }
    // Released clients explicitly request 100. Serving the larger safe page
    // immediately removes their five identical source scans; the signed
    // cursor contract continues to work for catalogues above 1,000 products.
    const effectivePageSize =
      requestedPageSize === LEGACY_CATALOG_STATUS_PAGE_SIZE
        ? CATALOG_STATUS_PAGE_SIZE
        : requestedPageSize;
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
      startIndex + effectivePageSize,
    );
    const hasNextPage =
      startIndex + effectivePageSize < snapshot.products.length;
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
