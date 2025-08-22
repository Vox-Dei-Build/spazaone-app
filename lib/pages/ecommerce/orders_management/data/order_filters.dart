import 'package:flutter/material.dart';
import 'package:pasella/models/sales/order_model.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';

/// Compute a unified OrderStatus for an order (same logic as detail page).
OrderStatus computeStatus(OrderModel o) {
  final raw = (o.status).toString();
  final sLow = raw.toLowerCase();
  final pm = (o.paymentMethod ?? '').toString();
  final typ = (o.type ?? '').toString();
  final ps = (o.paymentStatus ?? '').toString();

  // Use the same “method for logic” pattern as detail page
  final methodForLogic = ((pm.isNotEmpty ? pm : typ)).trim().toLowerCase();

  final isBnpl = typ.toUpperCase() == 'BNPL' ||
      methodForLogic == 'bnpl' ||
      sLow.contains('bnpl');

  final isBnplApproved = isBnpl &&
      (ps.toLowerCase() == 'approved' || sLow.contains('bnpl_outstanding'));

  final isBnplRejected = isBnpl &&
      (ps.toLowerCase() == 'rejected' || sLow.contains('bnpl_rejected'));

  final isPaid =
      ps.toLowerCase() == 'paid' || sLow == 'paid' || sLow == 'fulfilled';

  // IMPORTANT: use boolean flag for collected (not string contains)
  final isCollected = o.collected == true;

  return resolveOrderStatus(
    status: raw,
    isPaid: isPaid,
    isCollected: isCollected,
    isBnpl: isBnpl,
    isBnplApproved: isBnplApproved,
    isBnplRejected: isBnplRejected,
    paymentMethod: pm,
    type: typ,
    paymentStatus: ps,
  );
}

List<OrderModel> applyClientFilters(
  List<OrderModel> source, {
  required OrderStatus status,
  required String query,
  required DateTimeRange? range,
}) {
  bool matchesStatus(OrderModel o) {
    if (status == OrderStatus.all) return true;

    // Collection tabs filter directly off the flag
    if (status == OrderStatus.collected) return o.collected == true;
    if (status == OrderStatus.uncollected) return o.collected != true;

    final st = computeStatus(o);
    return st == status;
  }

  bool matchesQuery(OrderModel o) {
    if (query.isEmpty) return true;
    return o.id.toLowerCase().contains(query.toLowerCase());
  }

  bool matchesDate(OrderModel o) {
    if (range == null || o.createdAt == null) return true;
    final d = o.createdAt!;
    // Inclusive range check
    return !d.isBefore(range.start) && !d.isAfter(range.end);
  }

  return source
      .where((o) => matchesStatus(o) && matchesQuery(o) && matchesDate(o))
      .toList();
}
