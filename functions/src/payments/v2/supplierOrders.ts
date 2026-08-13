import axios from "axios";
import { createHash } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import { paystackSecret } from "../../config/environment";
import {
  createCjDropshipOrder,
  deleteCjOrderIfUnpaid,
  getCjOrderDetail,
  payCjOrderFromBalance,
  quoteCjVariant,
} from "../../commerce/cjClient";
import {
  deliverCommerceOrderNotificationOutbox,
  enqueueCommerceOrderNotification,
} from "../../commerce/notifications";
import { validatedTrackingUrl } from "../../commerce/tracking";
import {
  buildMoneySnapshot,
  calculatePlatformFeeMinor,
  MoneySnapshot,
  requireMinorUnits,
  requirePositiveMinorUnits,
  stableDocumentId,
} from "./domain";
import {
  createPaymentIntentV2,
  providerEventDocumentId,
  recordProviderEventV2,
} from "./financialCore";
import {
  estimatedOwnedOrderProviderFeeMinor,
  isOwnedOrderChannel,
  OWNED_ORDER_CHANNELS,
  OwnedOrderChannel,
} from "./ownedOrders";
import { paymentReadiness } from "./readiness";
import {
  executePaystackRefundV2,
  openRefundCaseInTransactionV2,
  requestRefundCaseV2,
} from "./refunds";
import {
  confirmSupplierFunding,
  consumeSupplierFunding,
  releaseSupplierFunding,
  reserveSupplierFunding,
  supplierFundingReservationId,
} from "./supplierFunding";

export type SupplierPaymentEconomics = {
  quantity: number;
  landedCostMinor: number;
  markupMinor: number;
  collectionFeeMinor: number;
  estimatedProviderFeeMinor: number;
  safetyMarginMinor: number;
  customerTotalMinor: number;
  merchantNetProceedsMinor: number;
  money: MoneySnapshot;
};

/** Grosses up the collection fee so landed cost and seller markup are intact. */
export function supplierPaymentEconomics(input: {
  landedCostMinor: number;
  markupMinor: number;
  safetyMarginMinor?: number;
  quantity?: number;
  channel?: OwnedOrderChannel;
}): SupplierPaymentEconomics {
  const landed = requirePositiveMinorUnits(
    input.landedCostMinor,
    "landed_cost",
  );
  const unitMarkup = requirePositiveMinorUnits(input.markupMinor, "markup");
  const quantity = Number(input.quantity ?? 1);
  if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 20) {
    throw new Error("SUPPLIER_QUANTITY_INVALID");
  }
  const markup = unitMarkup * quantity;
  const safety = requireMinorUnits(
    input.safetyMarginMinor ?? 100,
    "safety_margin",
  );
  const subtotal = landed + markup;
  let low = subtotal;
  let high = subtotal + Math.max(10_000, Math.ceil(subtotal / 10));
  while (
    high - calculatePlatformFeeMinor({ grossAmountMinor: high }) <
    subtotal
  ) {
    high *= 2;
  }
  while (low < high) {
    const midpoint = Math.floor((low + high) / 2);
    const net =
      midpoint - calculatePlatformFeeMinor({ grossAmountMinor: midpoint });
    if (net < subtotal) low = midpoint + 1;
    else high = midpoint;
  }
  const collectionFeeMinor = calculatePlatformFeeMinor({
    grossAmountMinor: low,
  });
  if (low - collectionFeeMinor !== subtotal) {
    throw new Error("SUPPLIER_COLLECTION_GROSS_UP_INVALID");
  }
  const channel = input.channel ?? "eft";
  const providerFee = estimatedOwnedOrderProviderFeeMinor({
    amountMinor: low,
    channel,
  });
  if (markup - providerFee < safety) {
    throw new Error("SUPPLIER_MARGIN_BELOW_SAFETY");
  }
  const money = buildMoneySnapshot({
    grossAmountMinor: low,
    platformFeeMinor: collectionFeeMinor,
    providerFeeMinor: providerFee,
    retainedCostMinor: landed,
  });
  if (money.merchantGrossShareMinor !== markup) {
    throw new Error("SUPPLIER_SPLIT_INVALID");
  }
  if (money.merchantNetProceedsMinor < safety) {
    throw new Error("SUPPLIER_MARGIN_BELOW_SAFETY");
  }
  return {
    quantity,
    landedCostMinor: landed,
    markupMinor: markup,
    collectionFeeMinor,
    estimatedProviderFeeMinor: providerFee,
    safetyMarginMinor: safety,
    customerTotalMinor: low,
    merchantNetProceedsMinor: money.merchantNetProceedsMinor,
    money,
  };
}

export function profitableSupplierChannels(input: {
  landedCostMinor: number;
  markupMinor: number;
  safetyMarginMinor?: number;
  quantity?: number;
}): OwnedOrderChannel[] {
  return OWNED_ORDER_CHANNELS.filter((channel) => {
    try {
      supplierPaymentEconomics({ ...input, channel });
      return true;
    } catch (_) {
      return false;
    }
  });
}

function text(value: unknown, field: string, max = 200): string {
  const result = String(value ?? "")
    .trim()
    .slice(0, max);
  if (!result) throw new Error(`${field}_INVALID`);
  return result;
}

function supplierReference(intentId: string): string {
  return `p2-sup-${createHash("sha256")
    .update(intentId)
    .digest("hex")
    .slice(0, 32)}`;
}

/** Initializes the single V2 Paystack rail for an already snapshotted order. */
export async function initializeSupplierOrderPaymentV2(input: {
  orderId: string;
  email: string;
  callbackUrl: string;
  channel?: OwnedOrderChannel;
}): Promise<{
  authorizationUrl: string;
  reference: string;
  intentId: string;
  amountMinor: number;
  deduped: boolean;
}> {
  const orderId = text(input.orderId, "ORDER_ID");
  const email = String(input.email ?? "")
    .trim()
    .toLowerCase();
  if (!/^\S+@\S+\.\S+$/.test(email)) throw new Error("BUYER_EMAIL_INVALID");
  const callbackUrl = String(input.callbackUrl ?? "").trim();
  if (!/^https?:\/\//.test(callbackUrl))
    throw new Error("CALLBACK_URL_INVALID");
  const orderRef = db.doc(`commerceOrders/${orderId}`);
  const order = await orderRef.get();
  if (!order.exists) throw new Error("SUPPLIER_ORDER_NOT_FOUND");
  const orderData = order.data() ?? {};
  const channel = input.channel ?? orderData.requestedPaymentChannel;
  if (!isOwnedOrderChannel(channel)) throw new Error("ORDER_CHANNEL_INVALID");
  const sellerId = text(orderData.sellerId, "SELLER_ID");
  if (
    String(orderData.supplierId ?? "") !== "cj_dropshipping" ||
    String(orderData.paymentMethod ?? "") !== "paystack" ||
    String(orderData.paymentStatus ?? "") !== "pending" ||
    String(orderData.status ?? "") !== "pending_payment"
  ) {
    throw new Error("SUPPLIER_ORDER_NOT_PAYABLE");
  }
  const readiness = await paymentReadiness({
    merchantId: sellerId,
    purpose: "supplier_order",
  });
  if (!readiness.enabled) throw new Error("PAYMENT_CAPABILITY_DISABLED");
  const profile = await db.doc(`merchantPaymentProfiles/${sellerId}`).get();
  const profileData = profile.data() ?? {};
  const subaccountCode = String(profileData.paystackSubaccountCode ?? "");
  if (
    profileData.bankVerificationStatus !== "approved" ||
    !/^ACCT_[A-Za-z0-9]+$/.test(subaccountCode)
  ) {
    throw new Error("MERCHANT_SETTLEMENT_NOT_APPROVED");
  }
  const economics = supplierPaymentEconomics({
    landedCostMinor: orderData.baseCostMinor,
    markupMinor: orderData.markupMinor,
    safetyMarginMinor: orderData.safetyMarginMinor,
    quantity: orderData.quantity ?? orderData.totals?.quantity ?? 1,
    channel,
  });
  const profitableChannels = profitableSupplierChannels({
    landedCostMinor: orderData.baseCostMinor,
    markupMinor: orderData.markupMinor,
    safetyMarginMinor: orderData.safetyMarginMinor,
    quantity: orderData.quantity ?? orderData.totals?.quantity ?? 1,
  });
  if (!profitableChannels.includes(channel)) {
    throw new Error("SUPPLIER_CHANNEL_UNPROFITABLE");
  }
  if (economics.customerTotalMinor !== Number(orderData.amountDueMinor)) {
    throw new Error("SUPPLIER_ORDER_AMOUNT_CHANGED");
  }
  const requiredUsdMinor =
    requirePositiveMinorUnits(
      orderData.supplierProductCostUsdMinor,
      "product_cost_usd",
    ) +
    requirePositiveMinorUnits(
      orderData.supplierShippingCostUsdMinor,
      "shipping_cost_usd",
    );
  const created = await createPaymentIntentV2({
    merchantId: sellerId,
    purpose: "supplier_order",
    idempotencyKey: `supplier-order:${orderId}`,
    expectedAmountMinor: economics.customerTotalMinor,
    businessBinding: { type: "supplier_order", id: orderId },
    money: economics.money,
    initiatedBy: "public_checkout",
  });
  const funding = await reserveSupplierFunding({
    orderId,
    intentId: created.intentId,
    requiredUsdMinor,
  });
  const intentRef = db.doc(`paymentIntents/${created.intentId}`);
  const reference = supplierReference(created.intentId);
  const claimId = stableDocumentId("claim", [
    created.intentId,
    String(Date.now()),
  ]);
  const existing = await db.runTransaction(async (tx) => {
    const [intent, currentOrder] = await Promise.all([
      tx.get(intentRef),
      tx.get(orderRef),
    ]);
    const intentData = intent.data() ?? {};
    const currentOrderData = currentOrder.data() ?? {};
    if (intentData.status === "initialized") {
      return {
        authorizationUrl: String(intentData.authorizationUrl ?? ""),
        providerReference: String(intentData.providerReference ?? ""),
      };
    }
    if (
      currentOrderData.paymentIntentId &&
      currentOrderData.paymentIntentId !== created.intentId
    ) {
      throw new Error("SUPPLIER_ORDER_PAYMENT_COLLISION");
    }
    if (
      intentData.initializationState === "processing" &&
      Number(intentData.initializationLeaseUntilMs ?? 0) > Date.now()
    ) {
      throw new Error("PAYMENT_INITIALIZATION_IN_PROGRESS");
    }
    const now = FieldValue.serverTimestamp();
    tx.update(intentRef, {
      initializationState: "processing",
      initializationClaimId: claimId,
      initializationLeaseUntilMs: Date.now() + 45_000,
      initializationAttempts: FieldValue.increment(1),
      selectedChannel: channel,
      paystackSubaccountCode: subaccountCode,
      settlementDestination: {
        bankName: String(profileData.bankName ?? ""),
        accountName: String(profileData.resolvedAccountName ?? ""),
        accountLast4: String(profileData.accountLast4 ?? ""),
      },
      supplierFundingReservationId: funding.reservationId,
      updatedAt: now,
    });
    tx.set(
      orderRef,
      {
        paymentIntentId: created.intentId,
        payment: {
          provider: "paystack",
          reference,
          channel,
          schemaVersion: 2,
        },
        collectionFeeMinor: economics.collectionFeeMinor,
        safetyMarginMinor: economics.safetyMarginMinor,
        money: economics.money,
        supplierFundingReservationId: funding.reservationId,
        updatedAt: now,
      },
      { merge: true },
    );
    return { authorizationUrl: "", providerReference: "" };
  });
  if (existing.authorizationUrl && existing.providerReference) {
    return {
      authorizationUrl: existing.authorizationUrl,
      reference: existing.providerReference,
      intentId: created.intentId,
      amountMinor: economics.customerTotalMinor,
      deduped: true,
    };
  }
  try {
    const response = await axios.post(
      "https://api.paystack.co/transaction/initialize",
      {
        email,
        amount: economics.customerTotalMinor,
        currency: "ZAR",
        channels: [channel],
        reference,
        callback_url: callbackUrl,
        subaccount: subaccountCode,
        transaction_charge:
          economics.landedCostMinor + economics.collectionFeeMinor,
        bearer: "subaccount",
        metadata: {
          schemaVersion: 2,
          purpose: "supplier_order",
          intentId: created.intentId,
          orderId,
          sellerId,
          selectedChannel: channel,
        },
      },
      {
        headers: { Authorization: `Bearer ${paystackSecret()}` },
        timeout: 15_000,
      },
    );
    const authorizationUrl = String(
      response.data?.data?.authorization_url ?? "",
    ).trim();
    const providerReference = String(
      response.data?.data?.reference ?? "",
    ).trim();
    if (!authorizationUrl || providerReference !== reference) {
      throw new Error("PAYSTACK_INITIALIZE_RESPONSE_INVALID");
    }
    await db.runTransaction(async (tx) => {
      const intent = await tx.get(intentRef);
      const data = intent.data() ?? {};
      if (
        data.status === "initialized" &&
        data.providerReference === reference
      ) {
        return;
      }
      if (data.initializationClaimId !== claimId) {
        throw new Error("PAYMENT_INITIALIZATION_CLAIM_LOST");
      }
      const now = FieldValue.serverTimestamp();
      tx.update(intentRef, {
        status: "initialized",
        previousStatus: "created",
        provider: "paystack",
        providerReference: reference,
        authorizationUrl,
        initializationState: "completed",
        initializationLeaseUntilMs: 0,
        initializedAt: now,
        updatedAt: now,
      });
      tx.update(orderRef, {
        "payment.authorizationUrl": authorizationUrl,
        "payment.initializedAt": now,
        updatedAt: now,
      });
    });
    return {
      authorizationUrl,
      reference,
      intentId: created.intentId,
      amountMinor: economics.customerTotalMinor,
      deduped: created.deduped,
    };
  } catch (error) {
    await intentRef.set(
      {
        initializationState: "retryable",
        initializationLeaseUntilMs: 0,
        initializationErrorCode: "provider_initialization_failed",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    throw error;
  }
}

async function queueSupplierRefund(input: {
  intentId: string;
  orderId: string;
  reason: string;
}): Promise<void> {
  const intent = await db.doc(`paymentIntents/${input.intentId}`).get();
  const amount = requirePositiveMinorUnits(
    intent.get("expectedAmountMinor"),
    "refund_amount",
  );
  const refund = await requestRefundCaseV2({
    intentId: input.intentId,
    idempotencyKey: `supplier-failure:${input.orderId}`,
    refundAmountMinor: amount,
    reason: input.reason,
    owner: "operations",
    commerceOrderId: input.orderId,
  });
  await db.doc(`commerceOrders/${input.orderId}`).set(
    {
      status: "cancelled",
      fulfilmentStatus: "cancelled",
      paymentStatus: "refund_pending",
      refundCaseId: refund.refundCaseId,
      updatedAt: FieldValue.serverTimestamp(),
      statusHistory: FieldValue.arrayUnion({
        from: "paid",
        to: "cancelled",
        actor: "supplier_fulfilment_worker",
        reason: input.reason,
        at: new Date().toISOString(),
      }),
    },
    { merge: true },
  );
  await executePaystackRefundV2(refund.refundCaseId).catch((error) => {
    console.error("[payments-v2] supplier refund submission queued", {
      refundCaseId: refund.refundCaseId,
      code: error instanceof Error ? error.message : "unknown",
    });
  });
}

type SupplierFulfilmentOutcome =
  | "accepted"
  | "refund_pending"
  | "retry"
  | "operations_review";

export type SupplierOperationsResolution = "retry" | "refund";

/**
 * Operations may resolve a supplier ambiguity only after CJ independently
 * proves that no provider order exists. This keeps a paid or ambiguously paid
 * CJ order out of every automatic retry/refund path.
 */
export function supplierOperationsResolutionDecision(input: {
  action: unknown;
  fulfilmentStatus: unknown;
  cjOrderId?: unknown;
  providerOrderAbsent: boolean | null;
}): SupplierOperationsResolution {
  const action = String(input.action ?? "") as SupplierOperationsResolution;
  if (!(["retry", "refund"] as const).includes(action)) {
    throw new Error("SUPPLIER_REVIEW_ACTION_INVALID");
  }
  if (String(input.fulfilmentStatus ?? "") !== "operations_review") {
    throw new Error("SUPPLIER_REVIEW_STATE_INVALID");
  }
  if (String(input.cjOrderId ?? "").trim()) {
    throw new Error("CJ_ORDER_EXISTS_REVIEW_REQUIRED");
  }
  if (input.providerOrderAbsent !== true) {
    throw new Error("CJ_OUTCOME_STILL_AMBIGUOUS");
  }
  return action;
}

export function supplierFulfilmentFailureDisposition(input: {
  code: string;
  cjOrderId?: string;
  providerOrderAbsent: boolean | null;
}): Exclude<SupplierFulfilmentOutcome, "accepted"> {
  if (
    ["CJ_RATE_LIMITED", "CJ_UNAVAILABLE"].includes(input.code) &&
    !input.cjOrderId
  ) {
    return "retry";
  }
  if (
    [
      "CJ_PRICE_OR_ROUTE_CHANGED",
      "CJ_BALANCE_INSUFFICIENT",
      "CJ_UPSTREAM_REJECTED",
      "CJ_ACTUAL_CHARGE_EXCEEDS_SNAPSHOT",
    ].includes(input.code) &&
    input.providerOrderAbsent === true
  ) {
    return "refund_pending";
  }
  return "operations_review";
}

function supplierFailureCode(error: unknown): string {
  return error instanceof Error
    ? String(error.message || "CJ_UNAVAILABLE").slice(0, 120)
    : "CJ_UNAVAILABLE";
}

async function recordSupplierOperationsReview(input: {
  fulfilmentId: string;
  orderId: string;
  intentId: string;
  code: string;
  cjOrderId?: string;
}): Promise<void> {
  const now = FieldValue.serverTimestamp();
  const alertId = stableDocumentId("alert", [
    "supplier_fulfilment",
    input.fulfilmentId,
    input.code,
  ]);
  const batch = db.batch();
  batch.set(
    db.doc(`supplierFulfilments/${input.fulfilmentId}`),
    {
      status: "operations_review",
      failureCode: input.code,
      owner: "operations",
      cjOrderId: input.cjOrderId || null,
      leaseUntilMs: 0,
      updatedAt: now,
    },
    { merge: true },
  );
  if (input.orderId) {
    batch.set(
      db.doc(`commerceOrders/${input.orderId}`),
      {
        fulfilmentStatus: "operations_review",
        operationsOwner: "operations",
        updatedAt: now,
      },
      { merge: true },
    );
  }
  batch.set(
    db.doc(`operationsAlerts/${alertId}`),
    {
      alertId,
      type: "supplier_fulfilment_ambiguity",
      fulfilmentId: input.fulfilmentId,
      orderId: input.orderId,
      intentId: input.intentId,
      cjOrderId: input.cjOrderId || null,
      code: input.code,
      owner: "operations",
      status: "open",
      schemaVersion: 2,
      createdAt: now,
      updatedAt: now,
    },
    { merge: true },
  );
  await batch.commit();
}

async function recordSupplierTrackingRetry(input: {
  fulfilmentId: string;
  orderId: string;
  intentId: string;
  cjOrderId: string;
  code: string;
}): Promise<void> {
  const now = FieldValue.serverTimestamp();
  const alertId = stableDocumentId("alert", [
    "supplier_tracking_retry",
    input.fulfilmentId,
    input.code,
  ]);
  const batch = db.batch();
  batch.set(
    db.doc(`supplierFulfilments/${input.fulfilmentId}`),
    {
      trackingFailureCode: input.code,
      trackingRetryAfterMs: Date.now() + 30 * 60 * 1000,
      updatedAt: now,
    },
    { merge: true },
  );
  batch.set(
    db.doc(`operationsAlerts/${alertId}`),
    {
      alertId,
      type: "supplier_tracking_provider_unavailable",
      fulfilmentId: input.fulfilmentId,
      orderId: input.orderId,
      intentId: input.intentId,
      cjOrderId: input.cjOrderId,
      code: input.code,
      owner: "operations",
      status: "open",
      retryable: true,
      schemaVersion: 2,
      createdAt: now,
      updatedAt: now,
    },
    { merge: true },
  );
  await batch.commit();
}

async function markSupplierRetry(
  fulfilmentId: string,
  code: string,
  cjOrderId = "",
): Promise<void> {
  await db.doc(`supplierFulfilments/${fulfilmentId}`).set(
    {
      status: "retry",
      failureCode: code,
      cjOrderId: cjOrderId || null,
      leaseUntilMs: 0,
      nextAttemptAfterMs: Date.now() + 5 * 60 * 1000,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function providerOrderAbsent(
  orderNumber: string,
): Promise<boolean | null> {
  try {
    await getCjOrderDetail(orderNumber);
    return false;
  } catch (error) {
    return supplierFailureCode(error) === "CJ_ORDER_NOT_FOUND" ? true : null;
  }
}

/**
 * Claims one paid supplier order, revalidates CJ, checks the pre-funded USD
 * balance, creates the order, pays it, and only then advances to preparing.
 */
export async function processSupplierFulfilmentV2(
  fulfilmentIdValue: unknown,
): Promise<{ status: SupplierFulfilmentOutcome; deduped: boolean }> {
  const fulfilmentId = text(fulfilmentIdValue, "FULFILMENT_ID", 200);
  const ref = db.doc(`supplierFulfilments/${fulfilmentId}`);
  const claimId = stableDocumentId("claim", [fulfilmentId, String(Date.now())]);
  const claimed = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) throw new Error("SUPPLIER_FULFILMENT_NOT_FOUND");
    const data = snapshot.data() ?? {};
    if (data.status === "accepted") return { deduped: true, data };
    if (["refund_pending", "operations_review"].includes(data.status)) {
      return { deduped: true, data };
    }
    if (
      data.status === "processing" &&
      Number(data.leaseUntilMs ?? 0) > Date.now()
    ) {
      throw new Error("SUPPLIER_FULFILMENT_IN_PROGRESS");
    }
    if (
      !["queued", "retry", "processing"].includes(String(data.status ?? ""))
    ) {
      throw new Error("SUPPLIER_FULFILMENT_NOT_PROCESSABLE");
    }
    tx.update(ref, {
      status: "processing",
      claimId,
      leaseUntilMs: Date.now() + 180_000,
      attempts: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { deduped: false, data };
  });
  if (claimed.deduped) {
    return {
      status:
        claimed.data.status === "accepted"
          ? "accepted"
          : claimed.data.status === "operations_review"
            ? "operations_review"
            : "refund_pending",
      deduped: true,
    };
  }
  const data = claimed.data;
  const intentId = text(data.intentId, "INTENT_ID");
  const orderId = text(data.orderId, "ORDER_ID");
  const quantity = Number(data.quantity ?? 1);
  if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 20) {
    throw new Error("SUPPLIER_QUANTITY_INVALID");
  }
  const orderNumber = `SPAZA-${orderId}`.slice(0, 50);
  let cjOrderId = String(data.cjOrderId ?? "").trim();
  let providerPaid: boolean | null = null;
  try {
    const liveQuote = await quoteCjVariant({
      productId: text(data.productId, "PRODUCT_ID"),
      variantId: text(data.variantId, "VARIANT_ID"),
      postalCode: text(data.shipping?.postalCode, "POSTAL_CODE", 20),
      quantity,
    });
    const expectedProductUsd = requirePositiveMinorUnits(
      data.productCostUsdMinor,
      "product_cost_usd",
    );
    const expectedShippingUsd = requirePositiveMinorUnits(
      data.shippingCostUsdMinor,
      "shipping_cost_usd",
    );
    const verifiedTotalUsd =
      liveQuote.productCostUsdMinor + liveQuote.shippingCostUsdMinor;
    if (
      liveQuote.productCostUsdMinor > expectedProductUsd ||
      liveQuote.shippingCostUsdMinor > expectedShippingUsd ||
      liveQuote.originCountryCode !== data.originCountryCode ||
      liveQuote.logisticName !== data.logisticName
    ) {
      throw new Error("CJ_PRICE_OR_ROUTE_CHANGED");
    }
    const fundingReservationId = supplierFundingReservationId(orderId);
    await confirmSupplierFunding({
      orderId,
      intentId,
      requiredUsdMinor: verifiedTotalUsd,
    });
    let shipmentOrderId = String(data.cjShipmentOrderId ?? "");
    let sandbox = Boolean(data.cjSandbox);
    let actualPaymentUsdMinor: number | null = null;
    let detail: Awaited<ReturnType<typeof getCjOrderDetail>> | null = null;
    try {
      // CJ's create-order response may expose a parent/shipment identifier
      // before its query API exposes the canonical payable sub-order ID. The
      // immutable merchant order number remains the authoritative recovery
      // key for retries.
      detail = await getCjOrderDetail(orderNumber);
      cjOrderId = detail.orderId;
      providerPaid = detail.paid;
      actualPaymentUsdMinor = detail.actualPaymentUsdMinor;
    } catch (error) {
      if (supplierFailureCode(error) !== "CJ_ORDER_NOT_FOUND") throw error;
      if (cjOrderId) throw new Error("CJ_CREATE_OUTCOME_AMBIGUOUS");
    }
    if (!detail) {
      try {
        const created = await createCjDropshipOrder({
          orderNumber,
          variantId: liveQuote.variant.variantId,
          quantity,
          logisticName: liveQuote.logisticName,
          fromCountryCode: liveQuote.originCountryCode,
          shipping: {
            postalCode: text(data.shipping?.postalCode, "POSTAL_CODE", 20),
            country: "South Africa",
            countryCode: "ZA",
            province: text(data.shipping?.province, "PROVINCE", 50),
            city: text(data.shipping?.city, "CITY", 50),
            phone: text(data.shipping?.phone, "PHONE", 20),
            customerName: text(
              data.shipping?.customerName,
              "CUSTOMER_NAME",
              50,
            ),
            address1: text(data.shipping?.address1, "ADDRESS", 200),
            address2: String(data.shipping?.address2 ?? "").slice(0, 200),
            email: String(data.shipping?.email ?? "").slice(0, 50),
          },
        });
        cjOrderId = created.orderId;
        shipmentOrderId = created.shipmentOrderId;
        sandbox = created.sandbox;
        actualPaymentUsdMinor = created.actualPaymentUsdMinor;
      } catch (createError) {
        // A timed-out create may still have succeeded. CJ accepts our custom
        // order number for an authoritative recovery lookup.
        try {
          detail = await getCjOrderDetail(orderNumber);
          cjOrderId = detail.orderId;
          providerPaid = detail.paid;
          actualPaymentUsdMinor = detail.actualPaymentUsdMinor;
        } catch (recoveryError) {
          if (
            supplierFailureCode(recoveryError) === "CJ_ORDER_NOT_FOUND" &&
            supplierFailureCode(createError) === "CJ_UPSTREAM_REJECTED"
          ) {
            throw createError;
          }
          throw new Error("CJ_CREATE_OUTCOME_AMBIGUOUS");
        }
      }
    }
    if (!cjOrderId) throw new Error("CJ_CREATE_OUTCOME_AMBIGUOUS");
    await ref.set(
      {
        cjOrderId,
        cjShipmentOrderId: shipmentOrderId || null,
        cjOrderNumber: orderNumber,
        cjSandbox: sandbox,
        cjActualPaymentUsdMinor: actualPaymentUsdMinor,
        providerPaymentState:
          providerPaid === true
            ? "paid"
            : providerPaid === false
              ? "unpaid"
              : "unknown",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    if (!detail) {
      detail = await getCjOrderDetail(cjOrderId);
      providerPaid = detail.paid;
      actualPaymentUsdMinor =
        detail.actualPaymentUsdMinor ?? actualPaymentUsdMinor;
    }
    if (actualPaymentUsdMinor == null) {
      throw new Error("CJ_ACTUAL_CHARGE_AMBIGUOUS");
    }
    requirePositiveMinorUnits(actualPaymentUsdMinor, "cj_actual_payment_usd");
    if (actualPaymentUsdMinor > verifiedTotalUsd) {
      if (providerPaid === false && (await deleteCjOrderIfUnpaid(cjOrderId))) {
        cjOrderId = "";
      }
      throw new Error("CJ_ACTUAL_CHARGE_EXCEEDS_SNAPSHOT");
    }
    if (providerPaid === null) {
      throw new Error("CJ_PAYMENT_STATE_AMBIGUOUS");
    }
    if (providerPaid === false) {
      try {
        await payCjOrderFromBalance(cjOrderId);
      } catch (payError) {
        try {
          detail = await getCjOrderDetail(cjOrderId);
          providerPaid = detail.paid;
          actualPaymentUsdMinor =
            detail.actualPaymentUsdMinor ?? actualPaymentUsdMinor;
        } catch (_) {
          throw new Error("CJ_PAYMENT_OUTCOME_AMBIGUOUS");
        }
        if (providerPaid === false) {
          await markSupplierRetry(
            fulfilmentId,
            supplierFailureCode(payError),
            cjOrderId,
          );
          return { status: "retry", deduped: false };
        }
        if (providerPaid !== true) {
          throw new Error("CJ_PAYMENT_OUTCOME_AMBIGUOUS");
        }
      }
    }
    const fundingConsumed = await consumeSupplierFunding(fundingReservationId);
    if (!fundingConsumed) throw new Error("SUPPLIER_FUNDING_CONSUME_FAILED");
    let notificationId = "";
    await db.runTransaction(async (tx) => {
      const current = await tx.get(ref);
      if (current.get("claimId") !== claimId) {
        throw new Error("SUPPLIER_FULFILMENT_CLAIM_LOST");
      }
      const now = FieldValue.serverTimestamp();
      tx.update(ref, {
        status: "accepted",
        cjOrderId,
        cjShipmentOrderId: shipmentOrderId,
        cjOrderNumber: orderNumber,
        cjActualPaymentUsdMinor: actualPaymentUsdMinor,
        cjSandbox: sandbox,
        providerPaymentState: "paid",
        cjPaidAt: now,
        leaseUntilMs: 0,
        updatedAt: now,
      });
      tx.update(db.doc(`commerceOrders/${orderId}`), {
        status: "submitted_for_fulfilment",
        fulfilmentStatus: "submitted_for_fulfilment",
        supplierOrder: {
          provider: "cj_dropshipping",
          orderId: cjOrderId,
          shipmentOrderId,
          sandbox,
          actualPaymentUsdMinor,
          paidAt: now,
        },
        updatedAt: now,
        statusHistory: FieldValue.arrayUnion({
          from: "paid",
          to: "submitted_for_fulfilment",
          actor: "supplier_fulfilment_worker",
          at: new Date().toISOString(),
        }),
      });
      notificationId = enqueueCommerceOrderNotification(tx, {
        orderId,
        sellerId: text(data.sellerId, "SELLER_ID"),
        customerId: String(data.customerId ?? ""),
        buyerName: text(data.shipping?.customerName, "CUSTOMER_NAME", 100),
        buyerPhone: text(data.shipping?.phone, "PHONE", 32),
        status: "preparing",
        paymentMethod: "paystack",
        amountDueMinor: Number(data.amountDueMinor),
        orderKind: "supplier_delivery",
        eventKey: `cj-accepted-${cjOrderId}`,
      });
    });
    if (notificationId) {
      await deliverCommerceOrderNotificationOutbox(notificationId).catch(
        () => undefined,
      );
    }
    return { status: "accepted", deduped: false };
  } catch (error) {
    const code = supplierFailureCode(error);
    const preliminaryDisposition = supplierFulfilmentFailureDisposition({
      code,
      cjOrderId,
      providerOrderAbsent: null,
    });
    if (preliminaryDisposition === "retry") {
      await markSupplierRetry(fulfilmentId, code);
      return { status: "retry", deduped: false };
    }
    const absence = cjOrderId ? false : await providerOrderAbsent(orderNumber);
    const disposition = supplierFulfilmentFailureDisposition({
      code,
      cjOrderId,
      providerOrderAbsent: absence,
    });
    if (disposition === "refund_pending") {
      await releaseSupplierFunding(supplierFundingReservationId(orderId), code);
      await queueSupplierRefund({ intentId, orderId, reason: code });
      await ref.set(
        {
          status: "refund_pending",
          failureCode: code,
          owner: "operations",
          leaseUntilMs: 0,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return { status: "refund_pending", deduped: false };
    }
    await recordSupplierOperationsReview({
      fulfilmentId,
      orderId,
      intentId,
      code: absence === null ? `${code}_PROVIDER_CHECK_AMBIGUOUS` : code,
      cjOrderId,
    });
    return { status: "operations_review", deduped: false };
  }
}

export async function applyVerifiedSupplierPaymentV2(
  transaction: Record<string, any>,
  rawBody: Buffer,
): Promise<{ deduped: boolean; intentId: string; orderId: string }> {
  const metadata = transaction.metadata ?? {};
  const intentId = text(metadata.intentId, "INTENT_ID");
  const orderId = text(metadata.orderId, "ORDER_ID");
  const reference = text(transaction.reference, "REFERENCE");
  const amountMinor = requirePositiveMinorUnits(transaction.amount, "amount");
  const paidChannel = String(transaction.channel ?? "").trim();
  if (!isOwnedOrderChannel(paidChannel))
    throw new Error("ORDER_CHANNEL_INVALID");
  const providerFeeMinor = requireMinorUnits(
    transaction.fees ?? 0,
    "provider_fee",
  );
  const providerId = String(transaction.id ?? "").trim();
  const eventInput = {
    provider: "paystack" as const,
    ...(providerId ? { providerEventId: `charge-${providerId}` } : {}),
    eventType: "charge.success",
    reference,
    rawBody,
    intentId,
  };
  const recorded = await recordProviderEventV2(eventInput);
  const eventRef = db.doc(
    `paymentEvents/${providerEventDocumentId(eventInput)}`,
  );
  const intentRef = db.doc(`paymentIntents/${intentId}`);
  const orderRef = db.doc(`commerceOrders/${orderId}`);
  const fulfilmentRef = db.doc(`supplierFulfilments/${intentId}`);
  const settlementRef = db.doc(
    `settlements/${stableDocumentId("st", [intentId])}`,
  );
  let deduped = recorded.deduped;
  await db.runTransaction(async (tx) => {
    const [intent, event, order, fulfilment, settlement] = await Promise.all([
      tx.get(intentRef),
      tx.get(eventRef),
      tx.get(orderRef),
      tx.get(fulfilmentRef),
      tx.get(settlementRef),
    ]);
    if (!intent.exists || !event.exists || !order.exists) {
      throw new Error("SUPPLIER_PAYMENT_CORE_MISSING");
    }
    const intentData = intent.data() ?? {};
    const orderData = order.data() ?? {};
    if (
      intentData.purpose !== "supplier_order" ||
      intentData.businessBinding?.type !== "supplier_order" ||
      intentData.businessBinding?.id !== orderId ||
      intentData.providerReference !== reference ||
      Number(intentData.expectedAmountMinor) !== amountMinor ||
      metadata.sellerId !== orderData.sellerId ||
      metadata.orderId !== orderId ||
      metadata.selectedChannel !== intentData.selectedChannel ||
      paidChannel !== intentData.selectedChannel ||
      paidChannel !== orderData.requestedPaymentChannel ||
      orderData.payment?.reference !== reference
    ) {
      throw new Error("SUPPLIER_PAYMENT_BINDING_MISMATCH");
    }
    const applied = Array.isArray(intentData.appliedProviderEventIds)
      ? intentData.appliedProviderEventIds.map(String)
      : [];
    if (applied.includes(eventRef.id)) {
      deduped = true;
      return;
    }
    if (fulfilment.exists || settlement.exists) {
      throw new Error("SUPPLIER_PAYMENT_IDEMPOTENCY_COLLISION");
    }
    const platformFeeMinor = Number(intentData.money?.platformFeeMinor ?? 0);
    const retainedCostMinor = Number(intentData.money?.retainedCostMinor ?? 0);
    const actualMoney = buildMoneySnapshot({
      grossAmountMinor: amountMinor,
      platformFeeMinor,
      retainedCostMinor,
      providerFeeMinor,
    });
    const safety = Number(orderData.safetyMarginMinor ?? 100);
    if (actualMoney.merchantNetProceedsMinor < safety) {
      throw new Error("SUPPLIER_ACTUAL_MARGIN_BELOW_SAFETY");
    }
    const now = FieldValue.serverTimestamp();
    tx.update(intentRef, {
      status: "paid",
      previousStatus: String(intentData.status),
      providerAmountMinor: amountMinor,
      providerFeeMinor,
      actualMoney,
      appliedProviderEventIds: FieldValue.arrayUnion(eventRef.id),
      paidAt: now,
      updatedAt: now,
    });
    tx.update(orderRef, {
      status: "paid",
      paymentStatus: "paid",
      fulfilmentStatus: "paid",
      "payment.actualFeeMinor": providerFeeMinor,
      "payment.channel": String(transaction.channel ?? ""),
      "payment.paidAtProvider": String(transaction.paid_at ?? ""),
      paidAt: now,
      updatedAt: now,
      statusHistory: FieldValue.arrayUnion({
        from: "pending_payment",
        to: "paid",
        actor: "paystack_v2_webhook",
        at: new Date().toISOString(),
        reference,
      }),
    });
    tx.create(fulfilmentRef, {
      fulfilmentId: intentId,
      intentId,
      orderId,
      sellerId: String(orderData.sellerId),
      customerId: String(orderData.customerId ?? ""),
      status: "queued",
      attempts: 0,
      leaseUntilMs: 0,
      productId: String(
        orderData.supplierProductId ??
          orderData.lineItems?.[0]?.supplierProductId ??
          "",
      ),
      variantId: String(orderData.supplierVariantId ?? ""),
      productCostUsdMinor: Number(orderData.supplierProductCostUsdMinor),
      shippingCostUsdMinor: Number(orderData.supplierShippingCostUsdMinor),
      originCountryCode: String(orderData.sourceCountryCode),
      logisticName: String(orderData.logisticName),
      shipping: {
        postalCode: String(orderData.deliveryAddress?.postalCode ?? ""),
        province: String(orderData.deliveryAddress?.province ?? ""),
        city: String(orderData.deliveryAddress?.city ?? ""),
        phone: String(orderData.buyer?.phone ?? ""),
        customerName: String(orderData.buyer?.name ?? ""),
        address1: String(orderData.deliveryAddress?.line1 ?? ""),
        address2: String(orderData.deliveryAddress?.line2 ?? ""),
        email: String(orderData.buyer?.email ?? ""),
      },
      amountDueMinor: amountMinor,
      quantity: Number(orderData.quantity ?? orderData.totals?.quantity ?? 1),
      supplierFundingReservationId: String(
        orderData.supplierFundingReservationId ??
          supplierFundingReservationId(orderId),
      ),
      schemaVersion: 2,
      createdAt: now,
      updatedAt: now,
    });
    tx.create(settlementRef, {
      settlementId: settlementRef.id,
      intentId,
      merchantId: String(orderData.sellerId),
      orderId,
      provider: "paystack",
      subaccountCode: String(intentData.paystackSubaccountCode ?? ""),
      destination: intentData.settlementDestination ?? {},
      grossAmountMinor: amountMinor,
      platformFeeMinor,
      retainedCostMinor,
      providerFeeMinor,
      merchantNetProceedsMinor: actualMoney.merchantNetProceedsMinor,
      status: "pending",
      currency: "ZAR",
      schemaVersion: 2,
      createdAt: now,
      updatedAt: now,
    });
    tx.update(eventRef, {
      processingState: "applied",
      attemptCount: FieldValue.increment(1),
      processedAt: now,
      updatedAt: now,
    });
  });
  return { deduped, intentId, orderId };
}

export type SupplierTrackingReconciliationResult = {
  checked: number;
  advanced: number;
  unchanged: number;
  needsOperationsReview: number;
};

export function commerceStatusForCj(
  status: string,
): "preparing" | "shipped" | "delivered" | null {
  if (["PENDING", "PROCESSING", "UNSHIPPED"].includes(status)) {
    return "preparing";
  }
  if (status === "SHIPPED") return "shipped";
  if (status === "DELIVERED") return "delivered";
  return null;
}

const COMMERCE_STATUS_RANK: Record<string, number> = {
  paid: 0,
  submitted_for_fulfilment: 1,
  preparing: 2,
  shipped: 3,
  on_the_way: 3,
  delivered: 4,
};

/** Reconciles CJ state into commerce orders using the unified outbox. */
export async function runSupplierTrackingReconciliationV2(input?: {
  limit?: number;
  source?: "scheduled" | "admin_on_demand";
  actorUid?: string;
}): Promise<SupplierTrackingReconciliationResult> {
  const limit = Math.min(100, Math.max(1, Number(input?.limit ?? 25)));
  const candidates = await db
    .collection("supplierFulfilments")
    .where("status", "==", "accepted")
    .limit(limit)
    .get();
  const result: SupplierTrackingReconciliationResult = {
    checked: 0,
    advanced: 0,
    unchanged: 0,
    needsOperationsReview: 0,
  };
  for (const fulfilment of candidates.docs) {
    result.checked += 1;
    const data = fulfilment.data();
    const orderId = String(data.orderId ?? "");
    const intentId = String(data.intentId ?? "");
    const cjOrderId = String(data.cjOrderId ?? "");
    if (!orderId || !intentId || !cjOrderId) {
      result.needsOperationsReview += 1;
      await recordSupplierOperationsReview({
        fulfilmentId: fulfilment.id,
        orderId,
        intentId,
        cjOrderId,
        code: "CJ_TRACKING_BINDING_MISSING",
      });
      continue;
    }
    let detail: Awaited<ReturnType<typeof getCjOrderDetail>>;
    try {
      detail = await getCjOrderDetail(cjOrderId);
    } catch (error) {
      const trackingCode = supplierFailureCode(error);
      if (["CJ_UNAVAILABLE", "CJ_RATE_LIMITED"].includes(trackingCode)) {
        result.unchanged += 1;
        await recordSupplierTrackingRetry({
          fulfilmentId: fulfilment.id,
          orderId,
          intentId,
          cjOrderId,
          code: trackingCode,
        });
        continue;
      }
      result.needsOperationsReview += 1;
      await recordSupplierOperationsReview({
        fulfilmentId: fulfilment.id,
        orderId,
        intentId,
        cjOrderId,
        code: `CJ_TRACKING_${trackingCode}`,
      });
      continue;
    }
    if (detail.status === "CANCELLED") {
      result.needsOperationsReview += 1;
      await recordSupplierOperationsReview({
        fulfilmentId: fulfilment.id,
        orderId,
        intentId,
        cjOrderId,
        code: "CJ_ORDER_CANCELLED_AFTER_PAYMENT",
      });
      continue;
    }
    let safeTrackingUrl: string | null = null;
    try {
      safeTrackingUrl = validatedTrackingUrl(detail.trackingUrl);
    } catch (_) {
      safeTrackingUrl = null;
    }
    const targetStatus = commerceStatusForCj(detail.status);
    let notificationId = "";
    let advanced = false;
    await db.runTransaction(async (tx) => {
      const [currentFulfilment, order] = await Promise.all([
        tx.get(fulfilment.ref),
        tx.get(db.doc(`commerceOrders/${orderId}`)),
      ]);
      if (!currentFulfilment.exists || !order.exists) {
        throw new Error("CJ_TRACKING_BINDING_MISSING");
      }
      const orderData = order.data() ?? {};
      const currentStatus = String(orderData.status ?? "");
      const now = FieldValue.serverTimestamp();
      tx.update(fulfilment.ref, {
        cjStatus: detail.status,
        trackingNumber: detail.trackingNumber || null,
        trackingUrl: safeTrackingUrl,
        trackingReconciledAt: now,
        trackingReconciliationSource: input?.source ?? "scheduled",
        trackingReconciliationActorUid: input?.actorUid ?? null,
        updatedAt: now,
      });
      if (
        !targetStatus ||
        (COMMERCE_STATUS_RANK[targetStatus] ?? -1) <=
          (COMMERCE_STATUS_RANK[currentStatus] ?? -1)
      ) {
        return;
      }
      advanced = true;
      tx.update(order.ref, {
        status: targetStatus,
        fulfilmentStatus: targetStatus,
        trackingNumber: detail.trackingNumber || null,
        trackingUrl: safeTrackingUrl,
        tracking: {
          carrier: "",
          number: detail.trackingNumber || "",
          url: safeTrackingUrl ?? "",
        },
        "supplierOrder.status": detail.status,
        "supplierOrder.trackingNumber": detail.trackingNumber || null,
        "supplierOrder.trackingUrl": safeTrackingUrl,
        updatedAt: now,
        statusHistory: FieldValue.arrayUnion({
          from: currentStatus,
          to: targetStatus,
          actor: "supplier_tracking_reconciliation",
          providerStatus: detail.status,
          at: new Date().toISOString(),
        }),
      });
      notificationId = enqueueCommerceOrderNotification(tx, {
        orderId,
        sellerId: String(orderData.sellerId ?? data.sellerId ?? ""),
        customerId: String(orderData.customerId ?? data.customerId ?? ""),
        buyerName: String(orderData.buyer?.name ?? "Customer"),
        buyerPhone: String(orderData.buyer?.phone ?? ""),
        status: targetStatus,
        paymentMethod: "paystack",
        amountDueMinor: Number(orderData.amountDueMinor ?? data.amountDueMinor),
        orderKind: "supplier_delivery",
        trackingNumber: detail.trackingNumber || undefined,
        trackingUrl: safeTrackingUrl || undefined,
        eventKey: `cj-${detail.status.toLowerCase()}-${cjOrderId}`,
      });
    });
    if (advanced) {
      result.advanced += 1;
      if (notificationId) {
        await deliverCommerceOrderNotificationOutbox(notificationId).catch(
          () => undefined,
        );
      }
    } else {
      result.unchanged += 1;
    }
  }
  return result;
}

export const reconcileSupplierTrackingV2OnDemand = functions
  .runWith({ secrets: ["CJ_API_KEY"], timeoutSeconds: 300 })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication required.",
      );
    }
    if (context.auth.token.spazaAdmin !== true) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Spaza One operations access required.",
      );
    }
    const operationId = String(data?.operationId ?? "").trim();
    const reason = String(data?.reason ?? "").trim();
    if (!/^[A-Za-z0-9:_-]{8,120}$/.test(operationId) || reason.length < 8) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "A unique operation ID and audit reason are required.",
      );
    }
    const auditRef = db.doc(
      `paymentOperations/${stableDocumentId("op", [
        "supplier_tracking_reconciliation",
        operationId,
      ])}`,
    );
    if ((await auditRef.get()).exists) {
      return { deduped: true, operationId };
    }
    const reconciliation = await runSupplierTrackingReconciliationV2({
      limit: data?.limit,
      source: "admin_on_demand",
      actorUid: context.auth.uid,
    });
    await auditRef.create({
      operationId,
      type: "supplier_tracking_reconciliation",
      reason: reason.slice(0, 500),
      actorUid: context.auth.uid,
      reconciliation,
      createdAt: FieldValue.serverTimestamp(),
      schemaVersion: 2,
    });
    return { deduped: false, operationId, ...reconciliation };
  });

/**
 * Audited recovery for a paid supplier order placed into operations review.
 * The command first asks CJ for the immutable Spaza One order number and only
 * permits retry/refund when CJ authoritatively reports that no order exists.
 */
export const resolveSupplierFulfilmentReviewV2 = functions
  .runWith({
    secrets: ["CJ_API_KEY", "PAYSTACK_SECRET_KEY"],
    timeoutSeconds: 300,
  })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication required.",
      );
    }
    if (context.auth.token.spazaAdmin !== true) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Spaza One operations access required.",
      );
    }
    const actorUid = context.auth.uid;
    const fulfilmentId = text(data?.fulfilmentId, "FULFILMENT_ID", 200);
    const operationId = String(data?.operationId ?? "").trim();
    const reason = String(data?.reason ?? "")
      .trim()
      .slice(0, 500);
    if (!/^[A-Za-z0-9:_-]{8,120}$/.test(operationId) || reason.length < 8) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "A unique operation ID and audit reason are required.",
      );
    }
    const action = String(data?.action ?? "") as SupplierOperationsResolution;
    if (!(["retry", "refund"] as const).includes(action)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Choose retry or refund.",
      );
    }

    const auditRef = db.doc(
      `paymentOperations/${stableDocumentId("op", [
        "supplier_fulfilment_review",
        operationId,
      ])}`,
    );
    const priorAudit = await auditRef.get();
    if (priorAudit.exists) {
      const previous = priorAudit.data() ?? {};
      if (
        previous.fulfilmentId !== fulfilmentId ||
        previous.action !== action ||
        previous.reason !== reason
      ) {
        throw new functions.https.HttpsError(
          "already-exists",
          "That operation ID is already bound to another resolution.",
        );
      }
      const previousOrderId = text(previous.orderId, "ORDER_ID");
      const previousIntentId = text(previous.intentId, "INTENT_ID");
      const previousRefundCaseId = String(previous.refundCaseId ?? "");
      let fundingReleased = Boolean(previous.fundingReleased);
      let refundSubmission = previous.refundSubmission ?? null;
      if (action === "refund" && previous.status !== "completed") {
        // The review transaction atomically released funding before the audit
        // was created. A retry here resumes only the provider submission.
        fundingReleased = true;
        refundSubmission = await executePaystackRefundV2(previousRefundCaseId);
        await auditRef.set(
          {
            status: "completed",
            fundingReleased,
            refundSubmission,
            completedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
      return {
        operationId,
        fulfilmentId: String(previous.fulfilmentId),
        orderId: previousOrderId,
        intentId: previousIntentId,
        action,
        providerOrderAbsent: true,
        refundCaseId: previousRefundCaseId || null,
        fundingReleased,
        refundSubmission,
        deduped: true,
      };
    }

    const fulfilmentRef = db.doc(`supplierFulfilments/${fulfilmentId}`);
    const initial = await fulfilmentRef.get();
    if (!initial.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Fulfilment not found.",
      );
    }
    const initialData = initial.data() ?? {};
    const orderId = text(initialData.orderId, "ORDER_ID");
    const intentId = text(initialData.intentId, "INTENT_ID");
    const orderNumber = `SPAZA-${orderId}`.slice(0, 50);
    let providerOrderAbsent: boolean | null = null;
    try {
      await getCjOrderDetail(orderNumber);
      providerOrderAbsent = false;
    } catch (error) {
      if (supplierFailureCode(error) === "CJ_ORDER_NOT_FOUND") {
        providerOrderAbsent = true;
      }
    }
    try {
      supplierOperationsResolutionDecision({
        action,
        fulfilmentStatus: initialData.status,
        cjOrderId: initialData.cjOrderId,
        providerOrderAbsent,
      });
    } catch (error) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        supplierFailureCode(error),
      );
    }

    const reservationId = supplierFundingReservationId(orderId);
    const reservationRef = db.doc(
      `supplierFundingReservations/${reservationId}`,
    );
    const fundingStateRef = db.doc("supplierFundingState/cj");
    let refundCaseId = "";
    let deduped = false;
    await db.runTransaction(async (tx) => {
      const [audit, fulfilment, order, intent, reservation, fundingState] =
        await Promise.all([
          tx.get(auditRef),
          tx.get(fulfilmentRef),
          tx.get(db.doc(`commerceOrders/${orderId}`)),
          tx.get(db.doc(`paymentIntents/${intentId}`)),
          tx.get(reservationRef),
          tx.get(fundingStateRef),
        ]);
      if (audit.exists) {
        const previous = audit.data() ?? {};
        if (
          previous.fulfilmentId !== fulfilmentId ||
          previous.action !== action ||
          previous.reason !== reason
        ) {
          throw new functions.https.HttpsError(
            "already-exists",
            "That operation ID is already bound to another resolution.",
          );
        }
        refundCaseId = String(previous.refundCaseId ?? "");
        deduped = true;
        return;
      }
      if (!fulfilment.exists || !order.exists || !intent.exists) {
        throw new Error("SUPPLIER_REVIEW_CORE_MISSING");
      }
      const fulfilmentData = fulfilment.data() ?? {};
      supplierOperationsResolutionDecision({
        action,
        fulfilmentStatus: fulfilmentData.status,
        cjOrderId: fulfilmentData.cjOrderId,
        providerOrderAbsent: true,
      });
      if (
        fulfilmentData.orderId !== orderId ||
        fulfilmentData.intentId !== intentId ||
        intent.get("purpose") !== "supplier_order" ||
        intent.get("businessBinding.id") !== orderId ||
        intent.get("status") !== "paid"
      ) {
        throw new Error("SUPPLIER_REVIEW_BINDING_INVALID");
      }
      const now = FieldValue.serverTimestamp();
      if (action === "retry") {
        if (
          !reservation.exists ||
          reservation.get("status") !== "active" ||
          Number(reservation.get("expiresAtMs") ?? 0) <= Date.now()
        ) {
          throw new Error("SUPPLIER_FUNDING_STATE_INVALID");
        }
        tx.update(fulfilmentRef, {
          status: "retry",
          failureCode: FieldValue.delete(),
          owner: FieldValue.delete(),
          leaseUntilMs: 0,
          reviewedAt: now,
          reviewedBy: actorUid,
          updatedAt: now,
        });
        tx.update(db.doc(`commerceOrders/${orderId}`), {
          fulfilmentStatus: "paid",
          operationsOwner: FieldValue.delete(),
          updatedAt: now,
        });
      } else {
        if (!reservation.exists || reservation.get("status") !== "active") {
          throw new Error("SUPPLIER_FUNDING_STATE_INVALID");
        }
        const requiredUsdMinor = requirePositiveMinorUnits(
          reservation.get("requiredUsdMinor"),
          "supplier_funding_required",
        );
        const outstandingUsdMinor = Number(
          fundingState.get("outstandingUsdMinor") ?? 0,
        );
        const providerBalanceUsdMinor = Number(
          fundingState.get("providerBalanceUsdMinor") ?? 0,
        );
        if (
          !Number.isSafeInteger(outstandingUsdMinor) ||
          outstandingUsdMinor < requiredUsdMinor ||
          !Number.isSafeInteger(providerBalanceUsdMinor)
        ) {
          throw new Error("SUPPLIER_FUNDING_STATE_INVALID");
        }
        const expectedAmountMinor = requirePositiveMinorUnits(
          intent.get("expectedAmountMinor"),
          "refund_amount",
        );
        const refund = await openRefundCaseInTransactionV2(tx, {
          intentId,
          idempotencyKey: `supplier-review:${orderId}`,
          refundAmountMinor: expectedAmountMinor,
          reason,
          owner: "operations",
          commerceOrderId: orderId,
        });
        refundCaseId = refund.refundCaseId;
        tx.update(fulfilmentRef, {
          status: "refund_pending",
          failureCode: "operations_authorized_pre_create_refund",
          owner: "operations",
          leaseUntilMs: 0,
          reviewedAt: now,
          reviewedBy: actorUid,
          updatedAt: now,
        });
        tx.update(db.doc(`commerceOrders/${orderId}`), {
          status: "cancelled",
          fulfilmentStatus: "cancelled",
          paymentStatus: "refund_pending",
          refundCaseId,
          operationsOwner: "operations",
          updatedAt: now,
          statusHistory: FieldValue.arrayUnion({
            from: "paid",
            to: "cancelled",
            actor: "supplier_operations_review",
            reason,
            at: new Date().toISOString(),
          }),
        });
        const nextOutstandingUsdMinor = outstandingUsdMinor - requiredUsdMinor;
        tx.update(reservationRef, {
          status: "released",
          closeReason: "operations_authorized_pre_create_refund",
          closedAt: now,
          updatedAt: now,
        });
        tx.set(
          fundingStateRef,
          {
            outstandingUsdMinor: nextOutstandingUsdMinor,
            remainingUsdMinor: Math.max(
              0,
              providerBalanceUsdMinor - nextOutstandingUsdMinor,
            ),
            updatedAt: now,
          },
          { merge: true },
        );
      }
      tx.create(auditRef, {
        operationId,
        type: "supplier_fulfilment_review_resolution",
        action,
        reason,
        actorUid,
        fulfilmentId,
        orderId,
        intentId,
        providerOrderAbsent: true,
        providerAbsenceCheckedAt: now,
        refundCaseId: refundCaseId || null,
        status: "authorized",
        schemaVersion: 2,
        createdAt: now,
        updatedAt: now,
      });
    });

    let fundingReleased = false;
    let refundSubmission: Record<string, unknown> | null = null;
    if (!deduped && action === "refund") {
      fundingReleased = true;
      refundSubmission = await executePaystackRefundV2(refundCaseId);
      await auditRef.set(
        {
          status: "completed",
          fundingReleased,
          refundSubmission,
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    } else if (!deduped) {
      await auditRef.set(
        {
          status: "completed",
          completedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    return {
      operationId,
      fulfilmentId,
      orderId,
      intentId,
      action,
      providerOrderAbsent: true,
      refundCaseId: refundCaseId || null,
      fundingReleased,
      refundSubmission,
      deduped,
    };
  });

export const reconcileSupplierTrackingV2 = functions
  .runWith({ secrets: ["CJ_API_KEY"], timeoutSeconds: 300 })
  .pubsub.schedule("every 30 minutes")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    await runSupplierTrackingReconciliationV2({ source: "scheduled" });
    return null;
  });

export const retrySupplierFulfilmentsV2 = functions
  .runWith({ secrets: ["CJ_API_KEY", "PAYSTACK_SECRET_KEY"] })
  .pubsub.schedule("every 5 minutes")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    const candidates = await db
      .collection("supplierFulfilments")
      .where("status", "in", ["queued", "retry", "processing"])
      .limit(20)
      .get();
    await Promise.all(
      candidates.docs.map((doc) =>
        processSupplierFulfilmentV2(doc.id).catch(() => undefined),
      ),
    );
    return null;
  });
