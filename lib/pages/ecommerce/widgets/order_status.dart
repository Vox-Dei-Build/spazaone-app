import 'package:flutter/material.dart';

class PillMeta {
  final String text;
  final Color color;
  const PillMeta(this.text, this.color);
}

enum OrderStatus {
  all,
  pending,
  accepted,
  paid,
  cancelled,
  refunded,
  rejected,
  uncollected,
  collected,
  outForDelivery,
  delivered,
  bnplPending,
  bnplOutstanding,
  bnplRejected,
}

extension OrderStatusLabel on OrderStatus {
  String get label => switch (this) {
        OrderStatus.all => 'All',
        OrderStatus.pending => 'Pending',
        OrderStatus.accepted => 'Accepted',
        OrderStatus.paid => 'Paid',
        OrderStatus.cancelled => 'Cancelled',
        OrderStatus.refunded => 'Refunded',
        OrderStatus.rejected => 'Rejected',
        OrderStatus.uncollected => 'Uncollected',
        OrderStatus.collected => 'Collected',
        OrderStatus.outForDelivery => 'Out for Delivery',
        OrderStatus.delivered => 'Delivered',
        OrderStatus.bnplPending => 'Pay Later Pending',
        OrderStatus.bnplOutstanding => 'Pay Later Outstanding',
        OrderStatus.bnplRejected => 'Pay Later Rejected',
      };
}

extension OrderStatusX on OrderStatus {
  Color color(BuildContext c) => switch (this) {
        OrderStatus.pending => Colors.amber,
        OrderStatus.accepted => Colors.indigo,
        OrderStatus.paid => Colors.green,
        OrderStatus.cancelled => Colors.red,
        OrderStatus.refunded => Colors.purple,
        OrderStatus.rejected => Colors.red,
        OrderStatus.uncollected => Colors.orange,
        OrderStatus.collected => Colors.teal,
        OrderStatus.outForDelivery => Colors.blue,
        OrderStatus.delivered => Colors.teal,
        OrderStatus.bnplRejected => Colors.deepOrange,
        OrderStatus.bnplPending => Colors.amber,
        OrderStatus.bnplOutstanding => Colors.brown,
        OrderStatus.all => Theme.of(c).colorScheme.outline,
      };

  // String parser (kept for convenience)
  static OrderStatus fromString(
    String v, {
    String? paymentMethod,
    String? type,
    String? paymentStatus,
  }) {
    final x = (v).toLowerCase();
    final pm = (paymentMethod ?? '').toLowerCase();
    final t = (type ?? '').toLowerCase();
    final ps = (paymentStatus ?? '').toLowerCase();

    final isBnpl = pm == 'bnpl' || t == 'bnpl' || x.contains('bnpl');
    if (isBnpl) {
      if (x.contains('outstanding') ||
          x.contains('approved') ||
          ps == 'approved') {
        return OrderStatus.bnplOutstanding;
      } else if (x.contains('rejected') || ps == 'rejected') {
        return OrderStatus.bnplRejected;
      } else if (x.contains('paid') || ps == 'paid') {
        return OrderStatus.paid;
      }
      return OrderStatus.bnplPending;
    }

    if (x.contains('refund') || ps == 'refunded') {
      return OrderStatus.refunded;
    }
    if (x.contains('cancel') || ps == 'cancelled') {
      return OrderStatus.cancelled;
    }
    if (x == 'delivered') return OrderStatus.delivered;
    if (x == 'shipped' || x == 'out_for_delivery') {
      return OrderStatus.outForDelivery;
    }
    if (x == 'submitted_for_fulfilment') return OrderStatus.accepted;
    if (x.contains('uncollected') || ps == 'uncollected') {
      return OrderStatus.uncollected;
    }
    if (x.contains('collected') || ps == 'collected') {
      return OrderStatus.collected;
    }
    if (x.contains('paid') || x.contains('complete') || ps == 'paid') {
      return OrderStatus.paid;
    }
    if (x.contains('reject') || ps == 'rejected') {
      return OrderStatus.rejected;
    }
    if (x.contains('pending') || x.isEmpty || ps == 'pending') {
      return OrderStatus.pending;
    }

    return OrderStatus.pending;
  }
}

// Optional: single resolver if you want to consolidate business rules
OrderStatus resolveOrderStatus({
  required String status,
  bool isPaid = false,
  bool isCollected = false,
  bool isBnpl = false,
  bool isBnplApproved = false,
  bool isBnplRejected = false,
  String? paymentMethod,
  String? type,
  String? paymentStatus,
}) {
  final s = status.toLowerCase();
  final ps = (paymentStatus ?? '').toLowerCase();

  // 1) BNPL first
  if (isBnpl ||
      (paymentMethod?.toLowerCase() == 'bnpl') ||
      (type?.toLowerCase() == 'bnpl') ||
      s.contains('bnpl')) {
    if (isBnplRejected || ps == 'rejected' || s.contains('rejected')) {
      return OrderStatus.bnplRejected;
    }
    if (isBnplApproved ||
        ps == 'approved' ||
        s.contains('approved') ||
        s.contains('outstanding')) {
      return OrderStatus.bnplOutstanding;
    }
    if (ps == 'paid' || s.contains('paid')) {
      return OrderStatus.paid;
    }
    return OrderStatus.bnplPending;
  }

  // 2) Delivery / collection terminal states win over generic "paid" so
  //    the merchant always sees the freshest fulfillment truth on the
  //    order header. A delivered/collected order is implicitly paid in
  //    this V1 — payment status is surfaced separately on its own pill.
  if (s == 'delivered' || s.contains('delivered')) {
    return OrderStatus.delivered;
  }
  if (s == 'out_for_delivery' || s.contains('out_for_delivery')) {
    return OrderStatus.outForDelivery;
  }
  if (s == 'shipped') return OrderStatus.outForDelivery;
  if (isCollected || s.contains('collected')) return OrderStatus.collected;

  if (s == 'submitted_for_fulfilment') return OrderStatus.accepted;

  // 3) Cancellation/refund must win over an older paid payment snapshot.
  if (s.contains('refund') || ps == 'refunded') return OrderStatus.refunded;
  if (s.contains('cancel') || ps == 'cancelled') return OrderStatus.cancelled;

  // 4) Payment/fulfillment
  if (isPaid || s == 'paid' || s == 'fulfilled' || ps == 'paid') {
    return OrderStatus.paid;
  }
  if (s.contains('reject') || ps == 'rejected') return OrderStatus.rejected;

  // 5) Accepted (merchant approved but not yet dispatched/paid)
  if (s == 'accepted') {
    return OrderStatus.accepted;
  }

  if (s.contains('uncollected') || ps == 'uncollected') {
    return OrderStatus.uncollected;
  }

  // 6) Pending / default
  if (s.contains('pending') || s.isEmpty || ps == 'pending') {
    return OrderStatus.pending;
  }

  // 7) Fallback to parser
  return OrderStatusX.fromString(status,
      paymentMethod: paymentMethod, type: type, paymentStatus: paymentStatus);
}

String statusLabel(OrderStatus st) => st.label;
Color statusColor(BuildContext c, OrderStatus st) => st.color(c);

@immutable
class StatusMeta {
  final String label;
  final Color color;
  const StatusMeta(this.label, this.color);
}

/// Build a display label/color for *payment* status (BNPL-aware).
StatusMeta buildPaymentStatusMeta(
  BuildContext c, {
  required String? paymentStatus,
  String? paymentMethod,
  String? type,
}) {
  final ps = (paymentStatus ?? '').toLowerCase().trim();
  final pm = (paymentMethod ?? '').toLowerCase();
  final t = (type ?? '').toLowerCase();
  final isBnpl = pm == 'bnpl' || t == 'bnpl';

  // BNPL rules
  if (isBnpl) {
    if (ps == 'rejected') {
      return const StatusMeta('Pay Later Rejected', Colors.deepOrange);
    }
    if (ps == 'approved' || ps == 'outstanding') {
      return const StatusMeta('Pay Later Outstanding', Colors.brown);
    }
    if (ps == 'paid' || ps == 'settled') {
      return const StatusMeta('Paid', Colors.green);
    }
    return const StatusMeta('Pay Later Pending', Colors.amber);
  }

  // Non-BNPL generic payment statuses
  if (ps == 'paid' || ps == 'settled') {
    return const StatusMeta('Paid', Colors.green);
  }
  if (ps == 'refunded') return const StatusMeta('Refunded', Colors.purple);
  if (ps == 'rejected' || ps == 'failed') {
    return const StatusMeta('Rejected', Colors.red);
  }
  if (ps == 'cancelled' || ps == 'canceled') {
    return const StatusMeta('Cancelled', Colors.red);
  }
  if (ps.isEmpty || ps == 'pending') {
    return const StatusMeta('Pending', Colors.amber);
  }

  // Fallback: show raw value with neutral outline color
  return StatusMeta(
      paymentStatus ?? 'Unknown', Theme.of(c).colorScheme.outline);
}

PillMeta? buildCollectionPill({
  required bool isCollected,
  bool isDelivery = false,
  bool isOutForDelivery = false,
  bool hasDriver = false,
  bool isRejected = false,
  bool isCancelled = false,
}) {
  // Terminal non-fulfillment states short-circuit so a rejected or
  // cancelled order never reads as "awaiting" something that will
  // never happen.
  if (isRejected) return const PillMeta('Rejected', Colors.red);
  if (isCancelled) return const PillMeta('Cancelled', Colors.red);

  // Delivery orders speak the language of delivery, not collection.
  // The "awaiting" label depends on whether a driver has been
  // attached yet: without a driver we're waiting to *find* one;
  // with a driver attached we're waiting to *dispatch* — and the
  // merchant's next action is "Mark Out for Delivery", so we call
  // it "Driver assigned" rather than the previous "Awaiting
  // Dispatch" which incorrectly implied no further action was
  // available.
  if (isDelivery) {
    if (isCollected) return const PillMeta('Delivered', Colors.teal);
    if (isOutForDelivery) {
      return const PillMeta('Out for Delivery', Colors.blue);
    }
    if (hasDriver) return const PillMeta('Driver assigned', Colors.blue);
    return const PillMeta('Awaiting driver', Colors.orange);
  }
  if (isCollected) {
    return const PillMeta('Collected', Colors.teal);
  } else {
    return const PillMeta('Uncollected', Colors.orange);
  }
}
