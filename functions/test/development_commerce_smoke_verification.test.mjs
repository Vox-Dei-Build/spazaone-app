import assert from "node:assert/strict";
import test from "node:test";

import {
  validateCommerceSmokeEvidence,
  validateCommerceSmokeVerificationOptions,
} from "../scripts/verify-development-commerce-smoke.mjs";

test("commerce evidence verifier fails closed on production", () => {
  assert.throws(() =>
    validateCommerceSmokeVerificationOptions([
      "--project",
      "pasella-ledger",
      "--handoff",
      "/tmp/evidence.json",
    ]),
  );
});

test("owned-order evidence requires exactly one event and a committed reservation", () => {
  const handoff = {
    flow: "owned_order",
    merchantId: "dev-seed-merchant",
    orderId: "order-1",
    reservationId: "reservation-1",
    intentId: "intent-1",
    reference: "reference-1",
    amountMinor: 1_600,
    channel: "eft",
    productQuantityBefore: 20,
  };
  const actualMoney = {
    currency: "ZAR",
    grossAmountMinor: 1_600,
    platformFeeMinor: 50,
    providerFeeMinor: 37,
    platformGrossShareMinor: 50,
    merchantGrossShareMinor: 1_550,
    merchantNetProceedsMinor: 1_513,
  };
  const valid = {
    handoff,
    run: { status: "initialized", synthetic: true, intentId: "intent-1" },
    intent: {
      status: "paid",
      purpose: "merchant_order",
      merchantId: "dev-seed-merchant",
      expectedAmountMinor: 1_600,
      providerAmountMinor: 1_600,
      providerReference: "reference-1",
      selectedChannel: "eft",
      appliedProviderEventIds: ["event-1"],
      actualMoney,
      businessBinding: { type: "owned_order", id: "order-1" },
    },
    event: {
      processingState: "applied",
      eventType: "charge.success",
      intentId: "intent-1",
      reference: "reference-1",
    },
    eventCount: 1,
    settlement: {
      ...actualMoney,
      status: "pending",
      intentId: "intent-1",
      destination: { accountLast4: "0000" },
    },
    settlementCount: 1,
    refundCount: 0,
    notification: { state: "retry", attempts: 1 },
    notificationCount: 1,
    sale: {
      status: "paid",
      paymentStatus: "paid",
      paymentIntentId: "intent-1",
    },
    reservation: { status: "committed", reservationId: "reservation-1" },
    product: { quantity: 19 },
    ledger: {},
    paystackLedgerCount: 0,
    customer: {},
  };
  assert.deepEqual(validateCommerceSmokeEvidence(valid), []);
  const replayed = { ...valid, eventCount: 2 };
  assert.ok(
    validateCommerceSmokeEvidence(replayed).includes(
      "PROVIDER_EVENT_COUNT_MISMATCH",
    ),
  );
  const released = { ...valid, reservation: { status: "released" } };
  assert.ok(
    validateCommerceSmokeEvidence(released).includes(
      "RESERVATION_NOT_COMMITTED",
    ),
  );
});
