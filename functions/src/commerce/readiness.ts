import { paystackPaymentCanaryEnabled } from "../config/environment";

/**
 * Digital payment is deliberately fail-closed until provider approval is
 * complete. Manual order requests remain available while this is false.
 */
export function commercePaymentsEnabled(merchantId?: string): boolean {
  const globallyEnabled =
    String(process.env.COMMERCE_PAYMENTS_ENABLED ?? "")
      .trim()
      .toLowerCase() === "true";
  if (globallyEnabled) return true;
  const exactMerchantId = String(merchantId ?? "").trim();
  return exactMerchantId
    ? paystackPaymentCanaryEnabled({
        merchantId: exactMerchantId,
        purpose: "supplier_order",
      })
    : false;
}
