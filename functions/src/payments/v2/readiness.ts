import { db } from "../../config/main";
import { paystackAccountPaymentCanaryEnabled } from "../../config/environment";
import {
  isPaymentPurpose,
  MerchantPaymentStatus,
  PaymentPurpose,
} from "./domain";

type CapabilityMap = Partial<Record<PaymentPurpose, boolean>>;

export type PaymentReadiness = {
  enabled: boolean;
  reason:
    | "ready"
    | "master_disabled"
    | "global_suspended"
    | "capability_disabled"
    | "merchant_not_enabled"
    | "merchant_capability_disabled"
    | "merchant_update_required";
};

function envEnabled(value: unknown): boolean {
  return (
    String(value ?? "")
      .trim()
      .toLowerCase() === "true"
  );
}

export function resolvePaymentReadiness(input: {
  masterEnabled: boolean;
  accountPaymentCanaryEnabled?: boolean;
  emergencySuspended?: boolean;
  globalCapabilities: CapabilityMap;
  merchantStatus: MerchantPaymentStatus;
  merchantCapabilities: CapabilityMap;
  purpose: PaymentPurpose;
}): PaymentReadiness {
  const accountPaymentCanaryEnabled =
    input.accountPaymentCanaryEnabled === true &&
    input.purpose === "account_settlement";
  if (!input.masterEnabled && !accountPaymentCanaryEnabled)
    return { enabled: false, reason: "master_disabled" };
  if (input.emergencySuspended === true) {
    return { enabled: false, reason: "global_suspended" };
  }
  if (
    input.globalCapabilities[input.purpose] !== true &&
    !accountPaymentCanaryEnabled
  ) {
    return { enabled: false, reason: "capability_disabled" };
  }
  // Campaign Credits are purchased from Spaza One and never settle to a
  // merchant bank account. Requiring a Paystack subaccount here would couple
  // optional messaging credit to an unrelated settlement destination. A
  // suspended merchant is still blocked, while a missing per-merchant flag is
  // treated as the default-on state once the global capability is enabled.
  if (input.purpose === "campaign_credit") {
    if (input.merchantStatus === "suspended") {
      return { enabled: false, reason: "merchant_not_enabled" };
    }
    if (input.merchantCapabilities.campaign_credit === false) {
      return { enabled: false, reason: "merchant_capability_disabled" };
    }
    return { enabled: true, reason: "ready" };
  }
  if (input.merchantStatus !== "enabled") {
    return { enabled: false, reason: "merchant_not_enabled" };
  }
  if (input.merchantCapabilities[input.purpose] !== true) {
    return { enabled: false, reason: "merchant_capability_disabled" };
  }
  return { enabled: true, reason: "ready" };
}

export async function paymentReadiness(input: {
  merchantId: string;
  purpose: PaymentPurpose;
}): Promise<PaymentReadiness> {
  if (!isPaymentPurpose(input.purpose)) {
    return { enabled: false, reason: "capability_disabled" };
  }
  const [global, merchant] = await Promise.all([
    db.doc("paymentConfiguration/global").get(),
    db.doc(`merchantPaymentProfiles/${input.merchantId}`).get(),
  ]);
  const globalData = global.data() ?? {};
  const merchantData = merchant.data() ?? {};
  return resolvePaymentReadiness({
    masterEnabled: envEnabled(process.env.PAYMENTS_V2_MASTER_ENABLED),
    accountPaymentCanaryEnabled: paystackAccountPaymentCanaryEnabled(input),
    emergencySuspended: globalData.emergencySuspended === true,
    globalCapabilities:
      (globalData.capabilities as CapabilityMap | undefined) ?? {},
    merchantStatus: String(
      merchantData.status ?? "not_started",
    ) as MerchantPaymentStatus,
    merchantCapabilities:
      (merchantData.capabilities as CapabilityMap | undefined) ?? {},
    purpose: input.purpose,
  });
}
