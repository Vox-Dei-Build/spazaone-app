import assert from "node:assert/strict";
import test from "node:test";
import {
  accountOutstandingMinor,
  nextRepaymentInstallmentMinor,
  shouldReopenPaymentRequestAfterExpiry,
} from "../lib/payments/v2/accountSettlements.js";

test("account settlement reads the legacy negative Rand balance at its boundary", () => {
  assert.equal(accountOutstandingMinor(-125.37), 12_537);
  assert.equal(accountOutstandingMinor(0), 0);
  assert.equal(accountOutstandingMinor(100), 0);
  assert.throws(
    () => accountOutstandingMinor("not-money"),
    /CUSTOMER_BALANCE_INVALID/,
  );
});

test("an expired link reopens only its own still-unpaid request", () => {
  assert.equal(
    shouldReopenPaymentRequestAfterExpiry({
      requestStatus: "link_created",
      lastPaymentIntentId: "pi_latest",
      expiredIntentId: "pi_latest",
    }),
    true,
  );
  for (const requestStatus of ["paid", "partially_paid", "needs_review"]) {
    assert.equal(
      shouldReopenPaymentRequestAfterExpiry({
        requestStatus,
        lastPaymentIntentId: "pi_latest",
        expiredIntentId: "pi_latest",
      }),
      false,
    );
  }
  assert.equal(
    shouldReopenPaymentRequestAfterExpiry({
      requestStatus: "link_created",
      lastPaymentIntentId: "pi_newer",
      expiredIntentId: "pi_old",
    }),
    false,
  );
});

test("repayment installments never overpay the final balance", () => {
  assert.equal(
    nextRepaymentInstallmentMinor({
      remainingAmountMinor: 10_000,
      installmentAmountMinor: 2_500,
    }),
    2_500,
  );
  assert.equal(
    nextRepaymentInstallmentMinor({
      remainingAmountMinor: 900,
      installmentAmountMinor: 2_500,
    }),
    900,
  );
});
