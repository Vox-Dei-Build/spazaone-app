import { PaymentReadiness, paymentReadiness } from "./readiness";

export const BUYER_PAYMENT_CHANNELS = [
  "card",
  "eft",
  "capitec_pay",
  "qr",
] as const;

export type BuyerPaymentCapability = {
  ready: boolean;
  reason: PaymentReadiness["reason"];
  channels: Array<(typeof BUYER_PAYMENT_CHANNELS)[number]>;
};

export type BuyerPaymentsV2 = {
  schemaVersion: 2;
  campaignCredits: BuyerPaymentCapability;
  ownedOrders: BuyerPaymentCapability;
  accountPayments: BuyerPaymentCapability;
  supplierOrders: BuyerPaymentCapability;
  manualTransferForOwnedOrders: boolean;
  supplierOrdersRequireOnlinePayment: true;
};

function safeCapability(value: PaymentReadiness): BuyerPaymentCapability {
  return {
    ready: value.enabled,
    reason: value.reason,
    channels: value.enabled ? [...BUYER_PAYMENT_CHANNELS] : [],
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
    campaignCredits: safeCapability(input.campaignCredits),
    ownedOrders: safeCapability(input.ownedOrders),
    accountPayments: safeCapability(input.accountPayments),
    supplierOrders: safeCapability(input.supplierOrders),
    manualTransferForOwnedOrders: !input.ownedOrders.enabled,
    supplierOrdersRequireOnlinePayment: true,
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
