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
import { recoverCampaignTopupV2 } from "../lib/payments/v2/campaignTopupRecovery.js";
import {
  applyVerifiedOwnedOrderPaymentV2,
  estimatedOwnedOrderProviderFeeMinor,
  handleCreateOwnedOrderPaymentV2,
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
import { upsertSettlementAuthorizationRequest } from "../lib/payments/v2/settlementAdminRequests.js";
import { monitorStalePaymentIntents } from "../lib/payments/v2/paymentIntentMonitoring.js";

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
    "paymentRecoveryOperations",
    "paymentAdministrationRequests",
    "paymentOperationsNotifications",
    "paymentMonitoringIncidents",
    "paymentConfiguration",
    "merchantPaymentProfiles",
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

test("settlement requests create one durable operations alert per real refresh", async () => {
  const base = {
    merchantId: "merchant-alert",
    bankingDetailsId: "banking-alert",
    bankingDetailsUpdatedAtMs: 1_000,
    storeName: "Alert Store",
    bankName: "Example Bank",
    accountNumber: "1234567890",
    maskedAccountHolder: "A*** Z***",
    reasonCode: "MERCHANT_REQUESTED",
  };
  const first = await upsertSettlementAuthorizationRequest(base);
  const requestRef = db.doc(`paymentAdministrationRequests/${first.requestId}`);
  const requestBeforeReplay = await requestRef.get();
  assert.equal(first.deduped, false);
  assert.equal(
    (await db.collection("paymentOperationsNotifications").get()).size,
    1,
  );

  const replay = await upsertSettlementAuthorizationRequest(base);
  const requestAfterReplay = await requestRef.get();
  assert.equal(replay.deduped, true);
  assert.equal(
    requestAfterReplay.get("requestedAt").toMillis(),
    requestBeforeReplay.get("requestedAt").toMillis(),
  );
  assert.equal(
    (await db.collection("paymentOperationsNotifications").get()).size,
    1,
  );

  const refreshed = await upsertSettlementAuthorizationRequest({
    ...base,
    bankingDetailsUpdatedAtMs: 2_000,
  });
  assert.equal(refreshed.deduped, false);
  const alerts = await db.collection("paymentOperationsNotifications").get();
  assert.equal(alerts.size, 2);
  for (const alert of alerts.docs) {
    assert.equal(alert.get("pushDeliveryState"), "pending");
    assert.equal(alert.get("route"), "https://workspace.spazaone.com/");
    assert.equal(alert.get("merchantId"), undefined);
    assert.equal(alert.get("bankName"), undefined);
    assert.equal(alert.get("bankingDetailsId"), undefined);
  }
});

test("stale initialized payments alert once and resolve without financial mutation", async () => {
  const nowMs = 1_000_000;
  const staleIntentId = `pi_${"a".repeat(64)}`;
  const recentIntentId = `pi_${"b".repeat(64)}`;
  const historicalPaidBatch = db.batch();
  for (let index = 0; index < 201; index += 1) {
    historicalPaidBatch.set(
      db.doc(`paymentIntents/historical-paid-${index}`),
      {
        status: "paid",
        initializedAt: admin.firestore.Timestamp.fromMillis(0),
      },
    );
  }
  await historicalPaidBatch.commit();
  await db.doc(`paymentIntents/${staleIntentId}`).set({
    status: "initialized",
    merchantId: "monitor-merchant",
    purpose: "campaign_credit",
    initializedAt: admin.firestore.Timestamp.fromMillis(1),
  });
  await db.doc(`paymentIntents/${recentIntentId}`).set({
    status: "initialized",
    merchantId: "monitor-merchant",
    purpose: "merchant_order",
    initializedAt: admin.firestore.Timestamp.fromMillis(nowMs - 60_000),
  });

  const first = await monitorStalePaymentIntents({ source: "test", nowMs });
  assert.equal(first.checkedCount, 1);
  assert.equal(first.detectedCount, 1);
  assert.equal(first.resolvedCount, 0);
  assert.equal(
    (await db.collection("paymentMonitoringIncidents").get()).size,
    1,
  );
  assert.equal(
    (
      await db
        .collection("paymentOperationsNotifications")
        .where("type", "==", "PAYMENT_INTENT_CONFIRMATION_OVERDUE")
        .get()
    ).size,
    1,
  );

  const replay = await monitorStalePaymentIntents({ source: "test", nowMs });
  assert.equal(replay.detectedCount, 0);
  assert.equal(
    (
      await db
        .collection("paymentOperationsNotifications")
        .where("type", "==", "PAYMENT_INTENT_CONFIRMATION_OVERDUE")
        .get()
    ).size,
    1,
  );

  await db.doc(`paymentIntents/${staleIntentId}`).update({ status: "paid" });
  const resolved = await monitorStalePaymentIntents({ source: "test", nowMs });
  assert.equal(resolved.resolvedCount, 1);
  assert.equal(
    (
      await db.collection("paymentMonitoringIncidents").limit(1).get()
    ).docs[0].get("status"),
    "resolved",
  );
  assert.equal(
    (
      await db
        .collection("paymentOperationsNotifications")
        .where("type", "==", "PAYMENT_INTENT_CONFIRMATION_OVERDUE")
        .get()
    ).size,
    1,
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
  const replayAfterSourceUpgrade = await recordProviderEventV2({
    ...event,
    ingestionSource: "webhook",
  });
  assert.equal(first.eventId, replay.eventId);
  assert.equal(first.deduped, false);
  assert.equal(replay.deduped, true);
  assert.equal(replayAfterSourceUpgrade.deduped, true);
  await assert.rejects(
    recordProviderEventV2({
      ...event,
      ingestionSource: "admin_provider_verify",
    }),
    /PROVIDER_EVENT_COLLISION/,
  );
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

test("admin provider verification recovers one campaign top-up exactly once", async () => {
  const merchantId = "merchant-campaign-recovery";
  const quote = quoteCampaignTopup({
    creditAmountMinor: 20_000,
    channel: "card",
  });
  const created = await createPaymentIntentV2({
    merchantId,
    purpose: "campaign_credit",
    idempotencyKey: "campaign-recovery-checkout",
    expectedAmountMinor: quote.totalChargeMinor,
    businessBinding: { type: "campaign_wallet", id: merchantId },
    money: buildMoneySnapshot({
      grossAmountMinor: quote.totalChargeMinor,
      platformFeeMinor: 0,
      providerFeeMinor: quote.providerFeeMinor,
    }),
  });
  const reference = "p2-campaign-recovery";
  await db.doc(`paymentIntents/${created.intentId}`).update({
    status: "initialized",
    previousStatus: "created",
    provider: "paystack",
    providerReference: reference,
    selectedChannel: "card",
    campaignCreditAmountMinor: quote.creditAmountMinor,
    campaignWalletStoreId: merchantId,
    campaignWalletShared: false,
  });
  await db.doc(`users/${merchantId}/wallet/current`).set({
    virtualBalance: 0,
  });
  const transaction = {
    id: 20810,
    status: "success",
    reference,
    amount: quote.totalChargeMinor,
    fees: quote.providerFeeMinor,
    currency: "ZAR",
    channel: "card",
    paid_at: "2026-08-24T05:09:00.000Z",
    metadata: {
      purpose: "campaign_credit",
      intentId: created.intentId,
      merchantId,
      walletStoreId: merchantId,
      creditAmountMinor: quote.creditAmountMinor,
      selectedChannel: "card",
      initiatedBy: merchantId,
    },
  };
  let verificationCalls = 0;
  const dependencies = {
    nowMs: () => 1_000,
    verifyTransaction: async ({ reference: requestedReference }) => {
      verificationCalls += 1;
      assert.equal(requestedReference, reference);
      return transaction;
    },
  };

  const [first, independentRetry] = await Promise.all([
    recoverCampaignTopupV2(
      {
        intentId: created.intentId,
        operationId: "recover-campaign-op-1",
        reason: "Provider success was not delivered to the webhook.",
        actorUid: "admin-recovery",
      },
      dependencies,
    ),
    recoverCampaignTopupV2(
      {
        intentId: created.intentId,
        operationId: "recover-campaign-op-2",
        reason: "Confirm concurrent recovery remains exact-once.",
        actorUid: "admin-recovery",
      },
      dependencies,
    ),
  ]);
  const replay = await recoverCampaignTopupV2(
    {
      intentId: created.intentId,
      operationId: "recover-campaign-op-1",
      reason: "Provider success was not delivered to the webhook.",
      actorUid: "admin-recovery",
    },
    dependencies,
  );
  await assert.rejects(
    recoverCampaignTopupV2(
      {
        intentId: created.intentId,
        operationId: "recover-campaign-op-1",
        reason: "A changed reason must not rebind the operation.",
        actorUid: "admin-recovery",
      },
      dependencies,
    ),
    /RECOVERY_OPERATION_COLLISION/,
  );
  assert.deepEqual([first.deduped, independentRetry.deduped].sort(), [
    false,
    true,
  ]);
  assert.equal(replay.deduped, true);
  assert.equal(first.eventId, replay.eventId);
  assert.equal(first.eventId, independentRetry.eventId);
  assert.equal(verificationCalls, 2);

  const webhookBody = Buffer.from(
    JSON.stringify({ event: "charge.success", data: transaction }),
  );
  const delayedWebhook = await applyVerifiedCampaignTopupV2(
    transaction,
    webhookBody,
  );
  assert.equal(delayedWebhook.deduped, true);
  assert.equal(
    (await db.doc(`users/${merchantId}/wallet/current`).get()).get(
      "virtualBalance",
    ),
    200,
  );
  assert.equal(
    (await db.collection(`users/${merchantId}/topUpTransactions`).get()).size,
    1,
  );
  const intentAfter = (
    await db.doc(`paymentIntents/${created.intentId}`).get()
  ).data();
  assert.equal(intentAfter.status, "paid");
  assert.equal(intentAfter.appliedProviderEventIds.length, 2);
  const events = await db
    .collection("paymentEvents")
    .where("intentId", "==", created.intentId)
    .get();
  assert.equal(events.size, 2);
  const recoveryEvent = events.docs.find(
    (doc) => doc.get("ingestionSource") === "admin_provider_verify",
  );
  const webhookEvent = events.docs.find(
    (doc) => doc.get("ingestionSource") === "webhook",
  );
  assert.equal(recoveryEvent?.get("processingState"), "applied");
  assert.equal(webhookEvent?.get("processingState"), "deduplicated");
  const recoveryReceipts = await db
    .collection("paymentRecoveryOperations")
    .where("intentId", "==", created.intentId)
    .get();
  assert.deepEqual(
    recoveryReceipts.docs.map((doc) => doc.get("applicationDeduped")).sort(),
    [false, true],
  );
});

test("campaign recovery records a safe failure without crediting", async () => {
  const merchantId = "merchant-campaign-recovery-failed";
  const quote = quoteCampaignTopup({
    creditAmountMinor: 5_000,
    channel: "card",
  });
  const created = await createPaymentIntentV2({
    merchantId,
    purpose: "campaign_credit",
    idempotencyKey: "campaign-recovery-failed-checkout",
    expectedAmountMinor: quote.totalChargeMinor,
    businessBinding: { type: "campaign_wallet", id: merchantId },
    money: buildMoneySnapshot({
      grossAmountMinor: quote.totalChargeMinor,
      platformFeeMinor: 0,
      providerFeeMinor: quote.providerFeeMinor,
    }),
  });
  const reference = "p2-campaign-recovery-failed";
  await db.doc(`paymentIntents/${created.intentId}`).update({
    status: "initialized",
    previousStatus: "created",
    provider: "paystack",
    providerReference: reference,
    selectedChannel: "card",
    campaignCreditAmountMinor: quote.creditAmountMinor,
  });
  await db.doc(`users/${merchantId}/wallet/current`).set({
    virtualBalance: 0,
  });

  await assert.rejects(
    recoverCampaignTopupV2(
      {
        intentId: created.intentId,
        operationId: "recover-campaign-failed-op",
        reason: "Verify that provider failure cannot credit the wallet.",
        actorUid: "admin-recovery",
      },
      {
        nowMs: () => 2_000,
        verifyTransaction: async () => ({
          id: 5000,
          status: "failed",
          reference,
          currency: "ZAR",
        }),
      },
    ),
    /PROVIDER_TRANSACTION_NOT_SUCCESSFUL/,
  );
  assert.equal(
    (await db.doc(`users/${merchantId}/wallet/current`).get()).get(
      "virtualBalance",
    ),
    0,
  );
  assert.equal(
    (await db.doc(`campaignCreditPurchases/${created.intentId}`).get()).exists,
    false,
  );
  const receipt = await db
    .doc("paymentRecoveryOperations/recover-campaign-failed-op")
    .get();
  assert.equal(receipt.get("status"), "failed");
  assert.equal(
    receipt.get("failureCode"),
    "PROVIDER_TRANSACTION_NOT_SUCCESSFUL",
  );
  assert.equal(receipt.get("providerReference"), undefined);
});

test("one owned order opens one hosted link and finalizes once after its verified event", async () => {
  const merchantId = "merchant-owned";
  const orderId = "owned-order-1";
  await db.doc(`users/${merchantId}`).set({
    name: "Owned Stock Merchant",
    unreadCount: 0,
    buildNumber: 88,
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
    type: "Online",
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
  await Promise.all([
    db.doc("paymentConfiguration/global").set(
      {
        emergencySuspended: false,
        capabilities: { merchant_order: true },
        paystackChannels: ["card"],
      },
      { merge: true },
    ),
    db.doc(`merchantPaymentProfiles/${merchantId}`).set({
      status: "enabled",
      bankVerificationStatus: "approved",
      paystackSubaccountCode: "ACCT_testmerchant",
      capabilities: { merchant_order: true },
      bankName: "Test Bank",
      resolvedAccountName: "Merchant",
      accountLast4: "1234",
    }),
    db.doc(`users/${merchantId}/carts/customer-1`).set({
      items: [{ productId: "product-1", quantity: 2 }],
      products: { "product-1": 2 },
      itemsCount: 2,
      subtotal: 100,
      total: 100,
      lock: { saleId: orderId },
    }),
    db
      .doc(`users/${merchantId}/carts/customer-1/items/product-1`)
      .set({ productId: "product-1", quantity: 2 }),
  ]);
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

  const originalAdapter = axios.defaults.adapter;
  const priorEnvironment = process.env.SPAZAONE_ENVIRONMENT;
  const priorMasterEnabled = process.env.PAYMENTS_V2_MASTER_ENABLED;
  const priorPaystackSecret = process.env.PAYSTACK_SECRET_KEY;
  const priorBotToken = process.env.PASELLA_BOT_TOKEN;
  process.env.SPAZAONE_ENVIRONMENT = "local";
  process.env.PAYMENTS_V2_MASTER_ENABLED = "true";
  process.env.PAYSTACK_SECRET_KEY = "sk_test_owned_order_emulator";
  process.env.PASELLA_BOT_TOKEN = "owned-order-bot-token";
  let paystackInitializeCalls = 0;
  let paystackInitializeInput = {};
  axios.defaults.adapter = async (config) => {
    assert.match(String(config.url), /paystack\.co\/transaction\/initialize/);
    paystackInitializeCalls += 1;
    paystackInitializeInput =
      typeof config.data === "string" ? JSON.parse(config.data) : config.data;
    return {
      data: {
        status: true,
        data: {
          authorization_url: "https://paystack.test/owned-order",
          reference: paystackInitializeInput.reference,
        },
      },
      status: 200,
      statusText: "OK",
      headers: {},
      config,
    };
  };
  const request = {
    method: "POST",
    body: {
      merchantId,
      orderId,
      customerId: "customer-1",
      email: "customer@example.test",
      channel: "card",
    },
    get(name) {
      return String(name).toLowerCase() === "x-pasella-bot-token"
        ? "owned-order-bot-token"
        : undefined;
    },
  };
  const responseRecorder = () => ({
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  });
  const prepared = responseRecorder();
  try {
    await handleCreateOwnedOrderPaymentV2(request, prepared);
    assert.equal(prepared.statusCode, 200);
    assert.equal(prepared.body.amountMinor, 10_000);
    assert.equal(
      prepared.body.authorizationUrl,
      "https://paystack.test/owned-order",
    );
    assert.equal(paystackInitializeCalls, 1);
    assert.equal(paystackInitializeInput.amount, 10_000);
    assert.deepEqual(paystackInitializeInput.channels, ["card"]);
    assert.equal(
      paystackInitializeInput.metadata.intentId,
      prepared.body.intentId,
    );
    assert.equal(paystackInitializeInput.metadata.orderId, orderId);

    const retried = responseRecorder();
    await handleCreateOwnedOrderPaymentV2(request, retried);
    assert.equal(retried.statusCode, 200);
    assert.equal(retried.body.intentId, prepared.body.intentId);
    assert.equal(retried.body.reference, prepared.body.reference);
    assert.equal(retried.body.deduped, true);
    assert.equal(paystackInitializeCalls, 1);
  } finally {
    axios.defaults.adapter = originalAdapter;
    const restore = (name, value) => {
      if (value == null) delete process.env[name];
      else process.env[name] = value;
    };
    restore("SPAZAONE_ENVIRONMENT", priorEnvironment);
    restore("PAYMENTS_V2_MASTER_ENABLED", priorMasterEnabled);
    restore("PAYSTACK_SECRET_KEY", priorPaystackSecret);
    restore("PASELLA_BOT_TOKEN", priorBotToken);
  }
  const created = { intentId: prepared.body.intentId };
  const reference = prepared.body.reference;
  const intentBeforePayment = await db
    .doc(`paymentIntents/${created.intentId}`)
    .get();
  assert.equal(intentBeforePayment.get("status"), "initialized");
  assert.equal(intentBeforePayment.get("expectedAmountMinor"), 10_000);
  assert.equal(intentBeforePayment.get("selectedChannel"), "card");
  assert.equal(intentBeforePayment.get("businessBinding.id"), orderId);
  assert.equal(
    (await db.doc(`users/${merchantId}/sales/${orderId}`).get()).get(
      "paymentIntentId",
    ),
    created.intentId,
  );
  assert.equal(
    (await db.doc(`inventoryReservations/${reserved.reservationId}`).get()).get(
      "paymentIntentId",
    ),
    created.intentId,
  );
  assert.equal((await db.collection("settlements").get()).size, 0);
  assert.equal(
    (await db.doc(`users/${merchantId}/sales/${orderId}`).get()).get(
      "paymentStatus",
    ),
    "pending",
  );
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
    "consumed",
  );
  assert.equal(
    (await db.doc(`users/${merchantId}/sales/${orderId}`).get()).get(
      "paymentStatus",
    ),
    "paid",
  );
  const ownedSettlements = await db
    .collection("settlements")
    .where("intentId", "==", created.intentId)
    .get();
  assert.equal(ownedSettlements.size, 1);
  assert.equal(
    (
      await db
        .collection("paymentEvents")
        .where("intentId", "==", created.intentId)
        .get()
    ).size,
    1,
  );
  assert.equal(
    (await db.doc(`users/${merchantId}/sales/${orderId}`).get()).get(
      "inventoryFinalized",
    ),
    true,
  );
  assert.equal(
    (await db.doc(`users/${merchantId}/carts/customer-1/items/product-1`).get())
      .exists,
    false,
  );
  const clearedCart = await db
    .doc(`users/${merchantId}/carts/customer-1`)
    .get();
  assert.deepEqual(clearedCart.get("items"), []);
  assert.deepEqual(clearedCart.get("products"), {});
  assert.equal(clearedCart.get("itemsCount"), 0);
  assert.equal(clearedCart.get("lock"), undefined);
  const notificationOutbox = await db
    .collection("commerceNotificationOutbox")
    .where("notice.orderId", "==", orderId)
    .get();
  assert.equal(notificationOutbox.size, 1);
  assert.equal(notificationOutbox.docs[0].get("notice.orderId"), orderId);
  assert.equal(notificationOutbox.docs[0].get("notice.status"), "paid");
  assert.equal(ownedSettlements.docs[0].get("merchantNetProceedsMinor"), 9_401);
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
  assert.deepEqual(consumed, { deduped: true });
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
