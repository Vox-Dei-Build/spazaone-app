import assert from "node:assert/strict";
import test from "node:test";

import {
  merchantCheckoutOptionDecision,
  merchantOrderingOptionsDefaults,
  merchantOrderingOptionsUpdate,
} from "../lib/ecommerce/merchantOrderingOptions.js";
import {
  applyMerchantBotFeatureAccess,
  requiredMerchantBotCheckoutFeatures,
  resolveMerchantBotFeatureAccess,
} from "../lib/ecommerce/merchantBotFeatureAccess.js";

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

test("new bot features require merchant build 88 by default", () => {
  const old = resolveMerchantBotFeatureAccess({ merchantBuild: 87 });
  const missing = resolveMerchantBotFeatureAccess({ merchantBuild: null });
  const legacyOverride = resolveMerchantBotFeatureAccess({
    merchantBuild: 87,
    whatsappEligibleOverride: true,
  });
  const current = resolveMerchantBotFeatureAccess({ merchantBuild: 88 });

  assert.equal(old.updateRequired, true);
  assert.equal(old.features.orderingOptions.enabled, false);
  assert.equal(old.features.ownedOrderPayments.enabled, false);
  assert.equal(old.features.accountPayments.enabled, false);
  assert.equal(old.features.supplierOrders.enabled, false);
  assert.equal(missing.features.orderingOptions.enabled, false);
  assert.equal(legacyOverride.features.ownedOrderPayments.enabled, false);
  assert.equal(old.features.supplierOrders.reason, "merchant_update_required");
  assert.equal(current.updateRequired, false);
  assert.equal(current.features.orderingOptions.enabled, true);
  assert.equal(current.features.ownedOrderPayments.enabled, true);
  assert.equal(current.features.accountPayments.enabled, true);
  assert.equal(current.features.supplierOrders.enabled, true);
});

test("bot feature minimum builds can advance independently", () => {
  const access = resolveMerchantBotFeatureAccess({
    merchantBuild: 88,
    config: {
      botFeatureMinimumBuilds: {
        orderingOptions: 89,
        ownedOrderPayments: 88,
        accountPayments: 90,
        supplierOrders: 91,
      },
    },
  });

  assert.equal(access.features.orderingOptions.enabled, false);
  assert.equal(access.features.ownedOrderPayments.enabled, true);
  assert.equal(access.features.accountPayments.minimumBuild, 90);
  assert.equal(access.features.supplierOrders.minimumBuild, 91);
});

test("old merchant builds receive legacy bot options only", () => {
  const access = resolveMerchantBotFeatureAccess({ merchantBuild: 87 });
  const result = applyMerchantBotFeatureAccess({
    access,
    orderingOptions: merchantOrderingOptionsUpdate({
      payLater: { enabled: true },
      delivery: {
        enabled: true,
        flatFeeMinor: 500,
        serviceAreaText: "Local area",
      },
    }),
    paymentsV2: {
      schemaVersion: 2,
      campaignCredits: {
        ready: true,
        reason: "ready",
        channels: ["eft"],
      },
      ownedOrders: {
        ready: true,
        reason: "ready",
        channels: ["card"],
      },
      accountPayments: {
        ready: true,
        reason: "ready",
        channels: ["card"],
      },
      supplierOrders: {
        ready: true,
        reason: "ready",
        channels: ["card"],
      },
      manualTransferForOwnedOrders: false,
      supplierOrdersRequireOnlinePayment: true,
    },
  });

  assert.deepEqual(result.orderingOptions, merchantOrderingOptionsDefaults());
  assert.equal(result.paymentsV2.campaignCredits.ready, true);
  assert.equal(result.paymentsV2.ownedOrders.ready, false);
  assert.equal(
    result.paymentsV2.ownedOrders.reason,
    "merchant_update_required",
  );
  assert.deepEqual(result.paymentsV2.ownedOrders.channels, []);
  assert.equal(result.paymentsV2.accountPayments.ready, false);
  assert.equal(result.paymentsV2.supplierOrders.ready, false);
  assert.equal(result.paymentsV2.manualTransferForOwnedOrders, true);
});

test("bot checkout identifies every feature required by the selected mode", () => {
  assert.deepEqual(
    requiredMerchantBotCheckoutFeatures({
      fulfillmentType: "pickup",
      paymentType: "cash",
      paymentRail: "",
    }),
    [],
  );
  assert.deepEqual(
    requiredMerchantBotCheckoutFeatures({
      fulfillmentType: "delivery",
      paymentType: "online",
      paymentRail: "paystack_v2",
    }),
    ["orderingOptions", "ownedOrderPayments"],
  );
  assert.deepEqual(
    requiredMerchantBotCheckoutFeatures({
      fulfillmentType: "pickup",
      paymentType: "pay_later",
      paymentRail: "",
    }),
    ["orderingOptions"],
  );
});
