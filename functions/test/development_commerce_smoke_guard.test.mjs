import assert from "node:assert/strict";
import test from "node:test";

import { validateDevelopmentCommerceSmokeOptions } from "../scripts/run-development-commerce-smoke.mjs";

test("commerce smoke refuses production and implicit projects", () => {
  assert.throws(() => validateDevelopmentCommerceSmokeOptions([]));
  assert.throws(() =>
    validateDevelopmentCommerceSmokeOptions([
      "--project",
      "pasella-ledger",
      "--flow",
      "owned_order",
    ]),
  );
});

test("commerce smoke accepts only release flows and Paystack channels", () => {
  const supplier = validateDevelopmentCommerceSmokeOptions([
    "--project",
    "spazaone-dev",
    "--flow",
    "supplier_order",
  ]);
  assert.equal(supplier.flow, "supplier_order");
  assert.throws(
    () =>
      validateDevelopmentCommerceSmokeOptions([
        "--project",
        "spazaone-dev",
        "--flow",
        "repayment_installment",
      ]),
    /FLOW_INVALID/,
  );
  assert.throws(
    () =>
      validateDevelopmentCommerceSmokeOptions([
        "--project",
        "spazaone-dev",
        "--flow",
        "owned_order",
        "--channel",
        "apple_pay",
      ]),
    /CHANNEL_INVALID/,
  );
});

test("commerce smoke execute requires a run id and absolute handoff", () => {
  assert.throws(() =>
    validateDevelopmentCommerceSmokeOptions([
      "--project",
      "spazaone-dev",
      "--flow",
      "owned_order",
      "--execute",
    ]),
  );
  const options = validateDevelopmentCommerceSmokeOptions([
    "--project",
    "spazaone-dev",
    "--flow",
    "account_settlement",
    "--run-id",
    "account-smoke-20260812",
    "--output",
    "/tmp/account-smoke.json",
    "--amount-minor",
    "4000",
    "--execute",
  ]);
  assert.equal(options.execute, true);
  assert.equal(options.amountMinor, 4_000);
});
