import { db } from "../config/main";
import { BuyerPaymentsV2 } from "../payments/v2/buyerReadiness";
import {
  MerchantOrderingOptions,
  merchantOrderingOptionsDefaults,
} from "./merchantOrderingOptions";

export const DEFAULT_MERCHANT_BOT_FEATURE_MINIMUM_BUILD = 88;

export const MERCHANT_BOT_FEATURES = [
  "orderingOptions",
  "ownedOrderPayments",
  "accountPayments",
  "supplierOrders",
] as const;

export type MerchantBotFeature = (typeof MERCHANT_BOT_FEATURES)[number];

export type MerchantBotFeatureDecision = {
  enabled: boolean;
  reason: "ready" | "merchant_update_required";
  merchantBuild: number;
  minimumBuild: number;
};

export type MerchantBotFeatureAccess = {
  schemaVersion: 1;
  merchantBuild: number;
  updateRequired: boolean;
  features: Record<MerchantBotFeature, MerchantBotFeatureDecision>;
};

function safeBuild(value: unknown): number {
  const build = Number(value);
  return Number.isSafeInteger(build) && build > 0 ? build : 0;
}

function configuredMinimumBuild(
  config: Record<string, unknown>,
  feature: MerchantBotFeature,
): number {
  const configured = config.botFeatureMinimumBuilds;
  if (!configured || typeof configured !== "object") {
    return DEFAULT_MERCHANT_BOT_FEATURE_MINIMUM_BUILD;
  }
  const minimum = safeBuild((configured as Record<string, unknown>)[feature]);
  return minimum || DEFAULT_MERCHANT_BOT_FEATURE_MINIMUM_BUILD;
}

/**
 * New WhatsApp capabilities require a recent authenticated merchant-app
 * heartbeat. Legacy WhatsApp access overrides deliberately do not participate
 * in this decision, so they cannot expose newer order or payment behaviour.
 */
export function resolveMerchantBotFeatureAccess(input: {
  merchantBuild: unknown;
  config?: Record<string, unknown>;
}): MerchantBotFeatureAccess {
  const merchantBuild = safeBuild(input.merchantBuild);
  const config = input.config ?? {};
  const features = Object.fromEntries(
    MERCHANT_BOT_FEATURES.map((feature) => {
      const minimumBuild = configuredMinimumBuild(config, feature);
      const enabled = merchantBuild >= minimumBuild;
      return [
        feature,
        {
          enabled,
          reason: enabled ? "ready" : "merchant_update_required",
          merchantBuild,
          minimumBuild,
        } satisfies MerchantBotFeatureDecision,
      ];
    }),
  ) as Record<MerchantBotFeature, MerchantBotFeatureDecision>;
  return {
    schemaVersion: 1,
    merchantBuild,
    updateRequired: MERCHANT_BOT_FEATURES.some(
      (feature) => !features[feature].enabled,
    ),
    features,
  };
}

export async function loadMerchantBotFeatureAccess(
  merchantId: string,
): Promise<MerchantBotFeatureAccess> {
  const [merchant, config] = await Promise.all([
    db.doc(`users/${merchantId}`).get(),
    db.doc("config/app").get(),
  ]);
  return resolveMerchantBotFeatureAccess({
    merchantBuild: merchant.data()?.buildNumber,
    config: config.data(),
  });
}

export async function merchantBotFeatureDecision(
  merchantId: string,
  feature: MerchantBotFeature,
): Promise<MerchantBotFeatureDecision> {
  return (await loadMerchantBotFeatureAccess(merchantId)).features[feature];
}

function unavailableCapability(
  current: BuyerPaymentsV2["ownedOrders"],
): BuyerPaymentsV2["ownedOrders"] {
  return {
    ...current,
    ready: false,
    reason: "merchant_update_required",
    channels: [],
  };
}

export function applyMerchantBotFeatureAccess(input: {
  paymentsV2: BuyerPaymentsV2;
  orderingOptions: MerchantOrderingOptions;
  access: MerchantBotFeatureAccess;
}): {
  paymentsV2: BuyerPaymentsV2;
  orderingOptions: MerchantOrderingOptions;
} {
  const paymentsV2: BuyerPaymentsV2 = {
    ...input.paymentsV2,
    ownedOrders: input.access.features.ownedOrderPayments.enabled
      ? input.paymentsV2.ownedOrders
      : unavailableCapability(input.paymentsV2.ownedOrders),
    accountPayments: input.access.features.accountPayments.enabled
      ? input.paymentsV2.accountPayments
      : unavailableCapability(input.paymentsV2.accountPayments),
    supplierOrders: input.access.features.supplierOrders.enabled
      ? input.paymentsV2.supplierOrders
      : unavailableCapability(input.paymentsV2.supplierOrders),
    manualTransferForOwnedOrders:
      !input.access.features.ownedOrderPayments.enabled ||
      input.paymentsV2.manualTransferForOwnedOrders,
  };
  return {
    paymentsV2,
    orderingOptions: input.access.features.orderingOptions.enabled
      ? input.orderingOptions
      : merchantOrderingOptionsDefaults(),
  };
}

export function requiredMerchantBotCheckoutFeatures(input: {
  fulfillmentType: unknown;
  paymentType: unknown;
  paymentRail: unknown;
}): MerchantBotFeature[] {
  const features = new Set<MerchantBotFeature>();
  const fulfillment = String(input.fulfillmentType ?? "pickup")
    .trim()
    .toLowerCase();
  const payment = String(input.paymentType ?? "online")
    .trim()
    .toLowerCase();
  const rail = String(input.paymentRail ?? "")
    .trim()
    .toLowerCase();
  if (
    fulfillment === "delivery" ||
    payment === "bnpl" ||
    payment === "pay_later"
  ) {
    features.add("orderingOptions");
  }
  if (payment === "online" && rail === "paystack_v2") {
    features.add("ownedOrderPayments");
  }
  return [...features];
}
