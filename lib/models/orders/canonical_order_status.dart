/// Customer-facing lifecycle shared by merchant-stock and supplier-delivery
/// orders. Source-specific states remain on their original documents.
enum CanonicalOrderStatus {
  awaitingPayment('awaiting_payment', 'Awaiting payment'),
  paid('paid', 'Paid'),
  preparing('preparing', 'Preparing'),
  onTheWay('on_the_way', 'On the way'),
  delivered('delivered', 'Delivered'),
  cancelled('cancelled', 'Cancelled'),
  refunded('refunded', 'Refunded');

  const CanonicalOrderStatus(this.value, this.label);

  final String value;
  final String label;
}

CanonicalOrderStatus canonicalOrderStatus(
  Object? statusValue, {
  Object? paymentStatus,
}) {
  final status = statusValue?.toString().trim().toLowerCase() ?? '';
  final payment = paymentStatus?.toString().trim().toLowerCase() ?? '';
  if (status == 'refunded' || payment == 'refunded') {
    return CanonicalOrderStatus.refunded;
  }
  if (status == 'cancelled') return CanonicalOrderStatus.cancelled;
  if (status == 'delivered') return CanonicalOrderStatus.delivered;
  if (const {'shipped', 'out_for_delivery', 'on_the_way'}.contains(status)) {
    return CanonicalOrderStatus.onTheWay;
  }
  if (const {'submitted_for_fulfilment', 'preparing'}.contains(status)) {
    return CanonicalOrderStatus.preparing;
  }
  if (status == 'paid' || payment == 'paid') {
    return CanonicalOrderStatus.paid;
  }
  return CanonicalOrderStatus.awaitingPayment;
}
