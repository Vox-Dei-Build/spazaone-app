import assert from "node:assert/strict";
import test from "node:test";
import { supplierPaymentEconomics } from "../lib/payments/v2/supplierOrders.js";

test("supplier gross preserves landed cost, collection fee and markup", () => {
  const result = supplierPaymentEconomics({
    landedCostMinor: 5_000,
    markupMinor: 2_000,
    safetyMarginMinor: 100,
  });
  assert.equal(result.customerTotalMinor - result.collectionFeeMinor, 7_000);
  assert.equal(result.money.retainedCostMinor, 5_000);
  assert.equal(result.money.platformFeeMinor, result.collectionFeeMinor);
  assert.equal(result.money.merchantGrossShareMinor, 2_000);
  assert.ok(result.merchantNetProceedsMinor >= 100);
});

test("supplier checkout blocks markup that cannot carry fees and safety", () => {
  assert.throws(
    () =>
      supplierPaymentEconomics({
        landedCostMinor: 5_000,
        markupMinor: 100,
        safetyMarginMinor: 100,
      }),
    /SUPPLIER_MARGIN_BELOW_SAFETY/,
  );
});
