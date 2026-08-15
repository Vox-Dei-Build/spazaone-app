import assert from "node:assert/strict";
import test from "node:test";
import { projectPaymentsV2OwnedSale } from "../lib/ecommerce/onlineSalesProjection.js";

test("projects a paid Payments V2 owned order with exact cent economics", () => {
  const row = projectPaymentsV2OwnedSale({
    merchantId: "merchant-a",
    saleId: "order-a",
    sale: {
      paymentRail: "paystack_v2",
      paymentIntentId: `pi_${"a".repeat(64)}`,
      paymentReference: "reference-a",
      paymentMethod: "Online",
      paymentStatus: "paid",
      status: "collected",
      amount: 140,
      itemsCount: 2,
      channelUsed: "eft",
    },
    intent: {
      intentId: `pi_${"a".repeat(64)}`,
      merchantId: "merchant-a",
      purpose: "merchant_order",
      businessBinding: { type: "owned_order", id: "order-a" },
      status: "paid",
      expectedAmountMinor: 14_000,
      providerAmountMinor: 14_000,
      actualMoney: {
        platformFeeMinor: 210,
        providerFeeMinor: 322,
        merchantNetProceedsMinor: 13_468,
      },
      selectedChannel: "eft",
    },
  });

  assert.equal(row.orderTotal, 140);
  assert.equal(row.amountPaid, 140);
  assert.equal(row.feeInclVat, 5.32);
  assert.equal(row.netAmount, 134.68);
  assert.equal(row.status, "collected");
  assert.equal(row.channel, "eft");
});

test("projects awaiting payment without inventing paid amounts or fees", () => {
  const row = projectPaymentsV2OwnedSale({
    merchantId: "merchant-a",
    saleId: "order-pending",
    sale: {
      paymentRail: "paystack_v2",
      paymentIntentId: `pi_${"b".repeat(64)}`,
      paymentStatus: "pending",
      status: "pending_payment",
      amount: 75,
      products: { bread: 2, milk: 1 },
    },
    intent: {
      intentId: `pi_${"b".repeat(64)}`,
      merchantId: "merchant-a",
      purpose: "merchant_order",
      businessBinding: { type: "owned_order", id: "order-pending" },
      status: "initialized",
      expectedAmountMinor: 7_500,
      selectedChannel: "card",
    },
  });

  assert.equal(row.amountPaid, 0);
  assert.equal(row.feeInclVat, 0);
  assert.equal(row.netAmount, 0);
  assert.equal(row.itemsCount, 3);
});

test("rejects mismatched order bindings and unexplained cents", () => {
  const base = {
    merchantId: "merchant-a",
    saleId: "order-a",
    sale: {
      paymentRail: "paystack_v2",
      paymentIntentId: `pi_${"c".repeat(64)}`,
      amount: 100,
    },
    intent: {
      intentId: `pi_${"c".repeat(64)}`,
      merchantId: "merchant-a",
      purpose: "merchant_order",
      businessBinding: { type: "owned_order", id: "different-order" },
      status: "paid",
      expectedAmountMinor: 10_000,
      providerAmountMinor: 10_000,
      actualMoney: {
        platformFeeMinor: 150,
        providerFeeMinor: 300,
        merchantNetProceedsMinor: 9_550,
      },
    },
  };
  assert.throws(
    () => projectPaymentsV2OwnedSale(base),
    /OWNED_ORDER_PAYMENT_BINDING_MISMATCH/,
  );

  assert.throws(
    () =>
      projectPaymentsV2OwnedSale({
        ...base,
        intent: {
          ...base.intent,
          businessBinding: { type: "owned_order", id: "order-a" },
          providerAmountMinor: 9_999,
        },
      }),
    /OWNED_ORDER_PROVIDER_AMOUNT_MISMATCH/,
  );
});
