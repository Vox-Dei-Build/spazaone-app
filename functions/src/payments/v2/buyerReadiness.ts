import { PaymentReadiness, paymentReadiness } from "./readiness";
import {
  PAYSTACK_PAYMENT_CHANNELS,
  PaystackPaymentChannel,
} from "./paymentChannels";

export const BUYER_PAYMENT_CHANNELS = PAYSTACK_PAYMENT_CHANNELS;

export type BuyerPaymentCapability = {
  ready: boolean;
  reason: PaymentReadiness["reason"];
  channels: PaystackPaymentChannel[];
};

export type BuyerPaymentsV2 = {
  schemaVersion: 2;
  campaignCredits: BuyerPaymentCapability;
  ownedOrders: BuyerPaymentCapability;
  accountPayments: BuyerPaymentCapability;
  supplierOrders: BuyerPaymentCapability;
  manualTransferForOwnedOrders: boolean;
  supplierOrdersRequireOnlinePayment: boolean;
};

function safeCapability(
  value: PaymentReadiness,
  channels: PaystackPaymentChannel[] = [...BUYER_PAYMENT_CHANNELS],
): BuyerPaymentCapability {
  const allowed = new Set(channels);
  const providerChannels = value.channels ?? channels;
  return {
    ready: value.enabled,
    reason: value.reason,
    channels: value.enabled
      ? providerChannels.filter((channel) => allowed.has(channel))
      : [],
  };
}

export function buildBuyerPaymentsV2(input: {
  campaignCredits: PaymentReadiness;
  ownedOrders: PaymentReadiness;
  accountPayments: PaymentReadiness;
  supplierOrders: PaymentReadiness;
}): BuyerPaymentsV2 {
  return {
    schemaVersion: 2,
    campaignCredits: safeCapability(input.campaignCredits, ["card"]),
    ownedOrders: safeCapability(input.ownedOrders),
    accountPayments: safeCapability(input.accountPayments),
    supplierOrders: safeCapability(input.supplierOrders),
    manualTransferForOwnedOrders: !input.ownedOrders.enabled,
    supplierOrdersRequireOnlinePayment: false,
  };
}

/** Buyer-safe readiness shared by merchant app and direct WhatsApp. */
export async function buyerSafePaymentsV2(
  merchantId: string,
): Promise<BuyerPaymentsV2> {
  const [campaignCredits, ownedOrders, accountPayments, supplierOrders] =
    await Promise.all([
      paymentReadiness({ merchantId, purpose: "campaign_credit" }),
      paymentReadiness({ merchantId, purpose: "merchant_order" }),
      paymentReadiness({ merchantId, purpose: "account_settlement" }),
      paymentReadiness({ merchantId, purpose: "supplier_order" }),
    ]);
  return buildBuyerPaymentsV2({
    campaignCredits,
    ownedOrders,
    accountPayments,
    supplierOrders,
  });
}
