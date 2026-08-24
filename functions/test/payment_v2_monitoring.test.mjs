import assert from "node:assert/strict";
import test from "node:test";
import {
  paymentIntentMonitoringIncidentId,
  paymentIntentRequiresMonitoring,
} from "../lib/payments/v2/paymentIntentMonitoring.js";

const timestamp = (millis) => ({ toMillis: () => millis });

test("only overdue initialized intents require operations monitoring", () => {
  const nowMs = 1_000_000;
  assert.equal(
    paymentIntentRequiresMonitoring({
      value: { status: "initialized", initializedAt: timestamp(99_999) },
      nowMs,
    }),
    true,
  );
  assert.equal(
    paymentIntentRequiresMonitoring({
      value: { status: "initialized", initializedAt: timestamp(100_001) },
      nowMs,
    }),
    false,
  );
  assert.equal(
    paymentIntentRequiresMonitoring({
      value: { status: "paid", initializedAt: timestamp(1) },
      nowMs,
    }),
    false,
  );
  assert.equal(
    paymentIntentRequiresMonitoring({
      value: { status: "initialized" },
      nowMs,
    }),
    false,
  );
});

test("payment monitoring incident IDs are deterministic per intent", () => {
  assert.equal(
    paymentIntentMonitoringIncidentId("intent-a"),
    paymentIntentMonitoringIncidentId("intent-a"),
  );
  assert.notEqual(
    paymentIntentMonitoringIncidentId("intent-a"),
    paymentIntentMonitoringIncidentId("intent-b"),
  );
});
