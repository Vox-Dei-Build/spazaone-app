import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
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

test("scheduled expiry filters actionable settlement intents before its limit", () => {
  const source = readFileSync(
    new URL("../src/payments/v2/accountSettlements.ts", import.meta.url),
    "utf8",
  );
  assert.match(
    source,
    /collection\("paymentIntents"\)[\s\S]*?\.where\("purpose",\s*"in",[\s\S]*?\.where\("status",\s*"in",[\s\S]*?\.where\("expiresAt",\s*"<=",\s*cutoff\)[\s\S]*?\.orderBy\("expiresAt",\s*"asc"\)[\s\S]*?\.limit\(MAX_ACCOUNT_SETTLEMENT_EXPIRIES_PER_RUN\)/,
  );

  const indexes = JSON.parse(
    readFileSync(new URL("../../firestore.indexes.json", import.meta.url)),
  );
  const expiryIndex = indexes.indexes.find(
    (index) =>
      index.collectionGroup === "paymentIntents" &&
      index.queryScope === "COLLECTION" &&
      JSON.stringify(index.fields) ===
        JSON.stringify([
          { fieldPath: "purpose", order: "ASCENDING" },
          { fieldPath: "status", order: "ASCENDING" },
          { fieldPath: "expiresAt", order: "ASCENDING" },
          { fieldPath: "__name__", order: "ASCENDING" },
        ]),
  );
  assert.ok(expiryIndex);
});
