import assert from "node:assert/strict";
import test from "node:test";
import {
  FAILURE_REHEARSALS,
  FAILURE_SCENARIO_IDS,
  validateFailureRehearsals,
} from "../lib/payments/v2/failureHarness.js";

test("every I2 disaster has exactly one accountable outcome", () => {
  assert.doesNotThrow(() => validateFailureRehearsals());
  assert.equal(FAILURE_REHEARSALS.length, FAILURE_SCENARIO_IDS.length);
  assert.deepEqual(
    [...new Set(FAILURE_REHEARSALS.map((scenario) => scenario.id))].sort(),
    [...FAILURE_SCENARIO_IDS].sort(),
  );
});

test("the harness refuses duplicate, missing, uncontrolled or unaccounted failures", () => {
  assert.throws(
    () =>
      validateFailureRehearsals([FAILURE_REHEARSALS[0], FAILURE_REHEARSALS[0]]),
    /SCENARIO_DUPLICATE/,
  );
  assert.throws(
    () => validateFailureRehearsals(FAILURE_REHEARSALS.slice(1)),
    /SCENARIO_MISSING/,
  );
  assert.throws(
    () =>
      validateFailureRehearsals([
        { ...FAILURE_REHEARSALS[0], control: "" },
        ...FAILURE_REHEARSALS.slice(1),
      ]),
    /CONTROL_MISSING/,
  );
  assert.throws(
    () =>
      validateFailureRehearsals([
        { ...FAILURE_REHEARSALS[0], expectedOutcome: "safely_retryable" },
        ...FAILURE_REHEARSALS.slice(1),
      ]),
    /OUTCOME_MISMATCH/,
  );
});
