import assert from "node:assert/strict";
import test from "node:test";
import {
  canManuallyConfirmCommerceRefund,
  paymentStatusAfterAction,
  priceCommerceOrder,
  supplierFundingPublicFailure,
  targetStatusForAction,
} from "../lib/commerce/domain.js";
import { commercePaymentsEnabled } from "../lib/commerce/readiness.js";
import { checkoutPage } from "../lib/commerce/checkoutPage.js";

test("digital payment activation fails closed", () => {
  const original = process.env.COMMERCE_PAYMENTS_ENABLED;
  try {
    delete process.env.COMMERCE_PAYMENTS_ENABLED;
    assert.equal(commercePaymentsEnabled(), false);
    process.env.COMMERCE_PAYMENTS_ENABLED = "false";
    assert.equal(commercePaymentsEnabled(), false);
    process.env.COMMERCE_PAYMENTS_ENABLED = " true ";
    assert.equal(commercePaymentsEnabled(), true);
  } finally {
    if (original === undefined) {
      delete process.env.COMMERCE_PAYMENTS_ENABLED;
    } else {
      process.env.COMMERCE_PAYMENTS_ENABLED = original;
    }
  }
});

test("supplier funding failures are buyer-safe and confirm no charge", () => {
  const unavailable = supplierFundingPublicFailure("CJ_BALANCE_INSUFFICIENT");
  assert.deepEqual(unavailable, {
    code: "SUPPLIER_CHECKOUT_UNAVAILABLE",
    message:
      "Supplier delivery payment is temporarily unavailable. You have not been charged. Please try again later.",
  });
  assert.equal(
    supplierFundingPublicFailure("SUPPLIER_FUNDING_STATE_INVALID")?.code,
    "SUPPLIER_CHECKOUT_UNAVAILABLE",
  );
  assert.equal(supplierFundingPublicFailure("CJ_OUT_OF_STOCK"), null);
});

test("hosted supplier checkout quotes quantity and profitable channels before payment", () => {
  const html = checkoutPage({
    listingId: "listing-1",
    title: "Solar Lamp",
    description: "A lamp",
    image: "",
    sellPriceMinor: 10_000,
    shippingNotes: "",
    digitalPaymentsEnabled: true,
  });
  assert.match(html, /id="quantity"/);
  assert.match(html, /preparePublicCommerceCheckout/);
  assert.match(html, /paymentOptions/);
  assert.match(html, /name='paymentChannel'/);
  assert.match(html, /Capitec Pay/);
  assert.match(html, /Scan to Pay/);
});

test("server pricing ignores a tampered client total", () => {
  const priced = priceCommerceOrder({
    baseCostMinor: 10_000,
    sellPriceMinor: 14_000,
    quantity: 1,
    // Deliberately present at runtime; the domain only accepts canonical
    // listing values selected by createCommerceOrder.
    clientAmountMinor: 1,
  });
  assert.equal(priced.amountDueMinor, 14_000);
  assert.equal(priced.baseCostMinor, 10_000);
  assert.equal(priced.feeMinor, 582);
  assert.equal(priced.marginMinor, 3_418);
});

test("manual order pricing snapshots zero provider fee", () => {
  const priced = priceCommerceOrder({
    baseCostMinor: 10_000,
    sellPriceMinor: 14_000,
    paymentFeeMinor: 0,
  });
  assert.equal(priced.feeMinor, 0);
  assert.equal(priced.marginMinor, 4_000);
  assert.equal(priced.amountDueMinor, 14_000);
});

test("pricing rejects unsupported quantities and loss-making listings", () => {
  assert.equal(
    priceCommerceOrder({
      baseCostMinor: 10_000,
      sellPriceMinor: 14_000,
      quantity: 2,
    }).quantity,
    2,
  );
  assert.throws(
    () =>
      priceCommerceOrder({
        baseCostMinor: 10_000,
        sellPriceMinor: 14_000,
        quantity: 21,
      }),
    /QUANTITY_INVALID/,
  );
  assert.throws(
    () =>
      priceCommerceOrder({
        baseCostMinor: 10_000,
        sellPriceMinor: 10_100,
      }),
    /MARGIN_NEGATIVE_AFTER_FEES/,
  );
});

test("fulfilment lifecycle permits only explicit forward transitions", () => {
  assert.equal(
    targetStatusForAction(
      "pending_payment",
      "confirm_manual_payment",
      "awaiting_manual_confirmation",
    ),
    "paid",
  );
  assert.equal(
    paymentStatusAfterAction(
      "awaiting_manual_confirmation",
      "confirm_manual_payment",
    ),
    "paid",
  );
  assert.equal(
    targetStatusForAction("paid", "submit_for_fulfilment", "paid"),
    "submitted_for_fulfilment",
  );
  assert.equal(
    targetStatusForAction("submitted_for_fulfilment", "mark_shipped", "paid"),
    "shipped",
  );
  assert.equal(
    targetStatusForAction("shipped", "mark_delivered", "paid"),
    "delivered",
  );
  assert.throws(
    () =>
      targetStatusForAction(
        "pending_payment",
        "confirm_manual_payment",
        "pending",
      ),
    /MANUAL_PAYMENT_NOT_PENDING/,
  );
  assert.throws(
    () => targetStatusForAction("paid", "mark_delivered", "paid"),
    /TRANSITION_INVALID/,
  );
  assert.throws(
    () => targetStatusForAction("delivered", "cancel", "paid"),
    /TRANSITION_INVALID/,
  );
});

test("paid cancellation creates a refund path", () => {
  assert.equal(
    paymentStatusAfterAction("awaiting_manual_confirmation", "cancel"),
    "cancelled",
  );
  assert.equal(paymentStatusAfterAction("paid", "cancel"), "refund_pending");
  assert.equal(
    targetStatusForAction("cancelled", "mark_refunded", "refund_pending"),
    "refunded",
  );
  assert.throws(
    () => targetStatusForAction("cancelled", "mark_refunded", "paid"),
    /REFUND_NOT_PENDING/,
  );
});

test("provider refunds cannot be completed by a merchant action", () => {
  assert.equal(canManuallyConfirmCommerceRefund("manual"), true);
  assert.equal(canManuallyConfirmCommerceRefund("paystack"), false);
  assert.equal(canManuallyConfirmCommerceRefund(""), false);
});
