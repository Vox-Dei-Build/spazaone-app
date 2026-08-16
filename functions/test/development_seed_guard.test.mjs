import assert from "node:assert/strict";
import test from "node:test";
import { validateDevelopmentSeedOptions } from "../scripts/seed-development-cloud.mjs";

test("development seed refuses production and unregistered projects", () => {
  assert.throws(() => validateDevelopmentSeedOptions([]));
  assert.throws(() =>
    validateDevelopmentSeedOptions(["--project", "pasella-ledger"]),
  );
  assert.throws(() =>
    validateDevelopmentSeedOptions(["--project", "demo-spazaone-qa"]),
  );
});

test("development seed is dry-run by default", () => {
  const options = validateDevelopmentSeedOptions(["--project", "spazaone-dev"]);
  assert.equal(options.execute, false);
  assert.equal(options.verify, false);
});

test("development apply and verify require an explicit run id", () => {
  assert.throws(() =>
    validateDevelopmentSeedOptions(["--project", "spazaone-dev", "--execute"]),
  );
  const options = validateDevelopmentSeedOptions([
    "--project",
    "spazaone-dev",
    "--run-id",
    "development-seed-v2",
    "--verify",
  ]);
  assert.equal(options.verify, true);
  assert.equal(options.runId, "development-seed-v2");
});
