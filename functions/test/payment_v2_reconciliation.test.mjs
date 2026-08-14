import assert from "node:assert/strict";
import test from "node:test";
import {
  reconcileIntentData,
  reconcilePaymentRequestReservationData,
  reconciliationOperationBindingMatches,
  reconciliationOutcome,
} from "../lib/payments/v2/reconciliation.js";

const balanced = {
  status: "paid",
  expectedAmountMinor: 10_000,
  providerAmountMinor: 10_000,
  providerReference: "ref_1",
  money: {
    currency: "ZAR",
    grossAmountMinor: 10_000,
    platformFeeMinor: 150,
    providerFeeMinor: 390,
    retainedCostMinor: 0,
    platformGrossShareMinor: 150,
    merchantGrossShareMinor: 9_850,
    merchantNetProceedsMinor: 9_460,
  },
};

test("accepts a balanced paid intent", () => {
  assert.deepEqual(reconcileIntentData(balanced), []);
});

test("reports split, amount and reference mismatches without guessing", () => {
  const issues = reconcileIntentData({
    ...balanced,
    providerAmountMinor: 9_999,
    providerReference: "",
    money: {
      ...balanced.money,
      merchantGrossShareMinor: 9_849,
    },
  });
  assert.deepEqual(
    issues.map((issue) => issue.code),
    [
      "MONEY_SNAPSHOT_INVALID",
      "SPLIT_TOTAL_MISMATCH",
      "PROVIDER_AMOUNT_MISMATCH",
      "PROVIDER_REFERENCE_MISSING",
    ],
  );
});

test("never treats a locally marked refund as provider-confirmed", () => {
  const issues = reconcileIntentData({
    ...balanced,
    status: "refunded",
    refundProviderConfirmed: false,
  });
  assert.deepEqual(
    issues.map((issue) => issue.code),
    ["REFUND_NOT_PROVIDER_CONFIRMED"],
  );
});

test("a truncated reconciliation window can never report balanced", () => {
  assert.deepEqual(
    reconciliationOutcome({ mismatchCount: 0, windowTruncated: true }),
    { mismatchCount: 1, status: "mismatch" },
  );
  assert.deepEqual(
    reconciliationOutcome({ mismatchCount: 0, windowTruncated: false }),
    { mismatchCount: 0, status: "balanced" },
  );
});

test("an audited reconciliation operation cannot be rebound on retry", () => {
  const binding = {
    operationId: "reconcile-480-final",
    actorUid: "spaza-admin-qa",
    reason: "Final development release reconciliation",
    windowDays: 30,
  };
  assert.equal(reconciliationOperationBindingMatches(binding, binding), true);
  assert.equal(
    reconciliationOperationBindingMatches(
      { ...binding, reason: "Different reason" },
      binding,
    ),
    false,
  );
  assert.equal(
    reconciliationOperationBindingMatches(
      { ...binding, windowDays: 7 },
      binding,
    ),
    false,
  );
  assert.equal(
    reconciliationOperationBindingMatches(
      { ...binding, actorUid: "another-admin" },
      binding,
    ),
    false,
  );
});

test("payment-request wallet reservations reconcile to the exact cent", () => {
  assert.deepEqual(
    reconcilePaymentRequestReservationData({
      status: "settled",
      reservedMinor: 120,
      spentMinor: 85,
      refundedMinor: 35,
    }),
    [],
  );
  assert.deepEqual(
    reconcilePaymentRequestReservationData({
      status: "recovered",
      reservedMinor: 120,
      spentMinor: 0,
      refundedMinor: 120,
    }),
    [],
  );
  assert.deepEqual(
    reconcilePaymentRequestReservationData({
      status: "settled",
      reservedMinor: 120,
      spentMinor: 85,
      refundedMinor: 34,
    }).map((issue) => issue.code),
    ["REQUEST_RESERVATION_TOTAL_MISMATCH"],
  );
  assert.deepEqual(
    reconcilePaymentRequestReservationData({
      status: "released",
      reservedMinor: 120,
      spentMinor: 1,
      refundedMinor: 119,
    }).map((issue) => issue.code),
    ["RELEASED_REQUEST_RESERVATION_CHARGED"],
  );
});
