import assert from "node:assert/strict";
import test from "node:test";

import {
  merchantCheckoutOptionDecision,
  merchantOrderingOptionsDefaults,
  merchantOrderingOptionsUpdate,
} from "../lib/ecommerce/merchantOrderingOptions.js";

test("merchant ordering options default pickup on and optional modes off", () => {
  assert.deepEqual(merchantOrderingOptionsDefaults(), {
    version: 1,
    pickup: { enabled: true },
    payLater: { enabled: false },
    delivery: { enabled: false, flatFeeMinor: 0, serviceAreaText: "" },
  });
});

test("delivery settings require a service area and accept a flat fee", () => {
  assert.throws(
    () =>
      merchantOrderingOptionsUpdate({
        payLater: { enabled: false },
        delivery: { enabled: true, flatFeeMinor: 500, serviceAreaText: "" },
      }),
    /SERVICE_AREA_REQUIRED/,
  );
  assert.equal(
    merchantOrderingOptionsUpdate({
      payLater: { enabled: true },
      delivery: {
        enabled: true,
        flatFeeMinor: 500,
        serviceAreaText: "Within 5 km of the shop",
      },
    }).delivery.flatFeeMinor,
    500,
  );
});

test("checkout enforces enabled modes and server delivery fees", () => {
  const options = merchantOrderingOptionsUpdate({
    payLater: { enabled: true },
    delivery: {
      enabled: true,
      flatFeeMinor: 750,
      serviceAreaText: "Local area",
    },
  });
  const result = merchantCheckoutOptionDecision({
    options,
    fulfillmentType: "delivery",
    paymentType: "online",
    deliveryAddress: "1 Main Road",
    subtotalMinor: 10_000,
    claimedDeliveryFeeMinor: 750,
    claimedTotalMinor: 10_750,
  });
  assert.equal(result.totalMinor, 10_750);
  assert.equal(result.requiresMerchantReview, true);
  assert.throws(
    () =>
      merchantCheckoutOptionDecision({
        options,
        fulfillmentType: "delivery",
        paymentType: "online",
        deliveryAddress: "1 Main Road",
        subtotalMinor: 10_000,
        claimedDeliveryFeeMinor: 1,
      }),
    /DELIVERY_FEE_MISMATCH/,
  );
});

test("pickup online payment can proceed while delivery waits for approval", () => {
  const options = merchantOrderingOptionsDefaults();
  assert.equal(
    merchantCheckoutOptionDecision({
      options,
      fulfillmentType: "pickup",
      paymentType: "online",
      deliveryAddress: "",
      subtotalMinor: 2_000,
    }).requiresMerchantReview,
    false,
  );
  assert.throws(
    () =>
      merchantCheckoutOptionDecision({
        options,
        fulfillmentType: "delivery",
        paymentType: "online",
        deliveryAddress: "1 Main Road",
        subtotalMinor: 2_000,
      }),
    /DELIVERY_DISABLED/,
  );
  assert.throws(
    () =>
      merchantCheckoutOptionDecision({
        options,
        fulfillmentType: "pickup",
        paymentType: "bnpl",
        deliveryAddress: "",
        subtotalMinor: 2_000,
      }),
    /PAY_LATER_DISABLED/,
  );
});
