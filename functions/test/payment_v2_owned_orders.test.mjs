import assert from "node:assert/strict";
import test from "node:test";
import { estimatedOwnedOrderProviderFeeMinor } from "../lib/payments/v2/ownedOrders.js";
import { shouldReleaseReservationOnCancel } from "../lib/ecommerce/cancelOrder.js";

test("owned order fee estimate is conservative and uses cents", () => {
  assert.equal(
    estimatedOwnedOrderProviderFeeMinor({
      amountMinor: 10_000,
      channel: "eft",
    }),
    230,
  );
  assert.equal(
    estimatedOwnedOrderProviderFeeMinor({
      amountMinor: 10_000,
      channel: "card",
    }),
    472,
  );
  assert.equal(
    estimatedOwnedOrderProviderFeeMinor({ amountMinor: 999, channel: "qr" }),
    33,
  );
});

test("owned order channels fail closed", () => {
  assert.throws(
    () =>
      estimatedOwnedOrderProviderFeeMinor({
        amountMinor: 10_000,
        channel: "cash",
      }),
    /ORDER_CHANNEL_INVALID/,
  );
});

test("refund-pending paid stock is never released by a cancel replay", () => {
  assert.equal(
    shouldReleaseReservationOnCancel(
      {
        paymentRail: "paystack_v2",
        paymentStatus: "refund_pending",
        inventoryReserved: true,
      },
      "reservation-1",
    ),
    false,
  );
  assert.equal(
    shouldReleaseReservationOnCancel(
      {
        paymentRail: "paystack_v2",
        paymentStatus: "pending",
        inventoryReserved: true,
      },
      "reservation-1",
    ),
    true,
  );
});
