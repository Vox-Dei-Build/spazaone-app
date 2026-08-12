import axios from "axios";
import { createHash } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import { paystackSecret } from "../../config/environment";
import {
  createCjDropshipOrder,
  getCjBalanceUsdMinor,
  payCjOrderFromBalance,
  quoteCjVariant,
} from "../../commerce/cjClient";
import {
  deliverCommerceOrderNotificationOutbox,
  enqueueCommerceOrderNotification,
} from "../../commerce/notifications";
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
import { estimatedOwnedOrderProviderFeeMinor } from "./ownedOrders";
import { paymentReadiness } from "./readiness";
import { executePaystackRefundV2, requestRefundCaseV2 } from "./refunds";

export type SupplierPaymentEconomics = {
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
}): SupplierPaymentEconomics {
  const landed = requirePositiveMinorUnits(
    input.landedCostMinor,
    "landed_cost",
  );
  const markup = requirePositiveMinorUnits(input.markupMinor, "markup");
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
  const providerFee = estimatedOwnedOrderProviderFeeMinor({
    amountMinor: low,
    channel: "eft",
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
  });
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
  if ((await getCjBalanceUsdMinor()) < requiredUsdMinor) {
    throw new Error("CJ_BALANCE_INSUFFICIENT");
  }
  const created = await createPaymentIntentV2({
    merchantId: sellerId,
    purpose: "supplier_order",
    idempotencyKey: `supplier-order:${orderId}`,
    expectedAmountMinor: economics.customerTotalMinor,
    businessBinding: { type: "supplier_order", id: orderId },
    money: economics.money,
    initiatedBy: "public_checkout",
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
      selectedChannel: "eft",
      paystackSubaccountCode: subaccountCode,
      settlementDestination: {
        bankName: String(profileData.bankName ?? ""),
        accountName: String(profileData.resolvedAccountName ?? ""),
        accountLast4: String(profileData.accountLast4 ?? ""),
      },
      updatedAt: now,
    });
    tx.set(
      orderRef,
      {
        paymentIntentId: created.intentId,
        payment: {
          provider: "paystack",
          reference,
          channel: "eft",
          schemaVersion: 2,
        },
        collectionFeeMinor: economics.collectionFeeMinor,
        safetyMarginMinor: economics.safetyMarginMinor,
        money: economics.money,
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
        channels: ["eft"],
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
          selectedChannel: "eft",
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

/**
 * Claims one paid supplier order, revalidates CJ, checks the pre-funded USD
 * balance, creates the order, pays it, and only then advances to preparing.
 */
export async function processSupplierFulfilmentV2(
  fulfilmentIdValue: unknown,
): Promise<{ status: "accepted" | "refund_pending"; deduped: boolean }> {
  const fulfilmentId = text(fulfilmentIdValue, "FULFILMENT_ID", 200);
  const ref = db.doc(`supplierFulfilments/${fulfilmentId}`);
  const claimId = stableDocumentId("claim", [fulfilmentId, String(Date.now())]);
  const claimed = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) throw new Error("SUPPLIER_FULFILMENT_NOT_FOUND");
    const data = snapshot.data() ?? {};
    if (data.status === "accepted") return { deduped: true, data };
    if (data.status === "refund_pending") return { deduped: true, data };
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
        claimed.data.status === "accepted" ? "accepted" : "refund_pending",
      deduped: true,
    };
  }
  const data = claimed.data;
  const intentId = text(data.intentId, "INTENT_ID");
  const orderId = text(data.orderId, "ORDER_ID");
  try {
    const liveQuote = await quoteCjVariant({
      productId: text(data.productId, "PRODUCT_ID"),
      variantId: text(data.variantId, "VARIANT_ID"),
      postalCode: text(data.shipping?.postalCode, "POSTAL_CODE", 20),
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
    const balanceUsdMinor = await getCjBalanceUsdMinor();
    if (balanceUsdMinor < verifiedTotalUsd) {
      throw new Error("CJ_BALANCE_INSUFFICIENT");
    }
    const created = await createCjDropshipOrder({
      orderNumber: `SPAZA-${orderId}`.slice(0, 50),
      variantId: liveQuote.variant.variantId,
      quantity: 1,
      logisticName: liveQuote.logisticName,
      fromCountryCode: liveQuote.originCountryCode,
      shipping: {
        postalCode: text(data.shipping?.postalCode, "POSTAL_CODE", 20),
        country: "South Africa",
        countryCode: "ZA",
        province: text(data.shipping?.province, "PROVINCE", 50),
        city: text(data.shipping?.city, "CITY", 50),
        phone: text(data.shipping?.phone, "PHONE", 20),
        customerName: text(data.shipping?.customerName, "CUSTOMER_NAME", 50),
        address1: text(data.shipping?.address1, "ADDRESS", 200),
        address2: String(data.shipping?.address2 ?? "").slice(0, 200),
        email: String(data.shipping?.email ?? "").slice(0, 50),
      },
    });
    const actualPaymentUsdMinor = requirePositiveMinorUnits(
      created.actualPaymentUsdMinor,
      "cj_actual_payment_usd",
    );
    if (actualPaymentUsdMinor > verifiedTotalUsd) {
      throw new Error("CJ_ACTUAL_CHARGE_EXCEEDS_SNAPSHOT");
    }
    await payCjOrderFromBalance(created.orderId);
    let notificationId = "";
    await db.runTransaction(async (tx) => {
      const current = await tx.get(ref);
      if (current.get("claimId") !== claimId) {
        throw new Error("SUPPLIER_FULFILMENT_CLAIM_LOST");
      }
      const now = FieldValue.serverTimestamp();
      tx.update(ref, {
        status: "accepted",
        cjOrderId: created.orderId,
        cjShipmentOrderId: created.shipmentOrderId,
        cjOrderNumber: created.orderNumber,
        cjActualPaymentUsdMinor: actualPaymentUsdMinor,
        cjSandbox: created.sandbox,
        cjPaidAt: now,
        leaseUntilMs: 0,
        updatedAt: now,
      });
      tx.update(db.doc(`commerceOrders/${orderId}`), {
        status: "submitted_for_fulfilment",
        fulfilmentStatus: "submitted_for_fulfilment",
        supplierOrder: {
          provider: "cj_dropshipping",
          orderId: created.orderId,
          shipmentOrderId: created.shipmentOrderId,
          sandbox: created.sandbox,
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
        eventKey: `cj-accepted-${created.orderId}`,
      });
    });
    if (notificationId) {
      await deliverCommerceOrderNotificationOutbox(notificationId).catch(
        () => undefined,
      );
    }
    return { status: "accepted", deduped: false };
  } catch (error) {
    const code = error instanceof Error ? error.message : "CJ_UNAVAILABLE";
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
