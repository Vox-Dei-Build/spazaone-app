import assert from "node:assert/strict";
import test from "node:test";

import {
  DEVELOPMENT_PAYSTACK_EMAIL,
  developmentOperatorPath,
  unwrapCallableResult,
  validateDevelopmentCampaignSmokeOptions,
} from "../scripts/run-development-campaign-topup-smoke.mjs";

test("campaign smoke uses a provider-valid non-personal QA email", () => {
  assert.match(DEVELOPMENT_PAYSTACK_EMAIL, /^[^@]+@spazaone\.com$/);
  assert.doesNotMatch(DEVELOPMENT_PAYSTACK_EMAIL, /\.(test|invalid)$/);
});

test("campaign smoke refuses production and unsafe execution options", () => {
  assert.throws(() => validateDevelopmentCampaignSmokeOptions([]));
  assert.throws(() =>
    validateDevelopmentCampaignSmokeOptions(["--project", "pasella-ledger"]),
  );
  assert.throws(() =>
    validateDevelopmentCampaignSmokeOptions([
      "--project",
      "spazaone-dev",
      "--execute",
      "--run-id",
      "too-short",
      "--output",
      "relative.json",
    ]),
  );
});

test("campaign smoke is dry-run by default with a bounded amount", () => {
  const options = validateDevelopmentCampaignSmokeOptions([
    "--project",
    "spazaone-dev",
    "--credit-minor",
    "1000",
  ]);
  assert.equal(options.execute, false);
  assert.equal(options.channel, "eft");
  assert.equal(options.creditAmountMinor, 1000);
});

test("campaign smoke accepts an explicit safe development execution", () => {
  const options = validateDevelopmentCampaignSmokeOptions([
    "--project",
    "spazaone-dev",
    "--execute",
    "--run-id",
    "campaign-smoke-20260812",
    "--output",
    "/tmp/spazaone-campaign-smoke.json",
    "--channel",
    "qr",
  ]);
  assert.equal(options.execute, true);
  assert.equal(options.channel, "qr");
});

test("campaign smoke accepts only the Firebase callable response envelope", () => {
  const environment = {
    environment: "development",
    firebaseProjectId: "spazaone-dev",
    providerModes: { paystack: "test" },
  };
  assert.deepEqual(unwrapCallableResult({ result: environment }), environment);
  assert.throws(
    () => unwrapCallableResult({ environment }),
    /DEVELOPMENT_ENVIRONMENT_CONTRACT_INVALID/,
  );
});

test("campaign smoke grants only a temporary synthetic merchant membership", () => {
  assert.equal(
    developmentOperatorPath("dev-seed-merchant", "temporary-uid"),
    "stores/dev-seed-merchant/operators/temporary-uid",
  );
  assert.throws(
    () => developmentOperatorPath("production-merchant", "temporary-uid"),
    /DEVELOPMENT_OPERATOR_BINDING_INVALID/,
  );
});
