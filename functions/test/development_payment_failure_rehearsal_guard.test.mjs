import assert from "node:assert/strict";
import test from "node:test";

import { validateDevelopmentFailureRehearsalOptions } from "../scripts/rehearse-development-payment-failures.mjs";

test("development failure rehearsal refuses production", () => {
  assert.throws(() => validateDevelopmentFailureRehearsalOptions([]));
  assert.throws(() =>
    validateDevelopmentFailureRehearsalOptions([
      "--project",
      "pasella-ledger",
      "--run-id",
      "failure-run-20260812",
      "--execute",
    ]),
  );
});

test("development failure rehearsal requires an explicit run for writes", () => {
  assert.throws(() =>
    validateDevelopmentFailureRehearsalOptions([
      "--project",
      "spazaone-dev",
      "--execute",
    ]),
  );
  const options = validateDevelopmentFailureRehearsalOptions([
    "--project",
    "spazaone-dev",
    "--run-id",
    "failure-run-20260812",
    "--execute",
  ]);
  assert.equal(options.execute, true);
  assert.equal(options.runId, "failure-run-20260812");
});
