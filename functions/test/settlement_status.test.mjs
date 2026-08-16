import assert from "node:assert/strict";
import test from "node:test";

import {
  addWorkingDays,
  normalizePaystackSettlementStatus,
} from "../lib/payments/v2/settlementStatus.js";

test("Paystack settlement statuses map to merchant-safe states", () => {
  assert.equal(normalizePaystackSettlementStatus("success"), "completed");
  assert.equal(normalizePaystackSettlementStatus("processing"), "processing");
  assert.equal(normalizePaystackSettlementStatus("pending"), "processing");
  assert.equal(normalizePaystackSettlementStatus("failed"), "failed");
  assert.equal(normalizePaystackSettlementStatus("new_status"), "review_required");
});

test("T+2 estimate skips weekends", () => {
  assert.equal(
    addWorkingDays(new Date("2026-08-14T10:00:00.000Z"), 2).toISOString(),
    "2026-08-18T10:00:00.000Z",
  );
});
