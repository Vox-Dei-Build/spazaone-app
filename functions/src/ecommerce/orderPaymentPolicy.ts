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

export function buildPaymentReceiptPatch(
  action: string,
  orderData: Record<string, unknown>,
  now: Date,
): Record<string, unknown> {
  if (action === "MARK_CASH_RECEIVED") {
    const existingMethod = String(
      orderData.paymentMethod ?? orderData.type ?? "",
    ).toLowerCase();
    return {
      updatedAt: now,
      paymentMethod:
        existingMethod === "transfer" || existingMethod === "eft"
          ? "Transfer"
          : "Cash",
      paymentStatus: "paid",
      status: "paid",
      cashReceivedAt: now,
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
