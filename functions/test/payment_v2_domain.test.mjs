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
import { requireAdminAdjustmentMinor } from "../lib/payments/v2/admin.js";

test("admin Campaign Credit adjustments require signed integer cents", () => {
  assert.equal(requireAdminAdjustmentMinor(5_000), 5_000);
  assert.equal(requireAdminAdjustmentMinor(-500), -500);
  assert.throws(() => requireAdminAdjustmentMinor(0), /valid Campaign Credit/);
  assert.throws(() => requireAdminAdjustmentMinor(10.5), /valid Campaign Credit/);
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
