import assert from "node:assert/strict";
import test from "node:test";

import {
  buildPaymentReceiptPatch,
  canAdvanceOrderFulfillment,
  canRecordManualPayment,
  isPaymentAlreadyRecorded,
  isPaymentReceiptAction,
} from "../lib/ecommerce/orderPaymentPolicy.js";

test("recognizes only actions that record newly received money", () => {
  assert.equal(isPaymentReceiptAction("MARK_CASH_RECEIVED"), true);
  assert.equal(isPaymentReceiptAction("SETTLE_BNPL"), true);
  assert.equal(isPaymentReceiptAction("ACCEPT_BNPL"), false);
  assert.equal(isPaymentReceiptAction("MARK_DELIVERED"), false);
});

test("treats every durable paid marker as an existing receipt", () => {
  assert.equal(isPaymentAlreadyRecorded({ paymentStatus: "paid" }), true);
  assert.equal(isPaymentAlreadyRecorded({ status: "PAID" }), true);
  assert.equal(isPaymentAlreadyRecorded({ cashReceivedAt: new Date() }), true);
  assert.equal(isPaymentAlreadyRecorded({ paidAt: new Date() }), true);
  assert.equal(isPaymentAlreadyRecorded({ paymentStatus: "unpaid" }), false);
});

test("preserves transfer and BNPL payment semantics in atomic patches", () => {
  const now = new Date("2026-08-06T10:00:00.000Z");
  assert.deepEqual(
    buildPaymentReceiptPatch(
      "MARK_CASH_RECEIVED",
      { paymentMethod: "eft" },
      now,
    ),
    {
      updatedAt: now,
      paymentMethod: "Transfer",
      paymentStatus: "paid",
      status: "paid",
      paidAt: now,
    },
  );
  assert.deepEqual(buildPaymentReceiptPatch("SETTLE_BNPL", {}, now), {
    updatedAt: now,
    paymentStatus: "paid",
    status: "paid",
    paidAt: now,
  });
});

test("requires EFT before handover and cash at handover", () => {
  assert.equal(
    canRecordManualPayment({ paymentMethod: "EFT", paymentStatus: "unpaid" }),
    true,
  );
  assert.equal(
    canAdvanceOrderFulfillment({
      paymentMethod: "EFT",
      paymentStatus: "unpaid",
    }),
    false,
  );
  assert.equal(
    canAdvanceOrderFulfillment({
      paymentMethod: "EFT",
      paymentStatus: "paid",
    }),
    true,
  );
  assert.equal(
    canRecordManualPayment({ paymentMethod: "Cash", collected: false }),
    false,
  );
  assert.equal(
    canRecordManualPayment({ paymentMethod: "Cash", collected: true }),
    true,
  );
  assert.equal(
    canAdvanceOrderFulfillment({
      paymentMethod: "Cash",
      paymentStatus: "unpaid",
    }),
    true,
  );
});

test("keeps online payment webhook-only and Pay Later explicit", () => {
  assert.equal(
    canRecordManualPayment({
      paymentMethod: "EFT",
      paymentRail: "paystack_v2",
      paymentStatus: "pending",
    }),
    false,
  );
  assert.equal(
    canAdvanceOrderFulfillment({
      paymentMethod: "paystack",
      paymentRail: "paystack_v2",
      paymentStatus: "pending",
    }),
    false,
  );
  assert.equal(
    canAdvanceOrderFulfillment({
      paymentMethod: "BNPL",
      paymentStatus: "approved",
    }),
    true,
  );
  assert.equal(
    canAdvanceOrderFulfillment({
      paymentMethod: "BNPL",
      paymentStatus: "pending",
    }),
    false,
  );
});
