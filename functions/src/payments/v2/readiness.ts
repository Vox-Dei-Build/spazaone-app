import { db } from "../../config/main";
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
    | "merchant_capability_disabled";
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
  emergencySuspended?: boolean;
  globalCapabilities: CapabilityMap;
  merchantStatus: MerchantPaymentStatus;
  merchantCapabilities: CapabilityMap;
  purpose: PaymentPurpose;
}): PaymentReadiness {
  if (!input.masterEnabled)
    return { enabled: false, reason: "master_disabled" };
  if (input.emergencySuspended === true) {
    return { enabled: false, reason: "global_suspended" };
  }
  if (input.globalCapabilities[input.purpose] !== true) {
    return { enabled: false, reason: "capability_disabled" };
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
