import assert from "node:assert/strict";
import test from "node:test";
import {
  profitableSupplierChannels,
  supplierFulfilmentFailureDisposition,
  supplierOperationsResolutionDecision,
  supplierPaymentEconomics,
} from "../lib/payments/v2/supplierOrders.js";

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

test("supplier quantities snapshot per-unit markup at 1, 5 and the risk cap", () => {
  for (const quantity of [1, 5, 20]) {
    const result = supplierPaymentEconomics({
      landedCostMinor: 5_000 * quantity,
      markupMinor: 500,
      safetyMarginMinor: 100,
      quantity,
      channel: "eft",
    });
    assert.equal(result.quantity, quantity);
    assert.equal(result.markupMinor, 500 * quantity);
  }
  assert.throws(
    () =>
      supplierPaymentEconomics({
        landedCostMinor: 105_000,
        markupMinor: 500,
        quantity: 21,
      }),
    /SUPPLIER_QUANTITY_INVALID/,
  );
});

test("supplier checkout exposes every profitable Paystack channel only", () => {
  assert.deepEqual(
    profitableSupplierChannels({
      landedCostMinor: 5_000,
      markupMinor: 500,
      safetyMarginMinor: 100,
    }),
    ["card", "eft", "capitec_pay", "qr"],
  );
  assert.deepEqual(
    profitableSupplierChannels({
      landedCostMinor: 5_000,
      markupMinor: 250,
      safetyMarginMinor: 100,
    }),
    ["eft", "capitec_pay"],
    "card and Scan to Pay are hidden when their fees breach R1 safety",
  );
});

test("supplier provider failures choose one safe accountable outcome", () => {
  assert.equal(
    supplierFulfilmentFailureDisposition({
      code: "CJ_UNAVAILABLE",
      providerOrderAbsent: null,
    }),
    "retry",
    "a pre-create transient can retry because no provider order is known",
  );
  assert.equal(
    supplierFulfilmentFailureDisposition({
      code: "CJ_PRICE_OR_ROUTE_CHANGED",
      providerOrderAbsent: true,
    }),
    "refund_pending",
    "a deterministic pre-create failure can enter the provider refund path",
  );
  assert.equal(
    supplierFulfilmentFailureDisposition({
      code: "CJ_PAYMENT_OUTCOME_AMBIGUOUS",
      cjOrderId: "cj-order-1",
      providerOrderAbsent: false,
    }),
    "operations_review",
    "an ambiguous post-create payment can never retry or promise a refund",
  );
  assert.equal(
    supplierFulfilmentFailureDisposition({
      code: "CJ_ACTUAL_CHARGE_EXCEEDS_SNAPSHOT",
      cjOrderId: "cj-order-1",
      providerOrderAbsent: false,
    }),
    "operations_review",
    "an extant provider order blocks automatic refund even on a bad charge",
  );
});

test("operations resolves a supplier ambiguity only after CJ proves absence", () => {
  assert.equal(
    supplierOperationsResolutionDecision({
      action: "retry",
      fulfilmentStatus: "operations_review",
      providerOrderAbsent: true,
    }),
    "retry",
  );
  assert.equal(
    supplierOperationsResolutionDecision({
      action: "refund",
      fulfilmentStatus: "operations_review",
      providerOrderAbsent: true,
    }),
    "refund",
  );
  assert.throws(
    () =>
      supplierOperationsResolutionDecision({
        action: "retry",
        fulfilmentStatus: "operations_review",
        providerOrderAbsent: null,
      }),
    /CJ_OUTCOME_STILL_AMBIGUOUS/,
  );
  assert.throws(
    () =>
      supplierOperationsResolutionDecision({
        action: "refund",
        fulfilmentStatus: "operations_review",
        cjOrderId: "cj-existing-order",
        providerOrderAbsent: false,
      }),
    /CJ_ORDER_EXISTS_REVIEW_REQUIRED/,
  );
});
