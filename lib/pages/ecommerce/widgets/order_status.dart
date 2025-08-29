import 'package:flutter/material.dart';

class PillMeta {
  final String text;
  final Color color;
  const PillMeta(this.text, this.color);
}

enum OrderStatus {
  all,
  pending,
  paid,
  cancelled,
  /* fulfilled,
  cancelled,
  refunded, */
  uncollected,
  collected,
  bnplPending,
  bnplOutstanding,
  bnplRejected,
}

extension OrderStatusLabel on OrderStatus {
  String get label => switch (this) {
        OrderStatus.all => 'All',
        OrderStatus.pending => 'Pending',
        OrderStatus.paid => 'Paid',
        OrderStatus.cancelled => 'Cancelled',
        /* OrderStatus.fulfilled => 'Fulfilled',
        OrderStatus.cancelled => 'Cancelled',
        OrderStatus.refunded => 'Refunded', */
        OrderStatus.uncollected => 'Uncollected',
        OrderStatus.collected => 'Collected',
        OrderStatus.bnplPending => 'BNPL Pending',
        OrderStatus.bnplOutstanding => 'BNPL Outstanding',
        OrderStatus.bnplRejected => 'BNPL Rejected',
      };
}

extension OrderStatusX on OrderStatus {
  Color color(BuildContext c) => switch (this) {
        OrderStatus.pending => Colors.amber,
        OrderStatus.paid => Colors.green,
        /* OrderStatus.fulfilled => Colors.blue,
        OrderStatus.cancelled => Colors.red,
        OrderStatus.refunded => Colors.purple, */
        OrderStatus.cancelled => Colors.red,
        OrderStatus.uncollected => Colors.orange,
        OrderStatus.collected => Colors.teal,
        OrderStatus.bnplRejected => Colors.deepOrange,
        OrderStatus.bnplPending => Colors.amber,
        OrderStatus.bnplOutstanding => Colors.brown,
        OrderStatus.all => Theme.of(c).colorScheme.outline,
      };

  // String parser (kept for convenience)
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

    if (x.contains('paid') || x.contains('complete') || ps == 'paid') {
      return OrderStatus.paid;
    }
    if (x.contains('uncollected') || ps == 'uncollected') {
      return OrderStatus.uncollected;
    }
    if (x.contains('collected') || ps == 'collected') {
      return OrderStatus.collected;
    }
    /* if (x.contains('refund') || ps == 'refunded') {
      return OrderStatus.refunded;
    }
    if (x.contains('cancel') || ps == 'cancelled') {
      return OrderStatus.cancelled;
    }
    if (x.contains('fulfill') || ps == 'fulfilled') {
      return OrderStatus.fulfilled;
    } */
    if (x.contains('cancel') || ps == 'cancelled') {
      return OrderStatus.cancelled;
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

  // 2) Payment/fulfillment/cancellation/refund
  if (isPaid || s == 'paid' || s == 'fulfilled' || ps == 'paid') {
    return OrderStatus.paid;
  }
  /* if (s.contains('refund') || ps == 'refunded') return OrderStatus.refunded;
  if (s.contains('cancel') || ps == 'cancelled') return OrderStatus.cancelled;
  if (s.contains('fulfill') || ps == 'fulfilled') return OrderStatus.fulfilled; */
  if (s.contains('cancel') || ps == 'cancelled') return OrderStatus.cancelled;

  // 3) Only now consider collection state
  if (isCollected || s.contains('collected')) return OrderStatus.collected;
  if (s.contains('uncollected') || ps == 'uncollected') {
    return OrderStatus.uncollected;
  }

  // 4) Pending / default
  if (s.contains('pending') || s.isEmpty || ps == 'pending') {
    return OrderStatus.pending;
  }

  // 5) Fallback to parser
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
      return const StatusMeta('BNPL Rejected', Colors.deepOrange);
    }
    if (ps == 'approved' || ps == 'outstanding') {
      return const StatusMeta('BNPL Outstanding', Colors.brown);
    }
    if (ps == 'paid' || ps == 'settled') {
      return const StatusMeta('Paid', Colors.green);
    }
    return const StatusMeta('BNPL Pending', Colors.amber);
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
}) {
  if (isCollected) {
    return const PillMeta('Collected', Colors.teal);
  } else {
    return const PillMeta('Uncollected', Colors.orange);
  }
}
