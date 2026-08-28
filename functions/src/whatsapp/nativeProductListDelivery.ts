import { randomBytes } from "crypto";
import { FieldPath, FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { merchantBotFeatureDecision } from "../ecommerce/merchantBotFeatureAccess";
import { requireBotRequest } from "../security/requestAuth";
import {
  buildMerchantCatalogDecision,
  MerchantCatalogProjection,
} from "./catalogProjection";
import { reconcileMerchantWhatsAppCatalogCompleteness } from "./catalogCompleteness";
import {
  collectAllNativeCatalogMappingPages,
  collectNativeCatalogBatchReads,
} from "./catalogMappingPages";
import { WHATSAPP_CATALOG_MAPPINGS } from "./catalogQueue";
import {
  MetaWhatsAppProductListError,
  NativeProductListDeliveryRecord,
  WhatsAppCatalogDeliveryFormat,
  buildMetaWhatsAppProductCarouselPayload,
  buildMetaWhatsAppProductListPayload,
  buildMetaWhatsAppSingleProductPayload,
  currentControlledWhatsAppRecipientDigest,
  decideNativeProductListClaim,
  normalizeWhatsAppRecipient,
  opaqueProductListId,
  productListDeliveryFingerprint,
  productListRetryDelayMs,
  selectNativeCatalogPage,
  sendMetaWhatsAppCatalogWithFallback,
  whatsappNativeCatalogAccessReason,
  whatsappProductListRuntimeConfig,
} from "./nativeProductList";

export const WHATSAPP_PRODUCT_LIST_DELIVERIES = "whatsappProductListDeliveries";
export const WHATSAPP_PRODUCT_LIST_RECIPIENT_STATE =
  "whatsappProductListRecipientState";
const DELIVERY_LEASE_MS = 30_000;

type Mapping = {
  merchantId: string;
  productId: string;
  retailerId: string;
  lastAppliedRevision: string;
  popularityScore: number;
  updatedAtMs: number;
};

export type ResolvedNativeCatalogSupplierMetadata =
  | { isDropshipListing: false }
  | { isDropshipListing: true; commerceListingId: string };

export type ResolvedMerchantWhatsAppCatalogProductResponse = {
  outcome: "found";
  product: {
    id: string;
    retailerId: string;
    name: string;
    description: string;
    imageUrl: string;
    price: number;
    priceMinor: number;
    currency: "ZAR";
    availability: "in stock" | "out of stock";
  } & ResolvedNativeCatalogSupplierMetadata;
};

export type NativeCatalogProductKind =
  | { kind: "owned" }
  | { kind: "supplier"; commerceListingId: string }
  | { kind: "invalid_supplier" };

/**
 * Seller product documents are merchant-writable, so this only parses the
 * claimed supplier reference. The endpoint separately binds it to the
 * server-only commerce listing before exposing it to the bot.
 */
export function nativeCatalogProductKind(
  product: Record<string, unknown>,
): NativeCatalogProductKind {
  if (product.isDropshipListing !== true) return { kind: "owned" };
  const commerceListingId = String(product.commerceListingId ?? "").trim();
  return /^[A-Za-z0-9_-]{1,160}$/.test(commerceListingId)
    ? { kind: "supplier", commerceListingId }
    : { kind: "invalid_supplier" };
}

export function nativeCatalogProductAllowedByMerchantFeature(
  product: Record<string, unknown> | undefined,
  supplierOrdersEnabled: boolean,
): boolean {
  return product?.isDropshipListing !== true || supplierOrdersEnabled;
}

/**
 * A supplier marker becomes authoritative only when the server-only listing
 * is active, belongs to the same merchant/product, and still has the exact
 * projected customer price. No supplier costs or provider identifiers cross
 * the bot wire boundary.
 */
export function nativeCatalogSupplierListingMatches(input: {
  exists: boolean;
  requestedMerchantId: string;
  requestedProductId: string;
  expectedPriceMinor: number;
  listing: Record<string, unknown>;
}): boolean {
  return (
    input.exists &&
    input.listing.active === true &&
    String(input.listing.supplierId ?? "") === "cj_dropshipping" &&
    String(input.listing.sellerId ?? "") === input.requestedMerchantId &&
    String(input.listing.sellerProductId ?? "") === input.requestedProductId &&
    Number(input.listing.sellPriceMinor) === input.expectedPriceMinor
  );
}

/** Exact, allowlisted wire serializer shared by the authenticated endpoint. */
export function resolvedMerchantWhatsAppCatalogProductResponse(input: {
  productId: string;
  retailerId: string;
  projection: MerchantCatalogProjection;
  supplier: ResolvedNativeCatalogSupplierMetadata;
}): ResolvedMerchantWhatsAppCatalogProductResponse {
  return {
    outcome: "found",
    product: {
      id: input.productId,
      retailerId: input.retailerId,
      name: input.projection.title,
      description: input.projection.description,
      imageUrl: input.projection.imageUrl,
      price: input.projection.priceMinor / 100,
      priceMinor: input.projection.priceMinor,
      currency: input.projection.currency,
      availability: input.projection.availability,
      ...input.supplier,
    },
  };
}

export function catalogMappingUnavailableReason(input: {
  exists: boolean;
  status: unknown;
  requestedMerchantId: string;
  mappingMerchantId: string;
  requestedRetailerId: string;
  mappingRetailerId: string;
}): "not_found" | "merchant_mismatch" | undefined {
  if (
    !input.exists ||
    input.status !== "active" ||
    input.mappingRetailerId !== input.requestedRetailerId
  ) {
    return "not_found";
  }
  if (input.mappingMerchantId !== input.requestedMerchantId) {
    return "merchant_mismatch";
  }
  return undefined;
}

type ClaimResult =
  | { action: "send"; claimToken: string; attempt: number }
  | {
      action:
        | "duplicate"
        | "idempotency_conflict"
        | "in_progress"
        | "needs_review"
        | "retry_later"
        | "failed";
      wamid?: string;
      format?: WhatsAppCatalogDeliveryFormat;
      retryAfterMs?: number;
    };

function merchantId(value: unknown): string {
  const normalized = String(value ?? "").trim();
  return /^[A-Za-z0-9_-]{1,200}$/.test(normalized) ? normalized : "";
}

function retailerId(value: unknown): string {
  const normalized = String(value ?? "").trim();
  return /^spz_[a-f0-9]{32}$/.test(normalized) ? normalized : "";
}

function catalogVersion(value: unknown): string {
  const normalized = String(value ?? "").trim();
  return !normalized || /^[a-f0-9]{64}$/.test(normalized) ? normalized : "";
}

function safeIdempotencyKey(value: unknown): string {
  const normalized = String(value ?? "").trim();
  return /^[A-Za-z0-9:_-]{8,240}$/.test(normalized) ? normalized : "";
}

function pageNumber(value: unknown): number {
  const page = Number(value ?? 0);
  return Number.isSafeInteger(page) && page >= 0 && page <= 1_000 ? page : -1;
}

export function nativeCatalogSessionGate(input: {
  page: number;
  catalogVersion: string;
}): "catalog_version_required" | "completeness_required" | undefined {
  if (input.page > 0 && !input.catalogVersion) {
    return "catalog_version_required";
  }
  if (input.page === 0 && !input.catalogVersion) {
    return "completeness_required";
  }
  return undefined;
}

async function activeMerchantMappings(merchant: string): Promise<Mapping[]> {
  const documents = await collectAllNativeCatalogMappingPages(
    async (cursor, limit) => {
      let query = db
        .collection(WHATSAPP_CATALOG_MAPPINGS)
        .where("merchantId", "==", merchant)
        .orderBy(FieldPath.documentId())
        .limit(limit);
      if (cursor) query = query.startAfter(cursor);
      return (await query.get()).docs;
    },
  );
  return documents
    .filter((doc) => doc.data().status === "active")
    .map((doc) => ({
      merchantId: String(doc.data().merchantId ?? "").trim(),
      productId: String(doc.data().productId ?? "").trim(),
      retailerId: String(doc.data().retailerId ?? doc.id).trim(),
      lastAppliedRevision: String(doc.data().lastAppliedRevision ?? "").trim(),
      popularityScore: Number(doc.data().popularityScore ?? 0),
      updatedAtMs: Number(doc.data().updatedAtMs ?? 0),
    }))
    .filter(
      (item) =>
        item.merchantId === merchant &&
        /^[A-Za-z0-9_-]{1,500}$/.test(item.productId) &&
        /^spz_[a-f0-9]{32}$/.test(item.retailerId) &&
        /^[a-f0-9]{64}$/.test(item.lastAppliedRevision),
    )
    .sort(
      (a, b) =>
        b.popularityScore - a.popularityScore ||
        b.updatedAtMs - a.updatedAtMs ||
        a.retailerId.localeCompare(b.retailerId),
    );
}

export function mappingMatchesCurrentProjection(input: {
  requestedMerchantId: string;
  mappingMerchantId: string;
  productId: string;
  retailerId: string;
  lastAppliedRevision: string;
  product: Record<string, unknown> | undefined;
  merchant: Record<string, unknown>;
}): boolean {
  if (input.mappingMerchantId !== input.requestedMerchantId) return false;
  const decision = buildMerchantCatalogDecision({
    merchantId: input.requestedMerchantId,
    productId: input.productId,
    product: input.product,
    merchant: input.merchant,
  });
  return (
    decision.action === "upsert" &&
    decision.retailerId === input.retailerId &&
    decision.revision === input.lastAppliedRevision
  );
}

export function merchantAvailableForNativeCatalog(input: {
  exists: boolean;
  isPaused: unknown;
}): boolean {
  return input.exists && input.isPaused !== true;
}

/**
 * Rebuild the exact merchant-owned projection at send time. Requiring its
 * revision to match Meta's applied revision prevents stale prices, pictures,
 * visibility, and ownership from reaching the customer.
 */
async function customerVisibleMappings(
  merchant: string,
  mappings: readonly Mapping[],
): Promise<Mapping[]> {
  const refs = mappings.map((item) =>
    db.doc(`users/${merchant}/products/${item.productId}`),
  );
  if (!refs.length) return [];
  const [merchantDocument, products, supplierAccess] = await Promise.all([
    db.doc(`users/${merchant}`).get(),
    collectNativeCatalogBatchReads(refs, (batch) => db.getAll(...batch)),
    merchantBotFeatureDecision(merchant, "supplierOrders"),
  ]);
  const merchantData = merchantDocument.exists
    ? (merchantDocument.data() ?? {})
    : {};
  if (
    !merchantAvailableForNativeCatalog({
      exists: merchantDocument.exists,
      isPaused: merchantData.isPaused,
    })
  ) {
    return [];
  }
  return mappings.filter((item, index) => {
    const product = products[index];
    if (
      !nativeCatalogProductAllowedByMerchantFeature(
        product.data(),
        supplierAccess.enabled,
      )
    ) {
      return false;
    }
    return mappingMatchesCurrentProjection({
      requestedMerchantId: merchant,
      mappingMerchantId: item.merchantId,
      productId: item.productId,
      retailerId: item.retailerId,
      lastAppliedRevision: item.lastAppliedRevision,
      product: product.exists ? (product.data() ?? {}) : undefined,
      merchant: merchantData,
    });
  });
}

async function acquireDelivery(input: {
  deliveryId: string;
  recipientId: string;
  fingerprint: string;
  merchantId: string;
  format: WhatsAppCatalogDeliveryFormat;
  page: number;
  pageCount: number;
  catalogVersion: string;
  itemCount: number;
  cooldownMs: number;
  maxAttempts: number;
}): Promise<ClaimResult> {
  const deliveryRef = db.doc(
    `${WHATSAPP_PRODUCT_LIST_DELIVERIES}/${input.deliveryId}`,
  );
  const recipientRef = db.doc(
    `${WHATSAPP_PRODUCT_LIST_RECIPIENT_STATE}/${input.recipientId}`,
  );
  const nowMs = Date.now();
  return db.runTransaction(async (tx) => {
    const [delivery, recipient] = await Promise.all([
      tx.get(deliveryRef),
      tx.get(recipientRef),
    ]);
    const decision = decideNativeProductListClaim({
      existing: delivery.exists
        ? (delivery.data() as NativeProductListDeliveryRecord)
        : undefined,
      fingerprint: input.fingerprint,
      nowMs,
      recipientNextAllowedAtMs: Number(recipient.data()?.nextAllowedAtMs ?? 0),
      maxAttempts: input.maxAttempts,
    });
    if (decision.action !== "send") {
      if (
        decision.action === "needs_review" &&
        delivery.data()?.status === "sending" &&
        Number(delivery.data()?.leaseUntilMs ?? 0) <= nowMs
      ) {
        tx.set(
          deliveryRef,
          {
            status: "needs_review",
            leaseUntilMs: 0,
            claimToken: null,
            lastErrorCode: "DELIVERY_LEASE_EXPIRED_OUTCOME_UNKNOWN",
            updatedAt: FieldValue.serverTimestamp(),
            updatedAtMs: nowMs,
          },
          { merge: true },
        );
      }
      return decision.action === "duplicate"
        ? {
            ...decision,
            format: delivery.data()?.format as
              | WhatsAppCatalogDeliveryFormat
              | undefined,
          }
        : decision;
    }
    const claimToken = randomBytes(16).toString("hex");
    tx.set(
      deliveryRef,
      {
        fingerprint: input.fingerprint,
        merchantId: input.merchantId,
        format: input.format,
        page: input.page,
        pageCount: input.pageCount,
        catalogVersion: input.catalogVersion,
        itemCount: input.itemCount,
        recipientHash: input.recipientId,
        status: "sending",
        attempts: decision.attempt,
        claimToken,
        leaseUntilMs: nowMs + DELIVERY_LEASE_MS,
        nextAttemptAtMs: 0,
        updatedAt: FieldValue.serverTimestamp(),
        updatedAtMs: nowMs,
        ...(!delivery.exists
          ? { createdAt: FieldValue.serverTimestamp() }
          : {}),
      },
      { merge: true },
    );
    tx.set(
      recipientRef,
      {
        nextAllowedAtMs: nowMs + input.cooldownMs,
        updatedAt: FieldValue.serverTimestamp(),
        updatedAtMs: nowMs,
      },
      { merge: true },
    );
    return { action: "send", claimToken, attempt: decision.attempt };
  });
}

async function finishDelivery(input: {
  deliveryId: string;
  claimToken: string;
  status: "sent" | "retry_wait" | "needs_review" | "failed";
  wamid?: string;
  format?: WhatsAppCatalogDeliveryFormat;
  errorCode?: string;
  nextAttemptAtMs?: number;
  recipientId?: string;
  recipientPauseUntilMs?: number;
  recipientPauseReason?: string;
}): Promise<void> {
  const ref = db.doc(`${WHATSAPP_PRODUCT_LIST_DELIVERIES}/${input.deliveryId}`);
  await db.runTransaction(async (tx) => {
    const current = await tx.get(ref);
    if (current.data()?.claimToken !== input.claimToken) return;
    tx.set(
      ref,
      {
        status: input.status,
        wamid: input.wamid ?? null,
        ...(input.format ? { format: input.format } : {}),
        lastErrorCode: input.errorCode?.slice(0, 100) ?? null,
        nextAttemptAtMs: input.nextAttemptAtMs ?? 0,
        claimToken: null,
        leaseUntilMs: 0,
        updatedAt: FieldValue.serverTimestamp(),
        updatedAtMs: Date.now(),
      },
      { merge: true },
    );
    if (
      input.recipientId &&
      Number(input.recipientPauseUntilMs ?? 0) > Date.now()
    ) {
      tx.set(
        db.doc(`${WHATSAPP_PRODUCT_LIST_RECIPIENT_STATE}/${input.recipientId}`),
        {
          nextAllowedAtMs: input.recipientPauseUntilMs,
          pauseReason: input.recipientPauseReason?.slice(0, 100) ?? null,
          updatedAt: FieldValue.serverTimestamp(),
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
    }
  });
}

function fallback(
  res: functions.Response,
  reason: string,
  detail: Record<string, unknown> = {},
  statusCode = 200,
): void {
  res.status(statusCode).json({
    outcome: "fallback",
    reason,
    ...(statusCode >= 400 ? { code: reason.toUpperCase() } : {}),
    ...detail,
  });
}

export type NativeCatalogPreDispatchResult<T> =
  | { outcome: "ready"; value: T }
  | { outcome: "fallback"; reason: "catalog_temporarily_unavailable" };

/**
 * Delimits the phase in which no provider request has been attempted. A
 * storage/configuration failure here is safe to expose as the bot's one
 * compact fallback. Provider and post-dispatch ledger writes deliberately sit
 * outside this boundary because their delivery outcome may be ambiguous.
 */
export async function runNativeCatalogPreDispatch<T>(
  operation: () => Promise<T>,
): Promise<NativeCatalogPreDispatchResult<T>> {
  try {
    return { outcome: "ready", value: await operation() };
  } catch (error) {
    console.warn("[whatsapp-native-catalog] pre-dispatch blocked", {
      code: error instanceof Error ? error.name : "UNKNOWN",
    });
    return {
      outcome: "fallback",
      reason: "catalog_temporarily_unavailable",
    };
  }
}

/**
 * Generic bot-only catalogue delivery. Products are selected and revalidated
 * here; the caller cannot inject retailer IDs or stream pages automatically.
 */
export async function sendMerchantWhatsAppCatalogBotHandler(
  req: functions.https.Request,
  res: functions.Response,
): Promise<void> {
  if (!requireBotRequest(req, res)) return;
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const requestedMerchantId = merchantId(req.body?.merchantId);
  const idempotencyKey = safeIdempotencyKey(req.body?.idempotencyKey);
  const page = pageNumber(req.body?.page);
  const requestedCatalogVersion = catalogVersion(req.body?.catalogVersion);
  if (
    !requestedMerchantId ||
    !idempotencyKey ||
    page < 0 ||
    (req.body?.catalogVersion && !requestedCatalogVersion)
  ) {
    fallback(res, "invalid_request", {}, 400);
    return;
  }

  let recipient: string;
  try {
    recipient = normalizeWhatsAppRecipient(req.body?.recipientPhone);
  } catch (_) {
    fallback(res, "invalid_recipient", {}, 400);
    return;
  }

  let config;
  try {
    config = whatsappProductListRuntimeConfig();
  } catch (error) {
    console.warn("[whatsapp-native-catalog] configuration blocked", {
      code: error instanceof Error ? error.message : "CONFIG_INVALID",
    });
    fallback(res, "configuration_blocked");
    return;
  }
  const accessReason = whatsappNativeCatalogAccessReason(
    config,
    requestedMerchantId,
    recipient,
  );
  if (accessReason) {
    fallback(res, accessReason);
    return;
  }
  const senderPhoneNumberId = String(
    req.body?.senderPhoneNumberId ?? "",
  ).trim();
  if (senderPhoneNumberId !== config.phoneNumberId) {
    fallback(res, "sender_mismatch");
    return;
  }
  const sessionGate = nativeCatalogSessionGate({
    page,
    catalogVersion: requestedCatalogVersion,
  });
  if (sessionGate === "catalog_version_required") {
    fallback(res, "catalog_version_required");
    return;
  }
  const preDispatch = await runNativeCatalogPreDispatch(async () => {
    if (
      sessionGate === "completeness_required" &&
      !(await reconcileMerchantWhatsAppCatalogCompleteness(requestedMerchantId))
        .complete
    ) {
      return {
        action: "fallback" as const,
        reason: "catalog_not_reconciled",
        detail: {},
      };
    }

    const visible = await customerVisibleMappings(
      requestedMerchantId,
      await activeMerchantMappings(requestedMerchantId),
    );
    const pageDecision = selectNativeCatalogPage({
      items: visible,
      page,
      ...(requestedCatalogVersion
        ? { catalogVersion: requestedCatalogVersion }
        : {}),
    });
    if (pageDecision.outcome === "fallback") {
      return {
        action: "fallback" as const,
        reason: pageDecision.reason,
        detail: {
          page: pageDecision.page,
          pageCount: pageDecision.pageCount,
          catalogVersion: pageDecision.catalogVersion,
          availableProducts: pageDecision.availableProducts,
        },
      };
    }

    const retailerIds = pageDecision.items.map((item) => item.retailerId);
    const recipientId = currentControlledWhatsAppRecipientDigest(recipient);
    const fingerprint = productListDeliveryFingerprint({
      merchantId: requestedMerchantId,
      recipientHash: recipientId,
      senderPhoneNumberId,
      catalogId: config.catalogId,
      format: pageDecision.format,
      page,
      pageCount: pageDecision.pageCount,
      catalogVersion: pageDecision.catalogVersion,
      productRetailerIds: retailerIds,
    });
    const deliveryId = opaqueProductListId(
      `${requestedMerchantId}:${idempotencyKey}`,
    );
    const metadata = {
      format: pageDecision.format,
      page,
      pageCount: pageDecision.pageCount,
      catalogVersion: pageDecision.catalogVersion,
      itemCount: retailerIds.length,
    };
    const primaryPayload =
      pageDecision.format === "single_product"
        ? buildMetaWhatsAppSingleProductPayload({
            recipient,
            catalogId: config.catalogId,
            productRetailerId: retailerIds[0],
          })
        : buildMetaWhatsAppProductCarouselPayload({
            recipient,
            catalogId: config.catalogId,
            productRetailerIds: retailerIds,
            page,
            pageCount: pageDecision.pageCount,
          });
    const productListFallbackPayload =
      pageDecision.format === "product_carousel"
        ? buildMetaWhatsAppProductListPayload({
            recipient,
            catalogId: config.catalogId,
            productRetailerIds: retailerIds,
          })
        : undefined;
    const claim = await acquireDelivery({
      deliveryId,
      recipientId,
      fingerprint,
      merchantId: requestedMerchantId,
      format: pageDecision.format,
      page,
      pageCount: pageDecision.pageCount,
      catalogVersion: pageDecision.catalogVersion,
      itemCount: retailerIds.length,
      cooldownMs: config.recipientCooldownMs,
      maxAttempts: config.maxAttempts,
    });
    return {
      action: "prepared" as const,
      claim,
      deliveryId,
      metadata,
      primaryPayload,
      productListFallbackPayload,
      recipientId,
    };
  });
  if (preDispatch.outcome === "fallback") {
    fallback(res, preDispatch.reason);
    return;
  }
  if (preDispatch.value.action === "fallback") {
    fallback(res, preDispatch.value.reason, preDispatch.value.detail);
    return;
  }

  const {
    claim,
    deliveryId,
    metadata,
    primaryPayload,
    productListFallbackPayload,
    recipientId,
  } = preDispatch.value;
  if (claim.action !== "send") {
    res.status(200).json({
      outcome: claim.action,
      ...metadata,
      ...(claim.format ? { format: claim.format } : {}),
      ...(claim.wamid ? { wamid: claim.wamid } : {}),
      ...(claim.retryAfterMs ? { retryAfterMs: claim.retryAfterMs } : {}),
    });
    return;
  }
  try {
    const result = await sendMetaWhatsAppCatalogWithFallback({
      config,
      primaryPayload,
      ...(productListFallbackPayload ? { productListFallbackPayload } : {}),
    });
    const actualMetadata = { ...metadata, format: result.format };
    await finishDelivery({
      deliveryId,
      claimToken: claim.claimToken,
      status: "sent",
      wamid: result.wamid,
      format: result.format,
    });
    console.info("[whatsapp-native-catalog] sent", {
      merchantId: requestedMerchantId,
      deliveryId,
      ...actualMetadata,
      providerRequests: result.providerRequests,
      wamid: result.wamid,
    });
    res.status(200).json({
      outcome: "sent",
      ...actualMetadata,
      wamid: result.wamid,
    });
  } catch (error) {
    const provider =
      error instanceof MetaWhatsAppProductListError
        ? error
        : new MetaWhatsAppProductListError(
            "META_WHATSAPP_MESSAGE_OUTCOME_UNKNOWN",
            false,
            true,
          );
    const retryDelay = Math.max(
      provider.retryAfterMs,
      productListRetryDelayMs(claim.attempt),
    );
    const isPairLimit = provider.providerCode.includes("_131056_");
    const effectiveRetryDelay = isPairLimit
      ? Math.max(config.pairLimitPauseMs, retryDelay)
      : retryDelay;
    const recipientPauseUntilMs = isPairLimit
      ? Date.now() + effectiveRetryDelay
      : 0;
    const status = provider.ambiguous
      ? "needs_review"
      : provider.retryable && claim.attempt < config.maxAttempts
        ? "retry_wait"
        : "failed";
    await finishDelivery({
      deliveryId,
      claimToken: claim.claimToken,
      status,
      errorCode: provider.providerCode,
      nextAttemptAtMs:
        status === "retry_wait" ? Date.now() + effectiveRetryDelay : 0,
      ...(isPairLimit
        ? {
            recipientId,
            recipientPauseUntilMs,
            recipientPauseReason: provider.providerCode,
          }
        : {}),
    });
    console.warn("[whatsapp-native-catalog] send blocked", {
      merchantId: requestedMerchantId,
      deliveryId,
      ...metadata,
      status,
      errorCode: provider.providerCode,
    });
    res.status(200).json({
      outcome: status === "retry_wait" ? "retry_later" : status,
      ...metadata,
      reason: provider.providerCode,
      ...(status === "retry_wait" ? { retryAfterMs: effectiveRetryDelay } : {}),
    });
  }
}

export const sendMerchantWhatsAppCatalogBotHttp = functions
  .runWith({
    secrets: [
      "PASELLA_BOT_TOKEN",
      "META_WHATSAPP_ACCESS_TOKEN",
      "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
    ],
    timeoutSeconds: 30,
    memory: "256MB",
    maxInstances: 1,
  })
  .https.onRequest(sendMerchantWhatsAppCatalogBotHandler);

/**
 * Revalidates a selected Meta retailer ID before Botpress shows detail. The
 * existing cart endpoint performs the final product/price check again when the
 * customer confirms quantity.
 */
export async function resolveMerchantWhatsAppCatalogProductBotHandler(
  req: functions.https.Request,
  res: functions.Response,
): Promise<void> {
  if (!requireBotRequest(req, res)) return;
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const requestedMerchantId = merchantId(req.body?.merchantId);
  const requestedRetailerId = retailerId(req.body?.retailerId);
  let recipient: string;
  try {
    recipient = normalizeWhatsAppRecipient(req.body?.recipientPhone);
  } catch (_) {
    res.status(400).json({
      outcome: "unavailable",
      reason: "invalid_recipient",
      code: "INVALID_RECIPIENT",
    });
    return;
  }
  if (!requestedMerchantId || !requestedRetailerId) {
    res.status(400).json({
      outcome: "unavailable",
      reason: "invalid_request",
      code: "INVALID_REQUEST",
    });
    return;
  }
  let config;
  try {
    config = whatsappProductListRuntimeConfig();
  } catch (_) {
    res.status(200).json({
      outcome: "unavailable",
      reason: "configuration_blocked",
    });
    return;
  }
  const accessReason = whatsappNativeCatalogAccessReason(
    config,
    requestedMerchantId,
    recipient,
  );
  if (accessReason) {
    res.status(200).json({ outcome: "unavailable", reason: accessReason });
    return;
  }
  const requestedCatalogId = String(req.body?.catalogId ?? "").trim();
  if (requestedCatalogId !== config.catalogId) {
    res
      .status(200)
      .json({ outcome: "unavailable", reason: "catalog_mismatch" });
    return;
  }
  const senderPhoneNumberId = String(
    req.body?.senderPhoneNumberId ?? "",
  ).trim();
  if (senderPhoneNumberId !== config.phoneNumberId) {
    res.status(200).json({
      outcome: "unavailable",
      reason: "sender_mismatch",
    });
    return;
  }
  const mappingDocument = await db
    .doc(`${WHATSAPP_CATALOG_MAPPINGS}/${requestedRetailerId}`)
    .get();
  const mappingData = mappingDocument.data() ?? {};
  const mapping: Mapping = {
    merchantId: String(mappingData.merchantId ?? "").trim(),
    productId: String(mappingData.productId ?? "").trim(),
    retailerId: String(mappingData.retailerId ?? mappingDocument.id).trim(),
    lastAppliedRevision: String(mappingData.lastAppliedRevision ?? "").trim(),
    popularityScore: Number(mappingData.popularityScore ?? 0),
    updatedAtMs: Number(mappingData.updatedAtMs ?? 0),
  };
  const mappingUnavailableReason = catalogMappingUnavailableReason({
    exists: mappingDocument.exists,
    status: mappingData.status,
    requestedMerchantId,
    mappingMerchantId: mapping.merchantId,
    requestedRetailerId,
    mappingRetailerId: mapping.retailerId,
  });
  if (mappingUnavailableReason) {
    res.status(200).json({
      outcome: "unavailable",
      reason: mappingUnavailableReason,
    });
    return;
  }

  const [merchantDocument, productDocument] = await Promise.all([
    db.doc(`users/${requestedMerchantId}`).get(),
    db.doc(`users/${requestedMerchantId}/products/${mapping.productId}`).get(),
  ]);
  const merchantData = merchantDocument.data() ?? {};
  const productData = productDocument.exists
    ? (productDocument.data() ?? {})
    : undefined;
  if (
    !merchantAvailableForNativeCatalog({
      exists: merchantDocument.exists,
      isPaused: merchantData.isPaused,
    })
  ) {
    res.status(200).json({
      outcome: "unavailable",
      reason: "merchant_unavailable",
    });
    return;
  }
  if (
    !mappingMatchesCurrentProjection({
      requestedMerchantId,
      mappingMerchantId: mapping.merchantId,
      productId: mapping.productId,
      retailerId: mapping.retailerId,
      lastAppliedRevision: mapping.lastAppliedRevision,
      product: productData,
      merchant: merchantData,
    })
  ) {
    res.status(200).json({ outcome: "unavailable", reason: "stale_mapping" });
    return;
  }
  const decision = buildMerchantCatalogDecision({
    merchantId: requestedMerchantId,
    productId: mapping.productId,
    product: productData,
    merchant: merchantData,
  });
  if (decision.action !== "upsert" || !decision.projection || !productData) {
    res.status(200).json({ outcome: "unavailable", reason: "not_visible" });
    return;
  }

  const productKind = nativeCatalogProductKind(productData);
  let supplier: ResolvedNativeCatalogSupplierMetadata;
  if (productKind.kind === "invalid_supplier") {
    res.status(200).json({
      outcome: "unavailable",
      reason: "supplier_listing_unavailable",
    });
    return;
  } else if (productKind.kind === "supplier") {
    if (
      !(await merchantBotFeatureDecision(requestedMerchantId, "supplierOrders"))
        .enabled
    ) {
      res.status(200).json({
        outcome: "unavailable",
        reason: "merchant_update_required",
      });
      return;
    }
    const listingDocument = await db
      .doc(`commerceListings/${productKind.commerceListingId}`)
      .get();
    if (
      !nativeCatalogSupplierListingMatches({
        exists: listingDocument.exists,
        requestedMerchantId,
        requestedProductId: mapping.productId,
        expectedPriceMinor: decision.projection.priceMinor,
        listing: listingDocument.data() ?? {},
      })
    ) {
      res.status(200).json({
        outcome: "unavailable",
        reason: "supplier_listing_unavailable",
      });
      return;
    }
    supplier = {
      isDropshipListing: true,
      commerceListingId: productKind.commerceListingId,
    };
  } else {
    supplier = { isDropshipListing: false };
  }

  res.status(200).json(
    resolvedMerchantWhatsAppCatalogProductResponse({
      productId: mapping.productId,
      retailerId: mapping.retailerId,
      projection: decision.projection,
      supplier,
    }),
  );
}

export const resolveMerchantWhatsAppCatalogProductBotHttp = functions
  .runWith({
    secrets: ["PASELLA_BOT_TOKEN", "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY"],
    timeoutSeconds: 15,
    memory: "256MB",
    maxInstances: 2,
  })
  .https.onRequest(resolveMerchantWhatsAppCatalogProductBotHandler);
