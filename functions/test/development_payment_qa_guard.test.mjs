import assert from "node:assert/strict";
import test from "node:test";

import { validateDevelopmentPaymentQaOptions } from "../scripts/prepare-development-payment-qa.mjs";

test("development payment QA refuses production and implicit projects", () => {
  assert.throws(() => validateDevelopmentPaymentQaOptions([]));
  assert.throws(() =>
    validateDevelopmentPaymentQaOptions(["--project", "pasella-ledger"]),
  );
});

test("development payment QA is dry-run by default", () => {
  const options = validateDevelopmentPaymentQaOptions([
    "--project",
    "spazaone-dev",
  ]);
  assert.equal(options.execute, false);
  assert.equal(options.verify, false);
  assert.equal(options.rollback, false);
  assert.deepEqual(options.capabilities, ["campaign_credit"]);
});

test("development payment QA mutations require one mode and a run id", () => {
  assert.throws(() =>
    validateDevelopmentPaymentQaOptions([
      "--project",
      "spazaone-dev",
      "--execute",
    ]),
  );
  assert.throws(() =>
    validateDevelopmentPaymentQaOptions([
      "--project",
      "spazaone-dev",
      "--run-id",
      "qa-1",
      "--execute",
      "--rollback",
    ]),
  );
  const options = validateDevelopmentPaymentQaOptions([
    "--project",
    "spazaone-dev",
    "--run-id",
    "qa-1",
    "--execute",
  ]);
  assert.equal(options.execute, true);
  assert.equal(options.runId, "qa-1");
});

test("development payment QA accepts only the bounded release capabilities", () => {
  const options = validateDevelopmentPaymentQaOptions([
    "--project",
    "spazaone-dev",
    "--capabilities",
    "campaign_credit,merchant_order,account_settlement",
  ]);
  assert.deepEqual(options.capabilities, [
    "campaign_credit",
    "merchant_order",
    "account_settlement",
  ]);
  assert.throws(
    () =>
      validateDevelopmentPaymentQaOptions([
        "--project",
        "spazaone-dev",
        "--capabilities",
        "supplier_order",
      ]),
    /CAPABILITIES_INVALID/,
  );
  assert.throws(
    () =>
      validateDevelopmentPaymentQaOptions([
        "--project",
        "spazaone-dev",
        "--capabilities",
        "merchant_order,merchant_order",
      ]),
    /CAPABILITIES_INVALID/,
  );
});

test("settlement capabilities require an explicit Paystack Test subaccount for mutations", () => {
  assert.throws(
    () =>
      validateDevelopmentPaymentQaOptions([
        "--project",
        "spazaone-dev",
        "--run-id",
        "commerce-qa",
        "--capabilities",
        "merchant_order,account_settlement",
        "--execute",
      ]),
    /TEST_SUBACCOUNT_REQUIRED/,
  );
  const options = validateDevelopmentPaymentQaOptions([
    "--project",
    "spazaone-dev",
    "--run-id",
    "commerce-qa",
    "--capabilities",
    "merchant_order,account_settlement",
    "--test-subaccount-code",
    "ACCT_test123",
    "--execute",
  ]);
  assert.equal(options.settlementCapabilitySelected, true);
  assert.equal(options.testSubaccountCode, "ACCT_test123");
});
