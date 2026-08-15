bool isCashOrderMethod(String paymentMethod) =>
    paymentMethod.trim().toLowerCase() == 'cash';

bool isManualTransferOrderMethod(String paymentMethod) {
  final method = paymentMethod.trim().toLowerCase();
  return method == 'transfer' || method == 'eft';
}

/// Whether the merchant may hand a pickup order to the customer.
///
/// Cash is confirmed at the same physical moment through the combined action.
/// Approved Pay Later deliberately permits handover while debt remains. Manual
/// bank transfers and online payments must be confirmed before handover.
bool canMarkPickupOrderCollected({
  required String paymentMethod,
  required bool isPaid,
  required bool isBnpl,
  required bool isBnplApproved,
  required bool isCollected,
  required bool isDelivery,
  required bool isPendingMerchantReview,
  required bool isTerminal,
}) {
  if (isCollected || isDelivery || isPendingMerchantReview || isTerminal) {
    return false;
  }
  if (isPaid) return true;
  if (isCashOrderMethod(paymentMethod)) return true;
  return isBnpl && isBnplApproved;
}

/// Whether a manual receipt action should be available.
///
/// EFT/transfer is confirmed before the goods are handed over. Cash remains
/// gated on handover because the pickup flow records collection and cash in a
/// single action, while cash delivery is settled after delivery.
bool canMarkManualOrderPaymentReceived({
  required String paymentMethod,
  required bool isPaid,
  required bool isTerminal,
  required bool isPendingMerchantReview,
  required bool hasHandedOver,
}) {
  if (isPaid || isTerminal || isPendingMerchantReview) return false;
  if (isManualTransferOrderMethod(paymentMethod)) return true;
  return isCashOrderMethod(paymentMethod) && hasHandedOver;
}

/// Online/EFT fulfilment waits for payment. Cash-on-handover and an approved
/// Pay Later account may continue while their payment status is still open.
bool canAdvanceOrderFulfillment({
  required String paymentMethod,
  required bool isPaid,
  required bool isBnpl,
  required bool isBnplApproved,
}) {
  if (isPaid) return true;
  if (isCashOrderMethod(paymentMethod)) return true;
  return isBnpl && isBnplApproved;
}
