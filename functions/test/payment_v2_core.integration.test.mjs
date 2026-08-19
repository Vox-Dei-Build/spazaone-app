import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { after, before, test } from "node:test";
import admin from "firebase-admin";
import { buildMoneySnapshot } from "../lib/payments/v2/domain.js";
import {
  createPaymentIntentV2,
  recordProviderEventV2,
  transitionPaymentIntentV2,
} from "../lib/payments/v2/financialCore.js";
import {
  confirmProviderRefundV2,
  quarantineVerifiedChargeV2,
  requestRefundCaseV2,
} from "../lib/payments/v2/refunds.js";
import {
  applyVerifiedCampaignTopupV2,
  quoteCampaignTopup,
} from "../lib/payments/v2/campaignTopup.js";
import {
  applyVerifiedOwnedOrderPaymentV2,
  estimatedOwnedOrderProviderFeeMinor,
} from "../lib/payments/v2/ownedOrders.js";
import {
  consumeOwnedInventoryReservation,
  releaseOwnedInventoryReservation,
  reserveOwnedInventoryForSale,
} from "../lib/payments/v2/inventoryReservations.js";
import { applyVerifiedAccountSettlementV2 } from "../lib/payments/v2/accountSettlements.js";
import {
  applyVerifiedSupplierPaymentV2,
  supplierPaymentEconomics,
} from "../lib/payments/v2/supplierOrders.js";
import {
  consumeSupplierFunding,
  reserveSupplierFunding,
} from "../lib/payments/v2/supplierFunding.js";
import { runPaymentsV2Reconciliation } from "../lib/payments/v2/reconciliation.js";
import {
  recordAcceptedCustomerPaymentRequest,
  releaseReviewedCustomerPaymentRequest,
  reserveCustomerPaymentRequest,
} from "../lib/payments/v2/customerPaymentRequests.js";

const emulatorHost = String(process.env.FIRESTORE_EMULATOR_HOST ?? "");
const emulatorProject = String(
  process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "",
);
if (!emulatorHost || !emulatorProject.startsWith("demo-")) {
  throw new Error(
    "Refusing Payments V2 integration test without a demo Firestore emulator.",
  );
}

const db = admin.firestore();
const requireModule = createRequire(import.meta.url);
const axios = requireModule("axios");

async function clear() {
  for (const name of [
    "paymentIntents",
    "paymentEvents",
    "refundCases",
    "commerceOrders",
    "campaignCreditPurchases",
    "campaignCreditRecoveryCases",
    "campaignWalletOperations",
    "campaignWalletBalances",
    "inventoryReservations",
    "settlements",
    "commerceNotificationOutbox",
    "repaymentPlans",
    "supplierFulfilments",
    "supplierFundingReservations",
    "supplierFundingState",
    "supplierIntegrationState",
    "operationsAlerts",
    "financialReconciliationRuns",
    "paymentOperations",
    "customerPaymentRequests",
    "customerPaymentRequestState",
    "paymentRequestWalletReservations",
    "users",
    "stores",
  ]) {
    await db.recursiveDelete(db.collection(name));
  }
}

function intent(overrides = {}) {
  return {
    merchantId: "merchant-1",
    purpose: "merchant_order",
    idempotencyKey: "checkout-1",
    expectedAmountMinor: 10_000,
    businessBinding: { type: "sale", id: "sale-1" },
    money: buildMoneySnapshot({
      grossAmountMinor: 10_000,
      platformFeeMinor: 150,
      providerFeeMinor: 390,
    }),
    ...overrides,
  };
}

before(clear);
after(clear);

test("concurrent intent creation is immutable and idempotent", async () => {
  const results = await Promise.all([
    createPaymentIntentV2(intent()),
    createPaymentIntentV2(intent()),
  ]);
  assert.equal(new Set(results.map((result) => result.intentId)).size, 1);
  assert.deepEqual(results.map((result) => result.deduped).sort(), [
    false,
    true,
  ]);
  assert.equal((await db.collection("paymentIntents").get()).size, 1);

  await assert.rejects(
    createPaymentIntentV2(
      intent({
        expectedAmountMinor: 10_001,
        money: buildMoneySnapshot({
          grossAmountMinor: 10_001,
          platformFeeMinor: 150,
          providerFeeMinor: 390,
        }),
      }),
    ),
    /IDEMPOTENCY_BINDING_MISMATCH/,
  );
});

test("payment-request delivery reserves once, blocks overlap and starts cooldown only after acceptance", async () => {
  await Promise.all([
    db.doc("users/request-merchant").set({ shopName: "Request Shop" }),
    db.doc("users/request-merchant/wallet/current").set({
      virtualBalance: 10,
    }),
    db.doc("users/request-merchant/customers/request-customer").set({
      name: "Thandi",
      number: "0821234567",
      balance: -90,
    }),
  ]);
  const deliveryPhone = "+27821234567";
  const quote = {
    merchantId: "request-merchant",
    customerId: "request-customer",
    customerName: "Thandi",
    shopName: "Request Shop",
    deliveryPhone,
    phoneLast4: "4567",
    phoneFingerprint: createHash("sha256").update(deliveryPhone).digest("hex"),
    outstandingAmountMinor: 9_000,
    mode: "whatsapp_online",
    expectedChannel: "whatsapp",
    messageCostMinor: 85,
    whatsappCostMinor: 85,
    smsCostMinor: 120,
    reservationAmountMinor: 120,
    walletBalanceMinor: 1_000,
    onlinePaymentsReady: true,
    messagePreview: "Hi Thandi, your balance is R90,00.",
    smsPreview: "Hi Thandi, your balance is R90,00.",
    quoteKey: "quote-request-1",
    pricingVersion: "pricing-request-1",
    canRequest: true,
    reason: "ready",
    cooldownEndsAtMs: 0,
    lastRequest: null,
  };
  const [first, replay] = await Promise.all([
    reserveCustomerPaymentRequest({
      quote,
      idempotencyKey: "same-send",
      initiatedBy: "merchant-user",
    }),
    reserveCustomerPaymentRequest({
      quote,
      idempotencyKey: "same-send",
      initiatedBy: "merchant-user",
    }),
  ]);
  assert.equal(first.requestId, replay.requestId);
  assert.deepEqual([first.deduped, replay.deduped].sort(), [false, true]);
  assert.equal(
    (await db.doc("users/request-merchant/wallet/current").get()).get(
      "virtualBalance",
    ),
    8.8,
  );
  await assert.rejects(
    reserveCustomerPaymentRequest({
      quote,
      idempotencyKey: "overlapping-send",
      initiatedBy: "merchant-user",
    }),
    /REQUEST_IN_PROGRESS/,
  );

  await recordAcceptedCustomerPaymentRequest({
    requestId: first.requestId,
    channel: "whatsapp",
    providerMessageId: "bp-conversation-1",
  });
  await recordAcceptedCustomerPaymentRequest({
    requestId: first.requestId,
    channel: "whatsapp",
    providerMessageId: "late-duplicate",
  });
  const request = await db
    .doc(`customerPaymentRequests/${first.requestId}`)
    .get();
  assert.equal(request.get("status"), "sent");
  assert.equal(request.get("providerMessageId"), "bp-conversation-1");
  assert.equal(request.get("actualMessageCostMinor"), 85);
  assert.equal(
    (await db.doc("users/request-merchant/wallet/current").get()).get(
      "virtualBalance",
    ),
    9.15,
  );
  const states = await db.collection("customerPaymentRequestState").get();
  assert.equal(states.size, 1);
  assert.equal(states.docs[0].get("activeRequestId"), undefined);
  assert.ok(states.docs[0].get("cooldownEndsAt").toMillis() > Date.now());
  await assert.rejects(
    reserveCustomerPaymentRequest({
      quote,
      idempotencyKey: "during-cooldown",
      initiatedBy: "merchant-user",
    }),
    /COOLDOWN_ACTIVE/,
  );

  await db
    .doc("users/request-merchant/customers/review-customer")
    .set({ name: "Lebo", number: "0831234567", balance: -40 });
  const reviewQuote = {
    ...quote,
    customerId: "review-customer",
    customerName: "Lebo",
    deliveryPhone: "+27831234567",
    phoneFingerprint: createHash("sha256").update("+27831234567").digest("hex"),
    outstandingAmountMinor: 4_000,
    quoteKey: "quote-request-review",
  };
  const review = await reserveCustomerPaymentRequest({
    quote: reviewQuote,
    idempotencyKey: "review-send",
    initiatedBy: "merchant-user",
  });
  await db.doc(`customerPaymentRequests/${review.requestId}`).update({
    status: "needs_review",
    operationsOwner: "operations",
  });
  await releaseReviewedCustomerPaymentRequest(
    review.requestId,
    "PROVIDER_CASE_123_CONFIRMED_NOT_DELIVERED",
  );
  await releaseReviewedCustomerPaymentRequest(
    review.requestId,
    "PROVIDER_CASE_123_CONFIRMED_NOT_DELIVERED",
  );
  assert.equal(
    (await db.doc(`customerPaymentRequests/${review.requestId}`).get()).get(
      "status",
    ),
    "failed",
  );
  const reviewedReservation = await db
    .doc(`paymentRequestWalletReservations/${review.requestId}`)
    .get();
  assert.equal(reviewedReservation.get("status"), "released");
  assert.equal(reviewedReservation.get("refundedMinor"), 120);
  assert.equal(
    (await db.doc("users/request-merchant/wallet/current").get()).get(
      "virtualBalance",
    ),
    9.15,
  );
});

test("provider replay deduplicates and altered payload collides", async () => {
  const event = {
    provider: "paystack",
    providerEventId: "evt-1",
    eventType: "charge.success",
    reference: "ref-1",
    rawBody: Buffer.from('{"event":"charge.success"}'),
  };
  const first = await recordProviderEventV2(event);
  const replay = await recordProviderEventV2(event);
  assert.equal(first.eventId, replay.eventId);
  assert.equal(first.deduped, false);
  assert.equal(replay.deduped, true);
  await assert.rejects(
    recordProviderEventV2({
      ...event,
      rawBody: Buffer.from('{"event":"charge.success","amount":1}'),
    }),
    /PROVIDER_EVENT_COLLISION/,
  );
  assert.equal((await db.collection("paymentEvents").get()).size, 1);

  const fallback = {
    provider: "paystack",
    eventType: "charge.success",
    reference: "ref-without-provider-event-id",
    rawBody: Buffer.from('{"event":"charge.success","amount":10000}'),
  };
  await recordProviderEventV2(fallback);
  await assert.rejects(
    recordProviderEventV2({
      ...fallback,
      rawBody: Buffer.from('{"event":"charge.success","amount":9999}'),
    }),
    /PROVIDER_EVENT_COLLISION/,
  );
  assert.equal((await db.collection("paymentEvents").get()).size, 2);
});

test("event application is exactly once and state never regresses", async () => {
  const created = await createPaymentIntentV2(
    intent({ idempotencyKey: "checkout-transition" }),
  );
  const paid = await transitionPaymentIntentV2({
    intentId: created.intentId,
    nextStatus: "paid",
    providerEventId: "evt-paid-1",
    providerReference: "ref-paid-1",
    providerAmountMinor: 10_000,
    providerFeeMinor: 0,
  });
  assert.equal(paid.deduped, false);
  const replay = await transitionPaymentIntentV2({
    intentId: created.intentId,
    nextStatus: "paid",
    providerEventId: "evt-paid-1",
    providerReference: "ref-paid-1",
    providerAmountMinor: 10_000,
  });
  assert.equal(replay.deduped, true);
  await assert.rejects(
    transitionPaymentIntentV2({
      intentId: created.intentId,
      nextStatus: "failed",
      providerEventId: "evt-failed-late",
    }),
    /PAYMENT_TRANSITION_INVALID/,
  );
  await assert.rejects(
    transitionPaymentIntentV2({
      intentId: created.intentId,
      nextStatus: "refund_pending",
      providerEventId: "evt-refund",
      providerAmountMinor: 9_999,
    }),
    /PROVIDER_AMOUNT_MISMATCH/,
  );

  const saved = (
    await db.doc(`paymentIntents/${created.intentId}`).get()
  ).data();
  assert.equal(saved.status, "paid");
  assert.equal(saved.providerReference, "ref-paid-1");
  assert.equal(saved.providerFeeMinor, 0);
  assert.deepEqual(saved.appliedProviderEventIds, ["evt-paid-1"]);
});

test("refunds stay pending until exact provider confirmation", async () => {
  const created = await createPaymentIntentV2(
    intent({ idempotencyKey: "checkout-refund" }),
  );
  await transitionPaymentIntentV2({
    intentId: created.intentId,
    nextStatus: "paid",
    providerEventId: "evt-refund-paid",
    providerReference: "ref-refund-paid",
    providerAmountMinor: 10_000,
  });
  await db.doc("commerceOrders/order-refund").set({
    status: "cancelled",
    paymentStatus: "refund_pending",
    payment: { provider: "paystack", reference: "ref-refund-paid" },
  });
  const firstCase = await requestRefundCaseV2({
    intentId: created.intentId,
    idempotencyKey: "partial-1",
    refundAmountMinor: 4_000,
    reason: "Partial item refund",
    owner: "operations",
    commerceOrderId: "order-refund",
  });
  const pending = (
    await db.doc(`paymentIntents/${created.intentId}`).get()
  ).data();
  assert.equal(pending.status, "refund_pending");
  assert.equal(pending.refundProviderConfirmed, false);
  assert.equal(
    (await db.doc("commerceOrders/order-refund").get()).get("paymentStatus"),
    "refund_pending",
  );
  await assert.rejects(
    confirmProviderRefundV2({
      refundCaseId: firstCase.refundCaseId,
      providerRefundId: "refund-1",
      providerReference: "ref-refund-paid",
      providerStatus: "pending",
      providerAmountMinor: 4_000,
    }),
    /REFUND_NOT_PROVIDER_CONFIRMED/,
  );
  const partial = await confirmProviderRefundV2({
    refundCaseId: firstCase.refundCaseId,
    providerRefundId: "refund-1",
    providerReference: "ref-refund-paid",
    providerStatus: "processed",
    providerAmountMinor: 4_000,
  });
  assert.deepEqual(partial, { deduped: false, fullRefund: false });
  assert.equal(
    (await db.doc("commerceOrders/order-refund").get()).get("paymentStatus"),
    "refund_pending",
  );
  const replay = await confirmProviderRefundV2({
    refundCaseId: firstCase.refundCaseId,
    providerRefundId: "refund-1",
    providerReference: "ref-refund-paid",
    providerStatus: "success",
    providerAmountMinor: 4_000,
  });
  assert.deepEqual(replay, { deduped: true, fullRefund: false });

  const finalCase = await requestRefundCaseV2({
    intentId: created.intentId,
    idempotencyKey: "final-1",
    refundAmountMinor: 6_000,
    reason: "Complete refund",
    owner: "operations",
    commerceOrderId: "order-refund",
  });
  const full = await confirmProviderRefundV2({
    refundCaseId: finalCase.refundCaseId,
    providerRefundId: "refund-2",
    providerReference: "ref-refund-paid",
    providerStatus: "processed",
    providerAmountMinor: 6_000,
  });
  assert.deepEqual(full, { deduped: false, fullRefund: true });
  const refundedIntent = (
    await db.doc(`paymentIntents/${created.intentId}`).get()
  ).data();
  assert.equal(refundedIntent.status, "refunded");
  assert.equal(refundedIntent.confirmedRefundMinor, 10_000);
  assert.equal(refundedIntent.refundProviderConfirmed, true);
  const refundedOrder = (
    await db.doc("commerceOrders/order-refund").get()
  ).data();
  assert.equal(refundedOrder.status, "refunded");
  assert.equal(refundedOrder.paymentStatus, "refunded");
  assert.equal(refundedOrder.refund.providerConfirmed, true);

  const requestReplay = await requestRefundCaseV2({
    intentId: created.intentId,
    idempotencyKey: "final-1",
    refundAmountMinor: 6_000,
    reason: "Complete refund",
    owner: "operations",
    commerceOrderId: "order-refund",
  });
  assert.deepEqual(requestReplay, {
    refundCaseId: finalCase.refundCaseId,
    deduped: true,
  });

  const otherIntent = await createPaymentIntentV2(
    intent({ idempotencyKey: "checkout-other-refund" }),
  );
  await transitionPaymentIntentV2({
    intentId: otherIntent.intentId,
    nextStatus: "paid",
    providerEventId: "evt-other-refund-paid",
    providerReference: "ref-other-refund-paid",
    providerAmountMinor: 10_000,
  });
  const otherCase = await requestRefundCaseV2({
    intentId: otherIntent.intentId,
    idempotencyKey: "other-full",
    refundAmountMinor: 10_000,
    reason: "Other refund",
    owner: "operations",
  });
  await assert.rejects(
    confirmProviderRefundV2({
      refundCaseId: otherCase.refundCaseId,
      providerRefundId: "refund-2",
      providerReference: "ref-other-refund-paid",
      providerStatus: "processed",
      providerAmountMinor: 10_000,
    }),
    /REFUND_PROVIDER_EVENT_COLLISION/,
  );
});

test("a verified mismatched charge is quarantined and refunded at its actual amount", async () => {
  const created = await createPaymentIntentV2(
    intent({ idempotencyKey: "checkout-provider-amount-mismatch" }),
  );
  const reference = "ref-provider-amount-mismatch";
  await db.doc(`paymentIntents/${created.intentId}`).update({
    status: "initialized",
    previousStatus: "created",
    providerReference: reference,
  });
  const transaction = {
    id: 900001,
    status: "success",
    reference,
    amount: 10_100,
    fees: 400,
    currency: "ZAR",
    channel: "eft",
    metadata: {
      purpose: "merchant_order",
      intentId: created.intentId,
      merchantId: "merchant-1",
      orderId: "sale-1",
    },
  };
  const rawBody = Buffer.from(
    JSON.stringify({ event: "charge.success", data: transaction }),
  );
  const quarantined = await quarantineVerifiedChargeV2({
    transaction,
    rawBody,
    reason: "OWNED_ORDER_PAYMENT_BINDING_MISMATCH",
  });
  const replay = await quarantineVerifiedChargeV2({
    transaction,
    rawBody,
    reason: "OWNED_ORDER_PAYMENT_BINDING_MISMATCH",
  });
  assert.equal(quarantined.intentId, created.intentId);
  assert.equal(quarantined.deduped, false);
  assert.equal(replay.refundCaseId, quarantined.refundCaseId);
  assert.equal(replay.deduped, true);

  const quarantinedIntent = (
    await db.doc(`paymentIntents/${created.intentId}`).get()
  ).data();
  assert.equal(quarantinedIntent.status, "refund_pending");
  assert.equal(quarantinedIntent.expectedAmountMinor, 10_000);
  assert.equal(quarantinedIntent.providerAmountMinor, 10_100);
  assert.equal(quarantinedIntent.requestedRefundMinor, 10_100);
  assert.equal(
    (await db.doc(`refundCases/${quarantined.refundCaseId}`).get()).get(
      "refundAmountMinor",
    ),
    10_100,
  );

  const confirmed = await confirmProviderRefundV2({
    refundCaseId: quarantined.refundCaseId,
    providerRefundId: "refund-provider-amount-mismatch",
    providerReference: reference,
    providerStatus: "processed",
    providerAmountMinor: 10_100,
  });
  assert.deepEqual(confirmed, { deduped: false, fullRefund: true });
  assert.equal(
    (await db.doc(`paymentIntents/${created.intentId}`).get()).get("status"),
    "refunded",
  );
});

test("campaign top-up credits exactly once and refund reverses the purchase", async () => {
  const quote = quoteCampaignTopup({
    creditAmountMinor: 10_000,
    channel: "eft",
  });
  const created = await createPaymentIntentV2({
    merchantId: "merchant-campaign",
    purpose: "campaign_credit",
    idempotencyKey: "campaign-credit-checkout",
    expectedAmountMinor: quote.totalChargeMinor,
    businessBinding: {
      type: "campaign_wallet",
      id: "merchant-campaign",
    },
    money: buildMoneySnapshot({
      grossAmountMinor: quote.totalChargeMinor,
      platformFeeMinor: 0,
      providerFeeMinor: quote.providerFeeMinor,
    }),
  });
  const reference = "p2-campaign-topup";
  await db.doc(`paymentIntents/${created.intentId}`).update({
    status: "initialized",
    previousStatus: "created",
    providerReference: reference,
    selectedChannel: "eft",
    campaignCreditAmountMinor: quote.creditAmountMinor,
    campaignWalletStoreId: "merchant-campaign",
    campaignWalletShared: false,
  });
  await db.doc("users/merchant-campaign/wallet/current").set({
    virtualBalance: 0,
  });
  const transaction = {
    id: 987654,
    status: "success",
    reference,
    amount: quote.totalChargeMinor,
    fees: quote.providerFeeMinor,
    currency: "ZAR",
    channel: "eft",
    metadata: {
      purpose: "campaign_credit",
      intentId: created.intentId,
      merchantId: "merchant-campaign",
      walletStoreId: "merchant-campaign",
      creditAmountMinor: quote.creditAmountMinor,
      selectedChannel: "eft",
      initiatedBy: "merchant-campaign",
    },
  };
  const rawBody = Buffer.from(
    JSON.stringify({
      event: "charge.success",
      data: transaction,
    }),
  );
  const first = await applyVerifiedCampaignTopupV2(transaction, rawBody);
  const replay = await applyVerifiedCampaignTopupV2(transaction, rawBody);
  assert.deepEqual(first, { deduped: false, intentId: created.intentId });
  assert.deepEqual(replay, { deduped: true, intentId: created.intentId });
  assert.equal(
    (await db.doc("users/merchant-campaign/wallet/current").get()).get(
      "virtualBalance",
    ),
    100,
  );
  assert.equal(
    (await db.doc(`campaignCreditPurchases/${created.intentId}`).get()).get(
      "creditAmountMinor",
    ),
    10_000,
  );

  const refund = await requestRefundCaseV2({
    intentId: created.intentId,
    idempotencyKey: "campaign-credit-full-refund",
    refundAmountMinor: quote.totalChargeMinor,
    reason: "Internal refund drill",
    owner: "operations",
  });
  const confirmed = await confirmProviderRefundV2({
    refundCaseId: refund.refundCaseId,
    providerRefundId: "campaign-refund-1",
    providerReference: reference,
    providerStatus: "processed",
    providerAmountMinor: quote.totalChargeMinor,
  });
  assert.deepEqual(confirmed, { deduped: false, fullRefund: true });
  assert.equal(
    (await db.doc("users/merchant-campaign/wallet/current").get()).get(
      "virtualBalance",
    ),
    0,
  );
  assert.equal(
    (await db.doc(`campaignCreditPurchases/${created.intentId}`).get()).get(
      "refundedCreditMinor",
    ),
    10_000,
  );
});

test("owned stock is reserved before payment and never decremented twice", async () => {
  const merchantId = "merchant-owned";
  const orderId = "owned-order-1";
  await db.doc(`users/${merchantId}`).set({
    name: "Owned Stock Merchant",
    unreadCount: 0,
  });
  await db.doc(`users/${merchantId}/products/product-1`).set({
    name: "Reserved product",
    sellingPrice: 50,
    quantity: 5,
  });
  await db.doc(`users/${merchantId}/sales/${orderId}`).set({
    id: orderId,
    customerId: "customer-1",
    paymentRail: "paystack_v2",
    paymentStatus: "pending",
    status: "pending_payment",
    amount: 100,
    products: { "product-1": 2 },
    items: [
      {
        productId: "product-1",
        quantity: 2,
        details: { sellingPrice: 50, price: 50 },
      },
    ],
    inventoryFinalized: false,
  });
  await db.doc(`users/${merchantId}/customers/customer-1`).set({
    name: "Customer",
    number: "",
  });
  const reserved = await reserveOwnedInventoryForSale({ merchantId, orderId });
  assert.equal(reserved.deduped, false);
  assert.equal(
    (await db.doc(`users/${merchantId}/products/product-1`).get()).get(
      "quantity",
    ),
    3,
  );
  assert.equal(
    (await db.doc(`inventoryReservations/${reserved.reservationId}`).get()).get(
      "inventorySnapshotVersion",
    ),
    1,
  );
  assert.deepEqual(
    (await db.doc(`inventoryReservations/${reserved.reservationId}`).get()).get(
      "items",
    ),
    [
      {
        productId: "product-1",
        quantity: 2,
        unitAmountMinor: 5_000,
        availableBefore: 5,
        availableAfter: 3,
      },
    ],
  );
  assert.deepEqual(
    await reserveOwnedInventoryForSale({ merchantId, orderId }),
    { reservationId: reserved.reservationId, deduped: true },
  );

  const providerFeeMinor = estimatedOwnedOrderProviderFeeMinor({
    amountMinor: 10_000,
    channel: "card",
  });
  const created = await createPaymentIntentV2({
    merchantId,
    purpose: "merchant_order",
    idempotencyKey: `owned-order:${orderId}`,
    expectedAmountMinor: 10_000,
    businessBinding: { type: "owned_order", id: orderId },
    money: buildMoneySnapshot({
      grossAmountMinor: 10_000,
      platformFeeMinor: 150,
      providerFeeMinor,
    }),
  });
  const reference = "p2-owned-order";
  await db.doc(`paymentIntents/${created.intentId}`).update({
    status: "initialized",
    previousStatus: "created",
    providerReference: reference,
    selectedChannel: "card",
    inventoryReservationId: reserved.reservationId,
    paystackSubaccountCode: "ACCT_testmerchant",
    settlementDestination: {
      bankName: "Test Bank",
      accountName: "Merchant",
      accountLast4: "1234",
    },
  });
  await db.doc(`inventoryReservations/${reserved.reservationId}`).update({
    paymentIntentId: created.intentId,
    providerReference: reference,
  });
  const transaction = {
    id: 987655,
    status: "success",
    reference,
    amount: 10_000,
    fees: 449,
    currency: "ZAR",
    channel: "card",
    metadata: {
      purpose: "merchant_order",
      intentId: created.intentId,
      merchantId,
      orderId,
      reservationId: reserved.reservationId,
      selectedChannel: "card",
    },
  };
  const rawBody = Buffer.from(
    JSON.stringify({
      event: "charge.success",
      data: transaction,
    }),
  );
  const applied = await applyVerifiedOwnedOrderPaymentV2(transaction, rawBody);
  assert.equal(applied.deduped, false);
  const replay = await applyVerifiedOwnedOrderPaymentV2(transaction, rawBody);
  assert.equal(replay.deduped, true);
  assert.equal(
    (await db.doc(`inventoryReservations/${reserved.reservationId}`).get()).get(
      "status",
    ),
    "committed",
  );
  assert.equal(
    (await db.doc(`users/${merchantId}/sales/${orderId}`).get()).get(
      "paymentStatus",
    ),
    "paid",
  );
  assert.equal((await db.collection("settlements").get()).size, 1);
  assert.equal(
    (await db.collection("settlements").limit(1).get()).docs[0].get(
      "merchantNetProceedsMinor",
    ),
    9_401,
  );
  await assert.rejects(
    releaseOwnedInventoryReservation({
      reservationId: reserved.reservationId,
      reason: "late_cancel",
    }),
    /RESERVATION_NOT_RELEASABLE/,
  );
  const consumed = await consumeOwnedInventoryReservation({
    reservationId: reserved.reservationId,
    merchantId,
    orderId,
  });
  assert.deepEqual(consumed, { deduped: false });
  assert.deepEqual(
    await consumeOwnedInventoryReservation({
      reservationId: reserved.reservationId,
      merchantId,
      orderId,
    }),
    { deduped: true },
  );
  assert.equal(
    (await db.doc(`users/${merchantId}/products/product-1`).get()).get(
      "quantity",
    ),
    3,
  );
});

test("account settlement projects one verified payment and one refund reversal", async () => {
  const merchantId = "merchant-account";
  const customerId = "customer-account";
  await db.doc(`users/${merchantId}/customers/${customerId}`).set({
    name: "Account Customer",
    number: "",
    balance: -100,
  });
  const created = await createPaymentIntentV2({
    merchantId,
    purpose: "account_settlement",
    idempotencyKey: "account-payment-1",
    expectedAmountMinor: 4_000,
    businessBinding: { type: "customer_account", id: customerId },
    money: buildMoneySnapshot({
      grossAmountMinor: 4_000,
      platformFeeMinor: 60,
      providerFeeMinor: 92,
    }),
  });
  const reference = "p2-account-settlement";
  await db.doc(`paymentIntents/${created.intentId}`).update({
    status: "initialized",
    previousStatus: "created",
    providerReference: reference,
    selectedChannel: "eft",
    customerId,
    repaymentPlanId: null,
    paystackSubaccountCode: "ACCT_accountmerchant",
    settlementDestination: {
      bankName: "Test Bank",
      accountName: "Merchant",
      accountLast4: "9876",
    },
  });
  const transaction = {
    id: 987656,
    status: "success",
    reference,
    amount: 4_000,
    fees: 92,
    currency: "ZAR",
    channel: "eft",
    metadata: {
      purpose: "account_settlement",
      intentId: created.intentId,
      merchantId,
      customerId,
      repaymentPlanId: null,
      selectedChannel: "eft",
    },
  };
  const rawBody = Buffer.from(
    JSON.stringify({
      event: "charge.success",
      data: transaction,
    }),
  );
  const applied = await applyVerifiedAccountSettlementV2(transaction, rawBody);
  assert.equal(applied.deduped, false);
  assert.equal(applied.transactionId, `paystack_${created.intentId}`);
  const replay = await applyVerifiedAccountSettlementV2(transaction, rawBody);
  assert.equal(replay.deduped, true);
  const payments = await db
    .collection(`users/${merchantId}/customers/${customerId}/transactions`)
    .get();
  assert.equal(payments.size, 1);
  assert.equal(payments.docs[0].get("amountMinor"), 4_000);
  assert.equal(payments.docs[0].get("source"), "paystack_v2");

  const refund = await requestRefundCaseV2({
    intentId: created.intentId,
    idempotencyKey: "account-payment-refund",
    refundAmountMinor: 4_000,
    reason: "Account payment refund drill",
    owner: "operations",
  });
  await confirmProviderRefundV2({
    refundCaseId: refund.refundCaseId,
    providerRefundId: "account-refund-1",
    providerReference: reference,
    providerStatus: "processed",
    providerAmountMinor: 4_000,
  });
  const transactions = await db
    .collection(`users/${merchantId}/customers/${customerId}/transactions`)
    .get();
  assert.equal(transactions.size, 2);
  const reversal = transactions.docs.find(
    (doc) => doc.get("source") === "paystack_refund_v2",
  );
  assert.ok(reversal);
  assert.equal(reversal.get("type"), "Credit");
  assert.equal(reversal.get("amountMinor"), 4_000);
});

test("repayment installments advance and complete the active plan exactly once", async () => {
  const merchantId = "merchant-repayment";
  const customerId = "customer-repayment";
  const planId = "repayment-plan-1";
  const firstDueAtMs = Date.now() + 24 * 60 * 60 * 1000;
  const customerRef = db.doc(`users/${merchantId}/customers/${customerId}`);
  const planRef = db.doc(`repaymentPlans/${planId}`);
  await customerRef.set({
    name: "Repayment Customer",
    number: "",
    balance: -100,
    activeRepaymentPlanId: planId,
  });
  await planRef.set({
    planId,
    merchantId,
    customerId,
    totalAmountMinor: 5_000,
    paidAmountMinor: 0,
    remainingAmountMinor: 5_000,
    installmentAmountMinor: 4_000,
    cadence: "weekly",
    cadenceDays: 7,
    nextDueAt: admin.firestore.Timestamp.fromMillis(firstDueAtMs),
    completedInstallments: 0,
    status: "active",
  });

  async function applyInstallment(sequence, amountMinor) {
    const created = await createPaymentIntentV2({
      merchantId,
      purpose: "repayment_installment",
      idempotencyKey: `repayment-payment-${sequence}`,
      expectedAmountMinor: amountMinor,
      businessBinding: { type: "repayment_installment", id: planId },
      money: buildMoneySnapshot({
        grossAmountMinor: amountMinor,
        platformFeeMinor: 0,
        providerFeeMinor: 0,
      }),
    });
    const reference = `p2-repayment-${sequence}`;
    await db.doc(`paymentIntents/${created.intentId}`).update({
      status: "initialized",
      previousStatus: "created",
      providerReference: reference,
      selectedChannel: "qr",
      customerId,
      repaymentPlanId: planId,
      paymentRequestId: null,
      providerMode: "test",
      paystackSubaccountCode: "ACCT_repaymentmerchant",
      settlementDestination: {
        bankName: "Test Bank",
        accountName: "Merchant",
        accountLast4: "9876",
      },
    });
    const transaction = {
      id: 990000 + sequence,
      status: "success",
      reference,
      amount: amountMinor,
      fees: 0,
      currency: "ZAR",
      channel: "qr",
      metadata: {
        purpose: "repayment_installment",
        intentId: created.intentId,
        merchantId,
        customerId,
        repaymentPlanId: planId,
        paymentRequestId: null,
        selectedChannel: "qr",
      },
    };
    const rawBody = Buffer.from(
      JSON.stringify({ event: "charge.success", data: transaction }),
    );
    const applied = await applyVerifiedAccountSettlementV2(
      transaction,
      rawBody,
    );
    assert.equal(applied.deduped, false);
    assert.equal(
      (await applyVerifiedAccountSettlementV2(transaction, rawBody)).deduped,
      true,
    );
  }

  await applyInstallment(1, 4_000);
  const activePlan = await planRef.get();
  assert.equal(activePlan.get("remainingAmountMinor"), 1_000);
  assert.equal(activePlan.get("paidAmountMinor"), 4_000);
  assert.equal(activePlan.get("completedInstallments"), 1);
  assert.equal(activePlan.get("status"), "active");
  assert.equal(
    activePlan.get("nextDueAt").toMillis(),
    firstDueAtMs + 7 * 24 * 60 * 60 * 1000,
  );
  assert.equal((await customerRef.get()).get("activeRepaymentPlanId"), planId);

  await applyInstallment(2, 1_000);
  const completedPlan = await planRef.get();
  assert.equal(completedPlan.get("remainingAmountMinor"), 0);
  assert.equal(completedPlan.get("paidAmountMinor"), 5_000);
  assert.equal(completedPlan.get("completedInstallments"), 2);
  assert.equal(completedPlan.get("status"), "completed");
  assert.equal(
    (await customerRef.get()).get("activeRepaymentPlanId"),
    undefined,
  );
});

test("supplier payment creates exactly one queued CJ fulfilment", async () => {
  const merchantId = "merchant-supplier";
  const orderId = "supplier-order-1";
  const economics = supplierPaymentEconomics({
    landedCostMinor: 8_000,
    markupMinor: 2_000,
    safetyMarginMinor: 100,
  });
  await db.doc(`commerceOrders/${orderId}`).set({
    sellerId: merchantId,
    customerId: "supplier-customer",
    supplierId: "cj_dropshipping",
    supplierProductId: "cj-product",
    supplierVariantId: "cj-variant",
    supplierProductCostUsdMinor: 300,
    supplierShippingCostUsdMinor: 200,
    sourceCountryCode: "CN",
    logisticName: "CJPacket",
    amountDueMinor: economics.customerTotalMinor,
    safetyMarginMinor: 100,
    status: "pending_payment",
    paymentStatus: "pending",
    requestedPaymentChannel: "eft",
    quantity: 1,
    payment: {
      provider: "paystack",
      reference: "p2-supplier-order",
      channel: "eft",
    },
    deliveryAddress: {
      postalCode: "2000",
      province: "Gauteng",
      city: "Johannesburg",
      line1: "1 Test Street",
      line2: "",
    },
    buyer: {
      name: "Supplier Customer",
      phone: "+27820000000",
      email: "customer@example.com",
    },
  });
  const created = await createPaymentIntentV2({
    merchantId,
    purpose: "supplier_order",
    idempotencyKey: `supplier-order:${orderId}`,
    expectedAmountMinor: economics.customerTotalMinor,
    businessBinding: { type: "supplier_order", id: orderId },
    money: economics.money,
  });
  await db.doc(`paymentIntents/${created.intentId}`).update({
    status: "initialized",
    previousStatus: "created",
    providerReference: "p2-supplier-order",
    selectedChannel: "eft",
    paystackSubaccountCode: "ACCT_suppliermerchant",
    settlementDestination: {
      bankName: "Test Bank",
      accountName: "Merchant",
      accountLast4: "4321",
    },
  });
  const transaction = {
    id: 987657,
    status: "success",
    reference: "p2-supplier-order",
    amount: economics.customerTotalMinor,
    fees: economics.estimatedProviderFeeMinor,
    currency: "ZAR",
    channel: "eft",
    metadata: {
      purpose: "supplier_order",
      intentId: created.intentId,
      orderId,
      sellerId: merchantId,
      selectedChannel: "eft",
    },
  };
  const rawBody = Buffer.from(
    JSON.stringify({
      event: "charge.success",
      data: transaction,
    }),
  );
  const first = await applyVerifiedSupplierPaymentV2(transaction, rawBody);
  const replay = await applyVerifiedSupplierPaymentV2(transaction, rawBody);
  assert.equal(first.deduped, false);
  assert.equal(replay.deduped, true);
  const fulfilments = await db.collection("supplierFulfilments").get();
  assert.equal(fulfilments.size, 1);
  assert.equal(fulfilments.docs[0].get("status"), "queued");
  assert.equal(
    (await db.doc(`commerceOrders/${orderId}`).get()).get("paymentStatus"),
    "paid",
  );
});

test("concurrent supplier funding reservations cannot overcommit CJ balance", async () => {
  const originalAdapter = axios.defaults.adapter;
  process.env.SPAZAONE_ENVIRONMENT = "local";
  process.env.CJ_API_KEY = "emulator-cj-api-key";
  process.env.CJ_SANDBOX_MODE = "true";
  process.env.CJ_SANDBOX_FUNDING_CAPACITY_USD_MINOR = "1000";
  axios.defaults.adapter = async (config) => {
    const url = String(config.url ?? "");
    if (url.includes("/authentication/getAccessToken")) {
      return {
        data: {
          result: true,
          data: {
            accessToken: "emulator-cj-access-token",
            accessTokenExpiryDate: "2099-01-01T00:00:00.000Z",
          },
        },
        status: 200,
        statusText: "OK",
        headers: {},
        config,
      };
    }
    throw new Error(`Unexpected CJ test request: ${url}`);
  };
  try {
    const attempts = await Promise.allSettled([
      reserveSupplierFunding({
        orderId: "funding-order-a",
        intentId: "funding-intent-a",
        requiredUsdMinor: 600,
      }),
      reserveSupplierFunding({
        orderId: "funding-order-b",
        intentId: "funding-intent-b",
        requiredUsdMinor: 600,
      }),
    ]);
    const fulfilled = attempts.filter(
      (result) => result.status === "fulfilled",
    );
    const rejected = attempts.filter((result) => result.status === "rejected");
    assert.equal(fulfilled.length, 1);
    assert.equal(rejected.length, 1);
    assert.match(String(rejected[0].reason), /CJ_BALANCE_INSUFFICIENT/);
    assert.equal(
      (await db.doc("supplierFundingState/cj").get()).get(
        "outstandingUsdMinor",
      ),
      600,
    );
    const alerts = await db
      .collection("operationsAlerts")
      .where("type", "==", "supplier_funding_insufficient")
      .get();
    assert.equal(alerts.size, 1);
    assert.equal(alerts.docs[0].get("owner"), "operations");
    assert.equal(alerts.docs[0].get("requiredUsdMinor"), 600);
    assert.equal(alerts.docs[0].get("availableUsdMinor"), 400);
    const reservationId = fulfilled[0].value.reservationId;
    assert.equal(await consumeSupplierFunding(reservationId), true);
    assert.equal(await consumeSupplierFunding(reservationId), true);
    assert.equal(
      (await db.doc("supplierFundingState/cj").get()).get(
        "outstandingUsdMinor",
      ),
      0,
    );
  } finally {
    axios.defaults.adapter = originalAdapter;
    delete process.env.SPAZAONE_ENVIRONMENT;
    delete process.env.CJ_API_KEY;
    delete process.env.CJ_SANDBOX_MODE;
    delete process.env.CJ_SANDBOX_FUNDING_CAPACITY_USD_MINOR;
  }
});

test("on-demand reconciliation writes one bound operations receipt", async () => {
  await clear();
  const input = {
    windowDays: 30,
    source: "on_demand",
    actorUid: "spaza-admin-emulator",
    operationId: "reconcile-480-emulator",
    reason: "Verify final development candidate",
  };
  const first = await runPaymentsV2Reconciliation(input);
  assert.deepEqual(first, {
    runId: first.runId,
    checkedCount: 0,
    mismatchCount: 0,
    status: "balanced",
    truncated: false,
  });
  assert.deepEqual(await runPaymentsV2Reconciliation(input), first);

  const operations = await db
    .collection("paymentOperations")
    .where("operationId", "==", input.operationId)
    .get();
  assert.equal(operations.size, 1);
  assert.equal(operations.docs[0].get("status"), "completed");
  assert.equal(operations.docs[0].get("type"), "payment_reconciliation");
  assert.equal(operations.docs[0].get("windowDays"), 30);
  assert.equal(operations.docs[0].get("reconciliation.status"), "balanced");

  await assert.rejects(
    runPaymentsV2Reconciliation({
      ...input,
      reason: "Attempt to reuse the operation ID",
    }),
    /RECONCILIATION_OPERATION_ID_REUSED/,
  );
});
