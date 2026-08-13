import assert from "node:assert/strict";
import test from "node:test";
import {
  assertMoneySnapshot,
  assertPaymentTransition,
  buildMoneySnapshot,
  calculatePlatformFeeMinor,
  failureOutcome,
  stableDocumentId,
} from "../lib/payments/v2/domain.js";
import {
  payloadDigest,
  paymentIntentDocumentId,
  providerEventDocumentId,
} from "../lib/payments/v2/financialCore.js";
import { resolvePaymentReadiness } from "../lib/payments/v2/readiness.js";
import { buildBuyerPaymentsV2 } from "../lib/payments/v2/buyerReadiness.js";
import { requireAdminAdjustmentMinor } from "../lib/payments/v2/admin.js";
import {
  assertBankAccountOnlyVerificationPayload,
  maskedAccountHolderName,
  protectedIdentityFingerprint,
  settlementVerificationBudgetDecision,
  settlementVerificationAuthorizationDecision,
  settlementDestinationRetirementDecision,
  settlementProfileAction,
  settlementVerificationDecision,
  settlementVerificationIdentity,
} from "../lib/payments/v2/merchantProfiles.js";
import { availableSupplierFunding } from "../lib/payments/v2/supplierFunding.js";
import { commerceStatusForCj } from "../lib/payments/v2/supplierOrders.js";

test("admin Campaign Credit adjustments require signed integer cents", () => {
  assert.equal(requireAdminAdjustmentMinor(5_000), 5_000);
  assert.equal(requireAdminAdjustmentMinor(-500), -500);
  assert.throws(() => requireAdminAdjustmentMinor(0), /valid Campaign Credit/);
  assert.throws(
    () => requireAdminAdjustmentMinor(10.5),
    /valid Campaign Credit/,
  );
});

test("calculates the launch collection fee in cents", () => {
  assert.equal(calculatePlatformFeeMinor({ grossAmountMinor: 1_000 }), 50);
  assert.equal(calculatePlatformFeeMinor({ grossAmountMinor: 10_000 }), 150);
  assert.equal(calculatePlatformFeeMinor({ grossAmountMinor: 33_333 }), 500);
});

test("snapshots collection shares without a floating-point balance", () => {
  const money = buildMoneySnapshot({
    grossAmountMinor: 10_000,
    platformFeeMinor: 150,
    providerFeeMinor: 390,
    retainedCostMinor: 4_000,
  });
  assert.deepEqual(money, {
    currency: "ZAR",
    grossAmountMinor: 10_000,
    platformFeeMinor: 150,
    providerFeeMinor: 390,
    retainedCostMinor: 4_000,
    platformGrossShareMinor: 4_150,
    merchantGrossShareMinor: 5_850,
    merchantNetProceedsMinor: 5_460,
  });
  assert.doesNotThrow(() => assertMoneySnapshot(money));
});

test("rejects a supplier split that makes merchant proceeds negative", () => {
  assert.throws(
    () =>
      buildMoneySnapshot({
        grossAmountMinor: 10_000,
        platformFeeMinor: 500,
        retainedCostMinor: 9_300,
        providerFeeMinor: 390,
      }),
    /MERCHANT_PROCEEDS_NEGATIVE/,
  );
});

test("payment transitions fail closed", () => {
  assert.doesNotThrow(() => assertPaymentTransition("created", "paid"));
  assert.doesNotThrow(() => assertPaymentTransition("paid", "refund_pending"));
  assert.throws(
    () => assertPaymentTransition("refunded", "paid"),
    /PAYMENT_TRANSITION_INVALID/,
  );
});

test("every rehearsed failure must end in one accountable outcome", () => {
  assert.equal(
    failureOutcome({
      charged: false,
      retryable: false,
      fulfilled: false,
      refundPending: false,
    }),
    "no_charge",
  );
  assert.equal(
    failureOutcome({
      charged: false,
      retryable: true,
      fulfilled: false,
      refundPending: false,
    }),
    "safely_retryable",
  );
  assert.equal(
    failureOutcome({
      charged: true,
      retryable: false,
      fulfilled: true,
      refundPending: false,
    }),
    "paid_and_fulfilled",
  );
  assert.equal(
    failureOutcome({
      charged: true,
      retryable: false,
      fulfilled: false,
      refundPending: true,
    }),
    "paid_refund_pending",
  );
  assert.throws(
    () =>
      failureOutcome({
        charged: true,
        retryable: false,
        fulfilled: false,
        refundPending: false,
      }),
    /CHARGED_OUTCOME_UNACCOUNTED/,
  );
});

test("intent and provider event identifiers are deterministic", () => {
  const intent = paymentIntentDocumentId({
    merchantId: "storeA",
    purpose: "merchant_order",
    idempotencyKey: "checkout-1",
  });
  assert.equal(
    intent,
    paymentIntentDocumentId({
      merchantId: "storeA",
      purpose: "merchant_order",
      idempotencyKey: "checkout-1",
    }),
  );
  assert.notEqual(intent, stableDocumentId("pi", ["different"]));
  const rawBody = Buffer.from('{"event":"charge.success"}');
  const event = {
    provider: "paystack",
    eventType: "charge.success",
    reference: "ref_1",
    rawBody,
  };
  assert.equal(providerEventDocumentId(event), providerEventDocumentId(event));
  const providerIdentifiedEvent = {
    ...event,
    providerEventId: "evt_1",
  };
  assert.equal(
    providerEventDocumentId(providerIdentifiedEvent),
    providerEventDocumentId({
      ...providerIdentifiedEvent,
      rawBody: Buffer.from('{"event":"charge.success","changed":true}'),
    }),
    "the provider identity remains stable so an altered replay collides",
  );
  assert.equal(payloadDigest(rawBody).length, 64);
});

test("readiness requires every independent gate", () => {
  const base = {
    masterEnabled: true,
    globalCapabilities: { merchant_order: true },
    merchantStatus: "enabled",
    merchantCapabilities: { merchant_order: true },
    purpose: "merchant_order",
  };
  assert.deepEqual(resolvePaymentReadiness(base), {
    enabled: true,
    reason: "ready",
  });
  assert.equal(
    resolvePaymentReadiness({ ...base, masterEnabled: false }).reason,
    "master_disabled",
  );
  assert.equal(
    resolvePaymentReadiness({ ...base, emergencySuspended: true }).reason,
    "global_suspended",
  );
  assert.equal(
    resolvePaymentReadiness({ ...base, merchantStatus: "suspended" }).reason,
    "merchant_not_enabled",
  );
});

test("campaign credits do not require a settlement subaccount", () => {
  const base = {
    masterEnabled: true,
    globalCapabilities: { campaign_credit: true },
    merchantStatus: "not_started",
    merchantCapabilities: {},
    purpose: "campaign_credit",
  };
  assert.deepEqual(resolvePaymentReadiness(base), {
    enabled: true,
    reason: "ready",
  });
  assert.equal(
    resolvePaymentReadiness({ ...base, merchantStatus: "suspended" }).reason,
    "merchant_not_enabled",
  );
  assert.equal(
    resolvePaymentReadiness({
      ...base,
      merchantCapabilities: { campaign_credit: false },
    }).reason,
    "merchant_capability_disabled",
  );
});

test("buyer-safe readiness exposes channels only for ready capabilities", () => {
  const ready = { enabled: true, reason: "ready" };
  const disabled = { enabled: false, reason: "merchant_not_enabled" };
  const payments = buildBuyerPaymentsV2({
    campaignCredits: ready,
    ownedOrders: disabled,
    accountPayments: disabled,
    supplierOrders: ready,
  });

  assert.equal(payments.schemaVersion, 2);
  assert.deepEqual(payments.campaignCredits.channels, [
    "eft",
    "capitec_pay",
    "qr",
  ]);
  assert.deepEqual(payments.ownedOrders.channels, []);
  assert.equal(payments.manualTransferForOwnedOrders, true);
  assert.equal(payments.supplierOrdersRequireOnlinePayment, true);
});

test("South African settlement verification always requires admin review", () => {
  const clean = {
    verified: true,
    accountOpen: true,
    accountAcceptsCredits: true,
    accountHolderMatch: true,
    accountOpenForMoreThanThreeMonths: true,
  };
  assert.deepEqual(settlementVerificationDecision(clean), {
    eligible: true,
    autoApprove: false,
  });
  assert.deepEqual(
    settlementVerificationDecision({
      ...clean,
      accountOpenForMoreThanThreeMonths: false,
    }),
    { eligible: true, autoApprove: false },
  );
  assert.deepEqual(
    settlementVerificationDecision({ ...clean, accountHolderMatch: false }),
    { eligible: false, autoApprove: false },
  );
});

test("settlement verification requires a live admin authorization budget", () => {
  const nowMs = Date.now();
  assert.deepEqual(
    settlementVerificationAuthorizationDecision({
      state: "authorized",
      expiresAtMs: nowMs + 60_000,
      remainingAttempts: 2,
      nowMs,
    }),
    { allowed: true, reason: "allowed" },
  );
  assert.equal(
    settlementVerificationAuthorizationDecision({
      state: "revoked",
      expiresAtMs: nowMs + 60_000,
      remainingAttempts: 2,
      nowMs,
    }).reason,
    "BANK_VALIDATION_PREAUTH_REQUIRED",
  );
  assert.equal(
    settlementVerificationAuthorizationDecision({
      state: "authorized",
      expiresAtMs: nowMs - 1,
      remainingAttempts: 2,
      nowMs,
    }).reason,
    "BANK_VALIDATION_PREAUTH_EXPIRED",
  );
  assert.equal(
    settlementVerificationAuthorizationDecision({
      state: "authorized",
      expiresAtMs: nowMs + 60_000,
      remainingAttempts: 0,
      nowMs,
    }).reason,
    "BANK_VALIDATION_PREAUTH_CONSUMED",
  );
});

test("settlement identity evidence is keyed and customer-safe", () => {
  const identity = {
    documentType: "identityNumber",
    documentNumber: "900101-5009-087",
  };
  const first = protectedIdentityFingerprint("test-secret-a", identity);
  assert.equal(first.length, 64);
  assert.equal(first, protectedIdentityFingerprint("test-secret-a", identity));
  assert.notEqual(
    first,
    protectedIdentityFingerprint("test-secret-b", identity),
  );
  assert.equal(first.includes("900101"), false);
  assert.equal(maskedAccountHolderName("Nomsa Dlamini"), "N•••• D••••••");
});

test("settlement setup accepts only matching personal and business evidence", () => {
  assert.deepEqual(
    settlementVerificationIdentity({
      accountType: "personal",
      documentType: "identityNumber",
      documentNumber: "900101 5009 087",
    }),
    {
      accountType: "personal",
      documentType: "identityNumber",
      documentNumber: "900101 5009 087",
    },
  );
  assert.deepEqual(
    settlementVerificationIdentity({
      accountType: "personal",
      documentType: "passportNumber",
      documentNumber: "A12345678",
    }),
    {
      accountType: "personal",
      documentType: "passportNumber",
      documentNumber: "A12345678",
    },
  );
  assert.deepEqual(
    settlementVerificationIdentity({
      accountType: "business",
      documentType: "businessRegistrationNumber",
      documentNumber: "2024/123456/07",
    }),
    {
      accountType: "business",
      documentType: "businessRegistrationNumber",
      documentNumber: "2024/123456/07",
    },
  );
  assert.throws(
    () =>
      settlementVerificationIdentity({
        accountType: "business",
        documentType: "identityNumber",
        documentNumber: "9001015009087",
      }),
    /BANK_DOCUMENT_TYPE_INVALID/,
  );
});

test("settlement verification rejects every card-shaped request surface", () => {
  assert.doesNotThrow(() =>
    assertBankAccountOnlyVerificationPayload({
      merchantId: "merchant-1",
      bankingDetailsId: "bank-1",
      verificationType: "bank_account",
    }),
  );
  for (const payload of [
    { cardNumber: "4084084084084081" },
    { pan: "4084084084084081" },
    { cvv: "408" },
    { instrumentType: "credit_card" },
    { verificationType: "card" },
  ]) {
    assert.throws(
      () => assertBankAccountOnlyVerificationPayload(payload),
      /BANK_CARD_INPUT_REJECTED/,
    );
  }
});

test("settlement verification has merchant, lifetime and platform budgets", () => {
  assert.deepEqual(
    settlementVerificationBudgetDecision({
      merchantDayAttempts: 0,
      merchantLifetimeAttempts: 0,
      platformDayAttempts: 0,
      suspended: false,
    }),
    { allowed: true, reason: "allowed", suspendAfterAttempt: false },
  );
  assert.equal(
    settlementVerificationBudgetDecision({
      merchantDayAttempts: 2,
      merchantLifetimeAttempts: 2,
      platformDayAttempts: 2,
      suspended: false,
    }).reason,
    "BANK_VALIDATION_DAILY_LIMIT",
  );
  assert.equal(
    settlementVerificationBudgetDecision({
      merchantDayAttempts: 0,
      merchantLifetimeAttempts: 6,
      platformDayAttempts: 2,
      suspended: false,
    }).reason,
    "BANK_VALIDATION_LIFETIME_LIMIT",
  );
  assert.deepEqual(
    settlementVerificationBudgetDecision({
      merchantDayAttempts: 0,
      merchantLifetimeAttempts: 1,
      platformDayAttempts: 9,
      suspended: false,
    }),
    { allowed: true, reason: "allowed", suspendAfterAttempt: true },
  );
  assert.equal(
    settlementVerificationBudgetDecision({
      merchantDayAttempts: 0,
      merchantLifetimeAttempts: 1,
      platformDayAttempts: 10,
      suspended: false,
    }).reason,
    "BANK_VALIDATION_PLATFORM_LIMIT",
  );
  assert.equal(
    settlementVerificationBudgetDecision({
      merchantDayAttempts: 0,
      merchantLifetimeAttempts: 1,
      platformDayAttempts: 0,
      suspended: true,
    }).reason,
    "BANK_VALIDATION_SUSPENDED",
  );
});

test("settlement setup dedupes destinations and reviews every replacement", () => {
  assert.equal(
    settlementProfileAction({
      sameActiveDestination: true,
      samePendingDestination: false,
      hadActiveAccount: true,
      validationAutoApprove: true,
    }),
    "dedupe_active",
  );
  assert.equal(
    settlementProfileAction({
      sameActiveDestination: false,
      samePendingDestination: true,
      hadActiveAccount: true,
      validationAutoApprove: true,
    }),
    "dedupe_pending",
  );
  assert.equal(
    settlementProfileAction({
      sameActiveDestination: false,
      samePendingDestination: false,
      hadActiveAccount: true,
      validationAutoApprove: true,
    }),
    "pending_review",
  );
  assert.equal(
    settlementProfileAction({
      sameActiveDestination: false,
      samePendingDestination: false,
      hadActiveAccount: false,
      validationAutoApprove: true,
    }),
    "pending_review",
  );
});

test("an old settlement destination retires only after every movement is final", () => {
  const base = {
    settlementStatuses: ["completed"],
    paymentIntentStatuses: ["cancelled", "expired", "refunded"],
    settlementWindowComplete: true,
    paymentIntentWindowComplete: true,
  };
  assert.deepEqual(settlementDestinationRetirementDecision(base), {
    safe: true,
    reason: "clear",
  });
  assert.deepEqual(
    settlementDestinationRetirementDecision({
      ...base,
      paymentIntentStatuses: ["initialized"],
    }),
    { safe: false, reason: "in_flight_payment" },
  );
  assert.deepEqual(
    settlementDestinationRetirementDecision({
      ...base,
      settlementStatuses: ["processing"],
    }),
    { safe: false, reason: "pending_settlement" },
  );
  assert.deepEqual(
    settlementDestinationRetirementDecision({
      ...base,
      paymentIntentWindowComplete: false,
    }),
    { safe: false, reason: "history_truncated" },
  );
});

test("supplier funding subtracts concurrent reservations without double counting its own", () => {
  assert.equal(
    availableSupplierFunding({
      providerBalanceUsdMinor: 10_000,
      outstandingUsdMinor: 4_000,
    }),
    6_000,
  );
  assert.equal(
    availableSupplierFunding({
      providerBalanceUsdMinor: 10_000,
      outstandingUsdMinor: 4_000,
      currentReservationUsdMinor: 1_500,
    }),
    7_500,
  );
  assert.equal(
    availableSupplierFunding({
      providerBalanceUsdMinor: 0,
      outstandingUsdMinor: 0,
    }),
    0,
  );
});

test("supplier tracking maps CJ statuses into the canonical order lifecycle", () => {
  assert.equal(commerceStatusForCj("PROCESSING"), "preparing");
  assert.equal(commerceStatusForCj("UNSHIPPED"), "preparing");
  assert.equal(commerceStatusForCj("SHIPPED"), "shipped");
  assert.equal(commerceStatusForCj("DELIVERED"), "delivered");
  assert.equal(commerceStatusForCj("CANCELLED"), null);
});
