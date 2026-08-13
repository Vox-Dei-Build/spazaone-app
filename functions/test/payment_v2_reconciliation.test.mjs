import assert from "node:assert/strict";
import test from "node:test";
import {
  reconcileIntentData,
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
