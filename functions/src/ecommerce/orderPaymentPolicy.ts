export const PAYMENT_RECEIPT_ACTIONS = new Set([
  "MARK_CASH_RECEIVED",
  "SETTLE_BNPL",
]);

export function isPaymentReceiptAction(action: string): boolean {
  return PAYMENT_RECEIPT_ACTIONS.has(action);
}

export function isPaymentAlreadyRecorded(
  orderData: Record<string, unknown>,
): boolean {
  const paymentStatus = String(orderData.paymentStatus ?? "").toLowerCase();
  const status = String(orderData.status ?? "").toLowerCase();
  return (
    paymentStatus === "paid" ||
    status === "paid" ||
    orderData.cashReceivedAt != null ||
    orderData.paidAt != null
  );
}

function normalizedPaymentMethod(orderData: Record<string, unknown>): string {
  return String(orderData.paymentMethod ?? orderData.type ?? "")
    .trim()
    .toLowerCase();
}

function hasBeenHandedOver(orderData: Record<string, unknown>): boolean {
  const status = String(orderData.status ?? "")
    .trim()
    .toLowerCase();
  return (
    orderData.collected === true ||
    orderData.collectedAt != null ||
    orderData.deliveredAt != null ||
    status === "collected" ||
    status === "delivered" ||
    status === "fulfilled"
  );
}

/** Manual receipt actions are never allowed to override Paystack truth. */
export function canRecordManualPayment(
  orderData: Record<string, unknown>,
): boolean {
  if (String(orderData.paymentRail ?? "").toLowerCase() === "paystack_v2") {
    return false;
  }
  const method = normalizedPaymentMethod(orderData);
  if (method === "transfer" || method === "eft") return true;
  return method === "cash" && hasBeenHandedOver(orderData);
}

/**
 * Goods may leave only after payment, except for cash-on-handover and an
 * explicitly approved Pay Later account.
 */
export function canAdvanceOrderFulfillment(
  orderData: Record<string, unknown>,
): boolean {
  if (isPaymentAlreadyRecorded(orderData)) return true;
  const method = normalizedPaymentMethod(orderData);
  if (method === "cash") return true;
  const paymentStatus = String(orderData.paymentStatus ?? "")
    .trim()
    .toLowerCase();
  return (
    (method === "bnpl" || method === "pay later" || method === "pay_later") &&
    paymentStatus === "approved"
  );
}

export function buildPaymentReceiptPatch(
  action: string,
  orderData: Record<string, unknown>,
  now: Date,
): Record<string, unknown> {
  if (action === "MARK_CASH_RECEIVED") {
    const existingMethod = String(
      orderData.paymentMethod ?? orderData.type ?? "",
    ).toLowerCase();
    const isTransfer =
      existingMethod === "transfer" || existingMethod === "eft";
    return {
      updatedAt: now,
      paymentMethod: isTransfer ? "Transfer" : "Cash",
      paymentStatus: "paid",
      status: "paid",
      ...(isTransfer ? { paidAt: now } : { cashReceivedAt: now }),
    };
  }

  if (action === "SETTLE_BNPL") {
    return {
      updatedAt: now,
      paymentStatus: "paid",
      status: "paid",
      paidAt: now,
    };
  }

  throw new Error(`Unsupported payment receipt action: ${action}`);
}
