import 'package:flutter/material.dart';
import 'package:pasella/models/sales/order_model.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';

/// PAS-UX-14: high-level filter groupings shown in the redesigned
/// Customer Orders chip row.
///
/// The original UI exposed all 13 raw `OrderStatus` values as chips,
/// which scrolled off-screen and pushed merchants past the few they
/// actually needed. The redesign promotes the 4 most actionable cohorts
/// and tucks everything else into a "More" bottom sheet (see
/// `order_filter_chips.dart`).
///
/// Mapping rationale:
///   * [all]      → no-op, default.
///   * [pending]  → single status; this is what merchants accept/reject
///                  from. Highest-attention bucket.
///   * [bnpl]     → `bnplPending` + `bnplOutstanding` + `bnplRejected`.
///                  Merchants think about "BNPL" as one funnel, not
///                  three states.
///   * [delivery] → `outForDelivery` + `delivered`. Same lens — "in
///                  flight or done".
///
/// Selecting a specific raw status (via the More sheet) is modelled by
/// [OrdersFilter.specific], which carries an `OrderStatus` payload and
/// bypasses the grouping entirely.
enum OrderFilterGroup { all, pending, bnpl, delivery }

/// Effective filter applied to the orders list.
///
/// We model this as a sealed-ish union (group OR specific status) so
/// the chip row never has to ask "is this group selected, or did the
/// user pick something specific that happens to fall in this group?".
class OrdersFilter {
  final OrderFilterGroup? group;
  final OrderStatus? specific;

  const OrdersFilter.group(this.group) : specific = null;
  const OrdersFilter.specific(OrderStatus status)
      : group = null,
        specific = status;

  static const all = OrdersFilter.group(OrderFilterGroup.all);

  bool get isAll => group == OrderFilterGroup.all;

  /// True when [status] would match the currently selected filter, for
  /// the purpose of counting how many orders belong to each chip.
  bool matchesStatus(OrderStatus status, {required bool isCollected}) {
    if (group != null) {
      switch (group!) {
        case OrderFilterGroup.all:
          return true;
        case OrderFilterGroup.pending:
          return status == OrderStatus.pending;
        case OrderFilterGroup.bnpl:
          return status == OrderStatus.bnplPending ||
              status == OrderStatus.bnplOutstanding ||
              status == OrderStatus.bnplRejected;
        case OrderFilterGroup.delivery:
          return status == OrderStatus.outForDelivery ||
              status == OrderStatus.delivered;
      }
    }
    // Specific status — same legacy behaviour applies for the collection
    // pseudo-statuses which are derived from the boolean flag, not the
    // computed status.
    if (specific == OrderStatus.collected) return isCollected;
    if (specific == OrderStatus.uncollected) return !isCollected;
    return specific == status;
  }
}

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
  required OrdersFilter filter,
  required String query,
  required DateTimeRange? range,
}) {
  bool matchesFilter(OrderModel o) {
    final status = computeStatus(o);
    return filter.matchesStatus(status, isCollected: o.collected == true);
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
      .where((o) => matchesFilter(o) && matchesQuery(o) && matchesDate(o))
      .toList();
}
