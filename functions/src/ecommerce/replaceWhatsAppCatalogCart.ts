import { createHash } from "crypto";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { requireBotRequest } from "../security/requestAuth";
import {
  MerchantCatalogProjection,
  buildMerchantCatalogDecision,
} from "../whatsapp/catalogProjection";
import { WHATSAPP_CATALOG_MAPPINGS } from "../whatsapp/catalogQueue";
import {
  currentControlledWhatsAppRecipientDigest,
  normalizeWhatsAppRecipient,
  whatsappNativeCatalogAccessReason,
  whatsappProductListRuntimeConfig,
} from "../whatsapp/nativeProductList";

export const WHATSAPP_CATALOG_CART_MAX_ITEMS = 10;
export const WHATSAPP_CATALOG_CART_MAX_QUANTITY = 999;
export const WHATSAPP_CATALOG_CART_STATES = "whatsappCatalogCartStates";
const WHATSAPP_CATALOG_CART_MAX_EXISTING_ITEMS = 100;
const IDEMPOTENCY_RETENTION_MS = 30 * 24 * 60 * 60 * 1_000;

export type WhatsAppCatalogCartRequestItem = {
  retailerId: string;
  quantity: number;
  expectedPriceMinor: number;
};

export type ParsedCartRequest = {
  merchantId: string;
  customerId: string;
  recipient: string;
  senderPhoneNumberId: string;
  catalogId: string;
  idempotencyKey: string;
  items: WhatsAppCatalogCartRequestItem[];
};

export type CatalogCartMappingInput = {
  exists: boolean;
  status: unknown;
  merchantId: unknown;
  productId: unknown;
  retailerId: unknown;
  lastAppliedRevision: unknown;
};

export type ResolvedCatalogCartItem = WhatsAppCatalogCartRequestItem & {
  productId: string;
  lastAppliedRevision: string;
};

export type CatalogCartPlanItem = ResolvedCatalogCartItem & {
  catalogRevision: string;
  priceMinor: number;
  projection: MerchantCatalogProjection;
};

export type CatalogCartPlan = {
  currency: "ZAR";
  lineCount: number;
  itemsCount: number;
  total: number;
  totalMinor: number;
  items: CatalogCartPlanItem[];
};

export type StoredNativeCatalogCartLine = {
  productId: string;
  quantity: unknown;
  source: unknown;
  retailerId: unknown;
  catalogRevision: unknown;
  catalogPriceMinor: unknown;
};

export type StoredNativeCatalogCartSummary = {
  source?: unknown;
  catalogId?: unknown;
  nativeCartFingerprint?: unknown;
  currency?: unknown;
  lineCount?: unknown;
  itemsCount?: unknown;
  total?: unknown;
  totalMinor?: unknown;
};

export type StoredNativeCatalogCartState = {
  exists: boolean;
  merchantId: unknown;
  customerId: unknown;
  catalogId: unknown;
  fingerprint: unknown;
  schemaVersion: unknown;
};

export type CatalogCartFailureReason =
  | "idempotency_conflict"
  | "customer_recipient_mismatch"
  | "cart_changed"
  | "merchant_mismatch"
  | "stale_mapping"
  | "price_changed"
  | "product_unavailable"
  | "quantity_unavailable"
  | "cart_too_large";

export class WhatsAppCatalogCartValidationError extends Error {
  constructor(
    public readonly reason: CatalogCartFailureReason,
    public readonly failedItemIndex?: number,
  ) {
    super(reason);
    this.name = "WhatsAppCatalogCartValidationError";
  }
}

/**
 * Binds the controlled WhatsApp recipient to the merchant-owned customer
 * record that owns the cart. Missing and mismatched records intentionally
 * share one result so this bot-only endpoint cannot be used for enumeration.
 */
export function customerMatchesWhatsAppRecipient(input: {
  customerExists: boolean;
  customerNumber: unknown;
  recipient: string;
}): boolean {
  if (!input.customerExists) return false;
  try {
    return (
      normalizeWhatsAppRecipient(input.customerNumber) ===
      normalizeWhatsAppRecipient(input.recipient)
    );
  } catch (_) {
    return false;
  }
}

function safeMerchantId(value: unknown): string {
  const normalized = String(value ?? "").trim();
  return /^[A-Za-z0-9_-]{1,200}$/.test(normalized) ? normalized : "";
}

function safeCustomerId(value: unknown): string {
  const normalized = String(value ?? "").trim();
  return /^[A-Za-z0-9_.:@+-]{1,500}$/.test(normalized) ? normalized : "";
}

function safeIdempotencyKey(value: unknown): string {
  const normalized = String(value ?? "").trim();
  return /^[A-Za-z0-9:_-]{8,240}$/.test(normalized) ? normalized : "";
}

export function parseWhatsAppCatalogCartRequest(
  body: unknown,
): ParsedCartRequest | undefined {
  const value =
    body && typeof body === "object"
      ? (body as Record<string, unknown>)
      : ({} as Record<string, unknown>);
  const merchantId = safeMerchantId(value.merchantId);
  const customerId = safeCustomerId(value.customerId);
  const senderPhoneNumberId = String(value.senderPhoneNumberId ?? "").trim();
  const catalogId = String(value.catalogId ?? "").trim();
  const idempotencyKey = safeIdempotencyKey(value.idempotencyKey);
  let recipient: string;
  try {
    recipient = normalizeWhatsAppRecipient(value.recipientPhone);
  } catch (_) {
    return undefined;
  }
  if (
    !merchantId ||
    !customerId ||
    !/^\d{5,30}$/.test(senderPhoneNumberId) ||
    !/^\d{5,30}$/.test(catalogId) ||
    !idempotencyKey ||
    !Array.isArray(value.items) ||
    value.items.length < 1 ||
    value.items.length > WHATSAPP_CATALOG_CART_MAX_ITEMS
  ) {
    return undefined;
  }
  const items: WhatsAppCatalogCartRequestItem[] = [];
  for (const raw of value.items) {
    if (!raw || typeof raw !== "object") return undefined;
    const item = raw as Record<string, unknown>;
    const retailerId = String(item.retailerId ?? "").trim();
    const quantity = item.quantity;
    const expectedPriceMinor = item.expectedPriceMinor;
    if (
      !/^spz_[a-f0-9]{32}$/.test(retailerId) ||
      typeof quantity !== "number" ||
      !Number.isSafeInteger(quantity) ||
      quantity < 1 ||
      quantity > WHATSAPP_CATALOG_CART_MAX_QUANTITY ||
      typeof expectedPriceMinor !== "number" ||
      !Number.isSafeInteger(expectedPriceMinor) ||
      expectedPriceMinor < 1 ||
      expectedPriceMinor > 100_000_000
    ) {
      return undefined;
    }
    items.push({ retailerId, quantity, expectedPriceMinor });
  }
  if (new Set(items.map((item) => item.retailerId)).size !== items.length) {
    return undefined;
  }
  return {
    merchantId,
    customerId,
    recipient,
    senderPhoneNumberId,
    catalogId,
    idempotencyKey,
    items,
  };
}

export function validateCatalogCartMappings(input: {
  merchantId: string;
  items: readonly WhatsAppCatalogCartRequestItem[];
  mappings: readonly CatalogCartMappingInput[];
}): ResolvedCatalogCartItem[] {
  if (input.items.length !== input.mappings.length) {
    throw new WhatsAppCatalogCartValidationError("stale_mapping");
  }
  return input.items.map((item, index) => {
    const mapping = input.mappings[index];
    const mappingMerchantId = String(mapping.merchantId ?? "").trim();
    const productId = String(mapping.productId ?? "").trim();
    const mappingRetailerId = String(mapping.retailerId ?? "").trim();
    const lastAppliedRevision = String(
      mapping.lastAppliedRevision ?? "",
    ).trim();
    if (
      mapping.exists &&
      mapping.status === "active" &&
      mappingMerchantId &&
      mappingMerchantId !== input.merchantId
    ) {
      throw new WhatsAppCatalogCartValidationError("merchant_mismatch", index);
    }
    if (!mapping.exists || mapping.status !== "active") {
      throw new WhatsAppCatalogCartValidationError(
        "product_unavailable",
        index,
      );
    }
    if (
      mappingMerchantId !== input.merchantId ||
      !/^[A-Za-z0-9_-]{1,500}$/.test(productId) ||
      mappingRetailerId !== item.retailerId ||
      !/^[a-f0-9]{64}$/.test(lastAppliedRevision)
    ) {
      throw new WhatsAppCatalogCartValidationError("stale_mapping", index);
    }
    return {
      ...item,
      productId,
      lastAppliedRevision,
    };
  });
}

function trackedStock(product: Record<string, unknown>): number | undefined {
  for (const raw of [product.quantity, product.stockQuantity]) {
    if (raw === undefined || raw === null || raw === "") continue;
    const stock = Number(raw);
    return Number.isFinite(stock) && stock >= 0 ? stock : 0;
  }
  return undefined;
}

/**
 * Pure all-item preflight. It returns a replacement only after the final item
 * passes, so callers cannot accidentally stage a partial cart mutation.
 */
export function planWhatsAppCatalogCartReplacement(input: {
  merchantId: string;
  merchantExists: boolean;
  merchant: Record<string, unknown>;
  items: ReadonlyArray<{
    request: ResolvedCatalogCartItem;
    product: Record<string, unknown> | undefined;
  }>;
}): CatalogCartPlan {
  if (!input.merchantExists || input.merchant.isPaused === true) {
    throw new WhatsAppCatalogCartValidationError("product_unavailable", 0);
  }
  const planned: CatalogCartPlanItem[] = input.items.map((item, index) => {
    const decision = buildMerchantCatalogDecision({
      merchantId: input.merchantId,
      productId: item.request.productId,
      product: item.product,
      merchant: input.merchant,
    });
    if (
      decision.action !== "upsert" ||
      !decision.projection ||
      decision.projection.availability !== "in stock"
    ) {
      throw new WhatsAppCatalogCartValidationError(
        "product_unavailable",
        index,
      );
    }
    if (decision.retailerId !== item.request.retailerId) {
      throw new WhatsAppCatalogCartValidationError("stale_mapping", index);
    }
    if (decision.projection.priceMinor !== item.request.expectedPriceMinor) {
      throw new WhatsAppCatalogCartValidationError("price_changed", index);
    }
    if (decision.revision !== item.request.lastAppliedRevision) {
      throw new WhatsAppCatalogCartValidationError("stale_mapping", index);
    }
    const stock = trackedStock(item.product ?? {});
    if (stock !== undefined && item.request.quantity > stock) {
      throw new WhatsAppCatalogCartValidationError(
        "quantity_unavailable",
        index,
      );
    }
    return {
      ...item.request,
      catalogRevision: decision.revision,
      priceMinor: decision.projection.priceMinor,
      projection: decision.projection,
    };
  });
  const totalMinor = planned.reduce(
    (sum, item) => sum + item.priceMinor * item.quantity,
    0,
  );
  const itemsCount = planned.reduce((sum, item) => sum + item.quantity, 0);
  if (!Number.isSafeInteger(totalMinor) || !Number.isSafeInteger(itemsCount)) {
    throw new WhatsAppCatalogCartValidationError("quantity_unavailable");
  }
  return {
    currency: "ZAR",
    lineCount: planned.length,
    itemsCount,
    total: totalMinor / 100,
    totalMinor,
    items: planned,
  };
}

export function nativeCatalogCartFingerprint(input: {
  merchantId: string;
  customerId: string;
  catalogId: string;
  items: ReadonlyArray<{
    productId: string;
    retailerId: string;
    quantity: number;
    priceMinor: number;
    catalogRevision: string;
  }>;
}): string {
  return createHash("sha256")
    .update(
      JSON.stringify({
        merchantId: input.merchantId,
        customerId: input.customerId,
        catalogId: input.catalogId,
        items: input.items
          .map((item) => ({
            productId: item.productId,
            retailerId: item.retailerId,
            quantity: item.quantity,
            priceMinor: item.priceMinor,
            catalogRevision: item.catalogRevision,
          }))
          .sort(
            (a, b) =>
              a.productId.localeCompare(b.productId) ||
              a.retailerId.localeCompare(b.retailerId),
          ),
      }),
    )
    .digest("hex");
}

/**
 * Rebuilds a stored native cart from current merchant products and active Meta
 * mappings. Checkout uses this so delivery, cart, and sale prices share the
 * same canonical catalogue projection semantics.
 */
export function planStoredNativeCatalogCart(input: {
  merchantId: string;
  customerId: string;
  merchantExists: boolean;
  merchant: Record<string, unknown>;
  summary: StoredNativeCatalogCartSummary;
  state: StoredNativeCatalogCartState;
  lines: readonly StoredNativeCatalogCartLine[];
  mappings: readonly CatalogCartMappingInput[];
  products: readonly (Record<string, unknown> | undefined)[];
}): { plan: CatalogCartPlan; fingerprint: string } {
  const catalogId = String(input.summary.catalogId ?? "").trim();
  if (
    input.summary.source !== "whatsapp_native_catalog" ||
    !/^\d{5,30}$/.test(catalogId) ||
    input.lines.length < 1 ||
    input.lines.length > WHATSAPP_CATALOG_CART_MAX_ITEMS ||
    input.lines.length !== input.mappings.length ||
    input.lines.length !== input.products.length
  ) {
    throw new WhatsAppCatalogCartValidationError("cart_changed");
  }
  const requests: WhatsAppCatalogCartRequestItem[] = input.lines.map(
    (line, index) => {
      const productId = String(line.productId ?? "").trim();
      const retailerId = String(line.retailerId ?? "").trim();
      const catalogRevision = String(line.catalogRevision ?? "").trim();
      const quantity = line.quantity;
      const expectedPriceMinor = line.catalogPriceMinor;
      if (
        line.source !== "whatsapp_native_catalog" ||
        !/^[A-Za-z0-9_-]{1,500}$/.test(productId) ||
        !/^spz_[a-f0-9]{32}$/.test(retailerId) ||
        !/^[a-f0-9]{64}$/.test(catalogRevision) ||
        typeof quantity !== "number" ||
        !Number.isSafeInteger(quantity) ||
        quantity < 1 ||
        quantity > WHATSAPP_CATALOG_CART_MAX_QUANTITY ||
        typeof expectedPriceMinor !== "number" ||
        !Number.isSafeInteger(expectedPriceMinor) ||
        expectedPriceMinor < 1 ||
        expectedPriceMinor > 100_000_000
      ) {
        throw new WhatsAppCatalogCartValidationError("cart_changed", index);
      }
      return { retailerId, quantity, expectedPriceMinor };
    },
  );
  if (
    new Set(requests.map((item) => item.retailerId)).size !== requests.length
  ) {
    throw new WhatsAppCatalogCartValidationError("cart_changed");
  }
  const resolved = validateCatalogCartMappings({
    merchantId: input.merchantId,
    items: requests,
    mappings: input.mappings,
  });
  resolved.forEach((item, index) => {
    if (
      item.productId !== input.lines[index].productId ||
      item.lastAppliedRevision !== input.lines[index].catalogRevision
    ) {
      throw new WhatsAppCatalogCartValidationError("stale_mapping", index);
    }
  });
  const plan = planWhatsAppCatalogCartReplacement({
    merchantId: input.merchantId,
    merchantExists: input.merchantExists,
    merchant: input.merchant,
    items: resolved.map((request, index) => ({
      request,
      product: input.products[index],
    })),
  });
  const fingerprint = nativeCatalogCartFingerprint({
    merchantId: input.merchantId,
    customerId: input.customerId,
    catalogId,
    items: plan.items,
  });
  if (
    !input.state.exists ||
    input.state.merchantId !== input.merchantId ||
    input.state.customerId !== input.customerId ||
    input.state.catalogId !== catalogId ||
    input.state.fingerprint !== fingerprint ||
    input.state.schemaVersion !== 1 ||
    input.summary.nativeCartFingerprint !== fingerprint ||
    input.summary.currency !== plan.currency ||
    input.summary.lineCount !== plan.lineCount ||
    input.summary.itemsCount !== plan.itemsCount ||
    input.summary.totalMinor !== plan.totalMinor ||
    input.summary.total !== plan.total
  ) {
    throw new WhatsAppCatalogCartValidationError("cart_changed");
  }
  return { plan, fingerprint };
}

export function nativeCatalogCartStateDocumentId(input: {
  merchantId: string;
  customerId: string;
}): string {
  return createHash("sha256")
    .update(`${input.merchantId}\u0000${input.customerId}`)
    .digest("hex");
}

function cartResponse(plan: CatalogCartPlan, nativeCartFingerprint: string) {
  return {
    currency: plan.currency,
    lineCount: plan.lineCount,
    itemsCount: plan.itemsCount,
    total: plan.total,
    totalMinor: plan.totalMinor,
    nativeCartFingerprint,
    items: plan.items.map((item) => ({
      productId: item.productId,
      retailerId: item.retailerId,
      quantity: item.quantity,
      priceMinor: item.priceMinor,
      catalogRevision: item.catalogRevision,
    })),
  };
}

function requestFingerprint(
  request: ParsedCartRequest,
  recipientHash: string,
): string {
  return createHash("sha256")
    .update(
      JSON.stringify({
        merchantId: request.merchantId,
        customerId: request.customerId,
        recipientHash,
        senderPhoneNumberId: request.senderPhoneNumberId,
        catalogId: request.catalogId,
        // Cart-line order is not semantic. Canonicalizing it makes a duplicate
        // webhook with the same unique items idempotent even if transport
        // normalization reordered the array.
        items: [...request.items].sort((a, b) =>
          a.retailerId.localeCompare(b.retailerId),
        ),
      }),
    )
    .digest("hex");
}

function idempotencyDocumentId(request: ParsedCartRequest): string {
  return createHash("sha256")
    .update(
      `${request.merchantId}\u0000${request.customerId}\u0000${request.idempotencyKey}`,
    )
    .digest("hex");
}

export type CatalogCartIdempotencyDecision =
  | { action: "apply" }
  | { action: "duplicate"; cart: unknown }
  | { action: "idempotency_conflict" };

export function decideCatalogCartIdempotency(input: {
  exists: boolean;
  existingFingerprint?: unknown;
  existingCart?: unknown;
  fingerprint: string;
}): CatalogCartIdempotencyDecision {
  if (!input.exists) return { action: "apply" };
  if (
    input.existingFingerprint === input.fingerprint &&
    input.existingCart &&
    typeof input.existingCart === "object"
  ) {
    return { action: "duplicate", cart: input.existingCart };
  }
  return { action: "idempotency_conflict" };
}

export type WhatsAppCatalogCartReplacementResult =
  | { outcome: "duplicate"; cart: unknown }
  | {
      outcome: "replaced";
      cart: ReturnType<typeof cartResponse>;
    };

/**
 * Executes the server-side cart replacement after HTTP authentication and
 * runtime access gates have succeeded. Keeping the full read/validate/write
 * sequence in one exported service lets emulator tests exercise the exact
 * Firestore transaction without weakening the HTTP authentication boundary.
 */
export async function replaceWhatsAppCatalogCartAtomically(input: {
  request: ParsedCartRequest;
  recipientHash: string;
}): Promise<WhatsAppCatalogCartReplacementResult> {
  const { request, recipientHash } = input;
  const fingerprint = requestFingerprint(request, recipientHash);
  const cartRef = db.doc(
    `users/${request.merchantId}/carts/${request.customerId}`,
  );
  const customerRef = db.doc(
    `users/${request.merchantId}/customers/${request.customerId}`,
  );
  const idempotencyRef = db.doc(
    `whatsappCatalogCartReplacements/${idempotencyDocumentId(request)}`,
  );
  const stateRef = db.doc(
    `${WHATSAPP_CATALOG_CART_STATES}/${nativeCatalogCartStateDocumentId(request)}`,
  );
  const mappingRefs = request.items.map((item) =>
    db.doc(`${WHATSAPP_CATALOG_MAPPINGS}/${item.retailerId}`),
  );

  return db.runTransaction(async (tx) => {
    const idempotency = await tx.get(idempotencyRef);
    const idempotencyDecision = decideCatalogCartIdempotency({
      exists: idempotency.exists,
      existingFingerprint: idempotency.get("fingerprint"),
      existingCart: idempotency.get("cart"),
      fingerprint,
    });
    if (idempotencyDecision.action === "duplicate") {
      return {
        outcome: "duplicate" as const,
        cart: idempotencyDecision.cart,
      };
    }
    if (idempotencyDecision.action === "idempotency_conflict") {
      throw new WhatsAppCatalogCartValidationError("idempotency_conflict");
    }

    const [merchantSnapshot, customerSnapshot, mappingSnapshots] =
      await Promise.all([
        tx.get(db.doc(`users/${request.merchantId}`)),
        tx.get(customerRef),
        Promise.all(mappingRefs.map((ref) => tx.get(ref))),
      ]);
    if (
      !customerMatchesWhatsAppRecipient({
        customerExists: customerSnapshot.exists,
        customerNumber: customerSnapshot.get("number"),
        recipient: request.recipient,
      })
    ) {
      throw new WhatsAppCatalogCartValidationError(
        "customer_recipient_mismatch",
      );
    }
    const resolvedItems = validateCatalogCartMappings({
      merchantId: request.merchantId,
      items: request.items,
      mappings: mappingSnapshots.map((snapshot) => ({
        exists: snapshot.exists,
        status: snapshot.get("status"),
        merchantId: snapshot.get("merchantId"),
        productId: snapshot.get("productId"),
        retailerId: snapshot.get("retailerId") ?? snapshot.id,
        lastAppliedRevision: snapshot.get("lastAppliedRevision"),
      })),
    });
    const [productSnapshots, existingCart, existingCartItems] =
      await Promise.all([
        Promise.all(
          resolvedItems.map((item) =>
            tx.get(
              db.doc(`users/${request.merchantId}/products/${item.productId}`),
            ),
          ),
        ),
        tx.get(cartRef),
        tx.get(
          cartRef
            .collection("items")
            .limit(WHATSAPP_CATALOG_CART_MAX_EXISTING_ITEMS + 1),
        ),
      ]);
    const existingLock = existingCart.get("lock") as
      | Record<string, unknown>
      | undefined;
    if (String(existingLock?.saleId ?? "").trim()) {
      throw new WhatsAppCatalogCartValidationError("cart_changed");
    }
    if (existingCartItems.size > WHATSAPP_CATALOG_CART_MAX_EXISTING_ITEMS) {
      throw new WhatsAppCatalogCartValidationError("cart_too_large");
    }
    const plan = planWhatsAppCatalogCartReplacement({
      merchantId: request.merchantId,
      merchantExists: merchantSnapshot.exists,
      merchant: merchantSnapshot.data() ?? {},
      items: resolvedItems.map((item, index) => ({
        request: item,
        product: productSnapshots[index].exists
          ? (productSnapshots[index].data() ?? {})
          : undefined,
      })),
    });
    const nativeCartFingerprint = nativeCatalogCartFingerprint({
      merchantId: request.merchantId,
      customerId: request.customerId,
      catalogId: request.catalogId,
      items: plan.items,
    });
    const responseCart = cartResponse(plan, nativeCartFingerprint);

    existingCartItems.docs.forEach((item) => tx.delete(item.ref));
    for (const item of plan.items) {
      tx.set(cartRef.collection("items").doc(item.productId), {
        quantity: item.quantity,
        details: {
          productId: item.productId,
          name: item.projection.title,
          productName: item.projection.title,
          price: item.priceMinor / 100,
          sellingPrice: item.priceMinor / 100,
          imageUrl: item.projection.imageUrl,
          image: item.projection.imageUrl,
          description: item.projection.description,
        },
        catalogRetailerId: item.retailerId,
        catalogRevision: item.catalogRevision,
        catalogPriceMinor: item.priceMinor,
        source: "whatsapp_native_catalog",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    tx.set(
      cartRef,
      {
        total: plan.total,
        totalMinor: plan.totalMinor,
        itemsCount: plan.itemsCount,
        lineCount: plan.lineCount,
        currency: plan.currency,
        source: "whatsapp_native_catalog",
        catalogId: request.catalogId,
        catalogCartFingerprint: fingerprint,
        nativeCartFingerprint,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.set(stateRef, {
      merchantId: request.merchantId,
      customerId: request.customerId,
      catalogId: request.catalogId,
      fingerprint: nativeCartFingerprint,
      schemaVersion: 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(idempotencyRef, {
      fingerprint,
      recipientHash,
      merchantId: request.merchantId,
      customerId: request.customerId,
      cart: responseCart,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + IDEMPOTENCY_RETENTION_MS),
    });
    return { outcome: "replaced" as const, cart: responseCart };
  });
}

/**
 * Replaces a WhatsApp-native cart atomically. All mapping, ownership,
 * revision, price, visibility and stock checks happen inside the transaction
 * and before the first delete or set.
 */
export const replaceWhatsAppCatalogCartBotHttp = functions
  .runWith({
    secrets: ["PASELLA_BOT_TOKEN", "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY"],
    timeoutSeconds: 30,
    memory: "256MB",
    maxInstances: 10,
  })
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
    const request = parseWhatsAppCatalogCartRequest(req.body);
    if (!request) {
      res.status(400).json({
        outcome: "rejected",
        reason: "invalid_request",
        code: "INVALID_REQUEST",
      });
      return;
    }

    let config;
    try {
      config = whatsappProductListRuntimeConfig();
    } catch (_) {
      res.status(503).json({
        outcome: "rejected",
        reason: "configuration_blocked",
        code: "CONFIGURATION_BLOCKED",
      });
      return;
    }
    const accessReason = whatsappNativeCatalogAccessReason(
      config,
      request.merchantId,
      request.recipient,
    );
    if (accessReason) {
      res.status(403).json({
        outcome: "rejected",
        reason: accessReason,
        code: accessReason.toUpperCase(),
      });
      return;
    }
    if (request.catalogId !== config.catalogId) {
      res.status(409).json({
        outcome: "rejected",
        reason: "catalog_mismatch",
        code: "CATALOG_MISMATCH",
      });
      return;
    }
    if (request.senderPhoneNumberId !== config.phoneNumberId) {
      res.status(409).json({
        outcome: "rejected",
        reason: "sender_mismatch",
        code: "SENDER_MISMATCH",
      });
      return;
    }

    try {
      const result = await replaceWhatsAppCatalogCartAtomically({
        request,
        recipientHash: currentControlledWhatsAppRecipientDigest(
          request.recipient,
        ),
      });
      res.status(200).json(result);
    } catch (error) {
      if (error instanceof WhatsAppCatalogCartValidationError) {
        res.status(409).json({
          outcome: "rejected",
          reason: error.reason,
          code: error.reason.toUpperCase(),
          ...(error.failedItemIndex === undefined
            ? {}
            : { failedItemIndex: error.failedItemIndex }),
        });
        return;
      }
      console.error("[whatsapp-native-catalog-cart] write failed", {
        merchantId: request.merchantId,
        code: error instanceof Error ? error.name : "UNKNOWN",
      });
      res.status(500).json({
        outcome: "rejected",
        reason: "cart_write_failed",
        code: "CART_WRITE_FAILED",
      });
    }
  });
