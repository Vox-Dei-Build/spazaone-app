export const COMMERCE_ORDER_STATUSES = [
  "pending_payment",
  "paid",
  "submitted_for_fulfilment",
  "shipped",
  "delivered",
  "cancelled",
  "refunded",
] as const;

export type CommerceOrderStatus = (typeof COMMERCE_ORDER_STATUSES)[number];

export type CommerceOrderAction =
  | "confirm_manual_payment"
  | "submit_for_fulfilment"
  | "mark_shipped"
  | "mark_delivered"
  | "cancel"
  | "mark_refunded";

export type CommercePriceSnapshot = {
  currency: "ZAR";
  quantity: number;
  baseCostMinor: number;
  sellPriceMinor: number;
  feeMinor: number;
  marginMinor: number;
  amountDueMinor: number;
};

export type CommerceCheckoutPublicFailure = {
  code: "SUPPLIER_CHECKOUT_UNAVAILABLE";
  message: string;
};

/**
 * Translates server-only supplier funding failures into a buyer-safe response.
 * These failures happen before Paystack initialization, so it is accurate and
 * important to state that no charge was made without exposing CJ internals.
 */
export function supplierFundingPublicFailure(
  errorCode: unknown,
): CommerceCheckoutPublicFailure | null {
  const code = String(errorCode ?? "");
  if (
    code !== "CJ_BALANCE_INSUFFICIENT" &&
    code !== "SUPPLIER_FUNDING_STATE_INVALID"
  ) {
    return null;
  }
  return {
    code: "SUPPLIER_CHECKOUT_UNAVAILABLE",
    message:
      "Supplier delivery payment is temporarily unavailable. You have not been charged. Please try again later.",
  };
}

const ACTION_TARGETS: Record<
  CommerceOrderAction,
  readonly CommerceOrderStatus[]
> = {
  confirm_manual_payment: ["pending_payment"],
  submit_for_fulfilment: ["paid"],
  mark_shipped: ["submitted_for_fulfilment"],
  mark_delivered: ["shipped"],
  cancel: ["pending_payment", "paid", "submitted_for_fulfilment"],
  mark_refunded: ["cancelled"],
};

export function requireMinorUnits(value: unknown, field: string): number {
  const amount = Number(value);
  if (!Number.isSafeInteger(amount) || amount < 0) {
    throw new Error(`${field.toUpperCase()}_INVALID`);
  }
  return amount;
}

export function priceCommerceOrder(input: {
  baseCostMinor: unknown;
  sellPriceMinor: unknown;
  quantity?: unknown;
  paymentFeeMinor?: unknown;
}): CommercePriceSnapshot {
  const baseCostMinor = requireMinorUnits(input.baseCostMinor, "base_cost");
  const unitSellPriceMinor = requireMinorUnits(
    input.sellPriceMinor,
    "sell_price",
  );
  const quantity = Number(input.quantity ?? 1);
  if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 20) {
    throw new Error("QUANTITY_INVALID");
  }
  if (unitSellPriceMinor <= baseCostMinor) {
    throw new Error("SELL_PRICE_TOO_LOW");
  }

  const sellPriceMinor = unitSellPriceMinor * quantity;
  const totalBaseCostMinor = baseCostMinor * quantity;
  // Manual orders have an explicit zero fee. When digital payment is enabled,
  // match Spaza One's existing local-card quote: 2.9% + R1, then 15% VAT.
  const feeMinor =
    input.paymentFeeMinor === undefined
      ? Math.round((sellPriceMinor * 0.029 + 100) * 1.15)
      : requireMinorUnits(input.paymentFeeMinor, "payment_fee");
  const marginMinor = sellPriceMinor - totalBaseCostMinor - feeMinor;
  if (marginMinor < 0) {
    throw new Error("MARGIN_NEGATIVE_AFTER_FEES");
  }

  return {
    currency: "ZAR",
    quantity,
    baseCostMinor: totalBaseCostMinor,
    sellPriceMinor,
    feeMinor,
    marginMinor,
    amountDueMinor: sellPriceMinor,
  };
}

/** Prices a live-quoted supplier order without an online collection fee. */
export function priceManualSupplierOrder(input: {
  landedCostMinor: unknown;
  unitMarkupMinor: unknown;
  quantity: unknown;
}): CommercePriceSnapshot {
  const baseCostMinor = requireMinorUnits(input.landedCostMinor, "landed_cost");
  const unitMarkupMinor = requireMinorUnits(
    input.unitMarkupMinor,
    "unit_markup",
  );
  const quantity = Number(input.quantity);
  if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 20) {
    throw new Error("QUANTITY_INVALID");
  }
  if (baseCostMinor <= 0 || unitMarkupMinor <= 0) {
    throw new Error("SUPPLIER_PRICE_INVALID");
  }
  const marginMinor = unitMarkupMinor * quantity;
  const sellPriceMinor = baseCostMinor + marginMinor;
  return {
    currency: "ZAR",
    quantity,
    baseCostMinor,
    sellPriceMinor,
    feeMinor: 0,
    marginMinor,
    amountDueMinor: sellPriceMinor,
  };
}

export function targetStatusForAction(
  currentStatus: unknown,
  actionValue: unknown,
  paymentStatus: unknown,
): CommerceOrderStatus {
  const current = String(currentStatus ?? "") as CommerceOrderStatus;
  const action = String(actionValue ?? "") as CommerceOrderAction;
  if (!COMMERCE_ORDER_STATUSES.includes(current)) {
    throw new Error("STATUS_INVALID");
  }
  if (!Object.prototype.hasOwnProperty.call(ACTION_TARGETS, action)) {
    throw new Error("ACTION_INVALID");
  }
  if (!ACTION_TARGETS[action].includes(current)) {
    throw new Error("TRANSITION_INVALID");
  }
  if (
    action === "confirm_manual_payment" &&
    String(paymentStatus ?? "") !== "awaiting_manual_confirmation"
  ) {
    throw new Error("MANUAL_PAYMENT_NOT_PENDING");
  }
  if (
    action === "mark_refunded" &&
    String(paymentStatus ?? "") !== "refund_pending"
  ) {
    throw new Error("REFUND_NOT_PENDING");
  }

  switch (action) {
    case "confirm_manual_payment":
      return "paid";
    case "submit_for_fulfilment":
      return "submitted_for_fulfilment";
    case "mark_shipped":
      return "shipped";
    case "mark_delivered":
      return "delivered";
    case "cancel":
      return "cancelled";
    case "mark_refunded":
      return "refunded";
  }
}

export function paymentStatusAfterAction(
  currentPaymentStatus: unknown,
  actionValue: unknown,
): string {
  const current = String(currentPaymentStatus ?? "pending");
  const action = String(actionValue ?? "") as CommerceOrderAction;
  if (action === "confirm_manual_payment") return "paid";
  if (action === "cancel" && current === "paid") return "refund_pending";
  if (
    action === "cancel" &&
    ["pending", "awaiting_manual_confirmation"].includes(current)
  ) {
    return "cancelled";
  }
  if (action === "mark_refunded") return "refunded";
  return current;
}

/** Manual refund confirmation is only valid for money collected outside the
 * provider. Paystack refunds are advanced by provider-confirmed V2 events. */
export function canManuallyConfirmCommerceRefund(
  paymentProvider: unknown,
): boolean {
  return (
    String(paymentProvider ?? "")
      .trim()
      .toLowerCase() === "manual"
  );
}
