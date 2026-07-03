import 'package:flutter/material.dart';

class ActionsBlock extends StatelessWidget {
  const ActionsBlock({
    super.key,
    required this.paymentMethod,
    required this.isPaid,
    required this.isBnpl,
    required this.isBnplApproved,
    required this.isCancelled,
    required this.isRejected,
    required this.onAcceptBnpl,
    required this.onRejectBnpl,
    required this.onMarkCash,
    required this.onSettleBnpl,
    required this.onMarkCollected,
    this.onMarkCollectedAndCash,
    required this.onCancelOrder,
    this.onAcceptOrder,
    this.onRejectOrder,
    this.onAssignDriver,
    this.onReassignDriver,
    this.onUnassignDriver,
    this.onMarkOutForDelivery,
    this.onMarkDelivered,
    required this.showMarkCollected,
    this.showMarkCash,
    this.showAcceptReject = false,
    this.showAssignDriver = false,
    this.showReassignDriver = false,
    this.showUnassignDriver = false,
    this.showMarkOutForDelivery = false,
    this.showMarkDelivered = false,
    this.isDelivery = false,
    this.busy = false,
    this.busyAction,
    this.showEmptyMessage = true,
  });

  final String paymentMethod;
  final bool isPaid;
  final bool isBnpl;
  final bool isBnplApproved;
  final bool isCancelled;
  final bool isRejected;

  final VoidCallback onAcceptBnpl;
  final VoidCallback onRejectBnpl;
  final VoidCallback onMarkCash;
  final VoidCallback onSettleBnpl;
  final VoidCallback onMarkCollected;

  /// Combined "Mark Collected & Cash Received" handler for pickup+cash
  /// orders where the two facts (goods handed over, cash in hand) happen
  /// at the same moment. When provided AND the order is in the
  /// pickup+cash+unpaid+uncollected state, the two separate buttons are
  /// replaced by one. All other flows (EFT, BNPL, delivery) are unchanged.
  final VoidCallback? onMarkCollectedAndCash;
  final VoidCallback onCancelOrder;
  final VoidCallback? onAcceptOrder;
  final VoidCallback? onRejectOrder;
  final VoidCallback? onAssignDriver;
  final VoidCallback? onReassignDriver;
  final VoidCallback? onUnassignDriver;
  final VoidCallback? onMarkOutForDelivery;
  final VoidCallback? onMarkDelivered;
  final bool showMarkCollected;
  final bool? showMarkCash;
  final bool showAcceptReject;
  final bool showAssignDriver;
  final bool showReassignDriver;
  final bool showUnassignDriver;
  final bool showMarkOutForDelivery;
  final bool showMarkDelivered;

  /// When true, fulfillment-related buttons render with delivery copy
  /// ("Mark Delivered" instead of "Mark Collected"). Drives the
  /// language only — the underlying server action depends on which
  /// `show*` flag is set.
  final bool isDelivery;
  final bool busy;
  final String? busyAction;

  final bool showEmptyMessage;

  @override
  Widget build(BuildContext context) {
    final payMethod = (paymentMethod).trim().toLowerCase();

    // ---- Build per-group action lists ------------------------------------
    final fulfillment = <_ActionBtn>[];
    final payment = <_ActionBtn>[];
    final destructive = <_ActionBtn>[];

    // Fulfillment ----------------------------------------------------------
    if (showAcceptReject) {
      fulfillment.add(_ActionBtn(
        label: 'Accept Order',
        icon: Icons.check_circle_outline,
        onTap: onAcceptOrder ?? () {},
        busy: busy && busyAction == 'ACCEPT_ORDER',
        kind: _BtnKind.primary,
      ));
    }
    if (showAssignDriver) {
      fulfillment.add(_ActionBtn(
        label: 'Assign Driver',
        icon: Icons.local_shipping_outlined,
        onTap: onAssignDriver ?? () {},
        busy: busy && busyAction == 'ASSIGN_DRIVER',
        kind: _BtnKind.primary,
      ));
    }
    if (showMarkOutForDelivery) {
      fulfillment.add(_ActionBtn(
        label: 'Mark Out for Delivery',
        icon: Icons.directions_car_outlined,
        onTap: onMarkOutForDelivery ?? () {},
        busy: busy && busyAction == 'MARK_OUT_FOR_DELIVERY',
        kind: _BtnKind.primary,
      ));
    }
    if (showReassignDriver) {
      fulfillment.add(_ActionBtn(
        label: 'Reassign Driver',
        icon: Icons.swap_horiz_outlined,
        onTap: onReassignDriver ?? () {},
        busy: busy && busyAction == 'ASSIGN_DRIVER',
        kind: _BtnKind.tonal,
      ));
    }
    if (showUnassignDriver) {
      fulfillment.add(_ActionBtn(
        label: 'Unassign Driver',
        icon: Icons.person_remove_outlined,
        onTap: onUnassignDriver ?? () {},
        busy: busy && busyAction == 'UNASSIGN_DRIVER',
        kind: _BtnKind.tonal,
      ));
    }
    if (showMarkDelivered) {
      fulfillment.add(_ActionBtn(
        label: 'Mark Delivered',
        icon: Icons.check_circle_outline,
        onTap: onMarkDelivered ?? () {},
        busy: busy && busyAction == 'MARK_DELIVERED',
        kind: _BtnKind.primary,
      ));
    }
    // Pickup + cash + still owed + goods not yet handed over → collapse
    // "Mark Collected" and "Mark Cash Received" into a single tap. They
    // *always* happen at the same physical moment for cash-on-collection,
    // so two taps was UX tax. The merchant retains separate actions for
    // EFT/transfer (cash button stays gated on hasHandedOver) and BNPL
    // (settle-later is a different button entirely).
    final canCombineCollectedAndCash = showMarkCollected &&
        !isDelivery &&
        !isPaid &&
        payMethod == 'cash' &&
        onMarkCollectedAndCash != null;
    if (canCombineCollectedAndCash) {
      fulfillment.add(_ActionBtn(
        label: 'Mark Collected & Cash Received',
        icon: Icons.payments_outlined,
        onTap: onMarkCollectedAndCash!,
        busy: busy &&
            (busyAction == 'MARK_COLLECTED' ||
                busyAction == 'MARK_CASH_RECEIVED'),
        kind: _BtnKind.primary,
      ));
    } else if (showMarkCollected) {
      fulfillment.add(_ActionBtn(
        label: isDelivery ? 'Mark Delivered' : 'Mark Collected',
        icon: isDelivery
            ? Icons.check_circle_outline
            : Icons.inventory_2_outlined,
        onTap: onMarkCollected,
        busy: busy && busyAction == 'MARK_COLLECTED',
        kind: _BtnKind.primary,
      ));
    }

    // Payment --------------------------------------------------------------
    if (!isPaid && isBnpl && !isBnplApproved) {
      payment.add(_ActionBtn(
        label: 'Approve Pay Later request',
        icon: Icons.account_balance_wallet_outlined,
        onTap: onAcceptBnpl,
        busy: busy && busyAction == 'ACCEPT_BNPL',
        kind: _BtnKind.primary,
      ));
      payment.add(_ActionBtn(
        label: 'Decline Pay Later request',
        icon: Icons.cancel_outlined,
        onTap: onRejectBnpl,
        busy: busy && busyAction == 'REJECT_BNPL',
        kind: _BtnKind.tonal,
      ));
    }
    if (!isPaid && isBnpl && isBnplApproved) {
      payment.add(_ActionBtn(
        label: 'Mark Pay Later as Paid',
        icon: Icons.done_all_outlined,
        onTap: onSettleBnpl,
        busy: busy && busyAction == 'SETTLE_BNPL',
        kind: _BtnKind.primary,
      ));
    }
    final canShowCash = (showMarkCash ?? true) &&
        !isPaid &&
        (payMethod == 'cash' ||
            payMethod == 'transfer' ||
            payMethod == 'eft') &&
        // If we already rendered the combined button, don't also show
        // the standalone "Mark Cash Received".
        !canCombineCollectedAndCash;
    if (canShowCash) {
      payment.add(_ActionBtn(
        label: payMethod == 'cash'
            ? 'Mark Cash Received'
            : 'Mark Payment Received',
        icon: Icons.payments_outlined,
        onTap: onMarkCash,
        busy: busy && busyAction == 'MARK_CASH_RECEIVED',
        kind: _BtnKind.primary,
      ));
    }

    // Destructive ----------------------------------------------------------
    if (showAcceptReject) {
      destructive.add(_ActionBtn(
        label: 'Reject Order',
        icon: Icons.block_outlined,
        onTap: onRejectOrder ?? () {},
        busy: busy && busyAction == 'REJECT_ORDER',
        kind: _BtnKind.destructive,
      ));
    }
    if (!isPaid &&
        !isCancelled &&
        !isRejected &&
        (isBnpl || payMethod == 'cash')) {
      destructive.add(_ActionBtn(
        label: 'Cancel Order',
        icon: Icons.cancel_outlined,
        onTap: onCancelOrder,
        busy: busy && busyAction == 'CANCEL_ORDER',
        kind: _BtnKind.destructive,
      ));
    }

    // ---- Render ----------------------------------------------------------
    final hasAny =
        fulfillment.isNotEmpty || payment.isNotEmpty || destructive.isNotEmpty;

    if (!hasAny) {
      if (!showEmptyMessage) return const SizedBox.shrink();
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No further actions available.'),
        ),
      );
    }

    final sections = <Widget>[];
    void addSection(String label, List<_ActionBtn> btns, {String? hint}) {
      if (btns.isEmpty) return;
      if (sections.isNotEmpty) {
        sections.add(const SizedBox(height: 12));
        sections.add(const Divider(height: 1));
        sections.add(const SizedBox(height: 12));
      }
      sections.add(_SectionLabel(label));
      if (hint != null && hint.isNotEmpty) {
        sections.add(const SizedBox(height: 4));
        sections.add(_SectionHint(hint));
      }
      sections.add(const SizedBox(height: 8));
      for (var i = 0; i < btns.length; i++) {
        if (i > 0) sections.add(const SizedBox(height: 8));
        sections.add(btns[i]);
      }
    }

    // ---- Per-section hints (derived from current order state) -----------
    String? fulfillmentHint;
    if (showAcceptReject) {
      fulfillmentHint =
          'A new order is waiting for your decision. Accept it to continue, or reject to decline the request.';
    } else if (showAssignDriver) {
      fulfillmentHint =
          'Pick a driver who will collect this order and deliver it to the customer.';
    } else if (showMarkOutForDelivery) {
      fulfillmentHint =
          'Driver has the order? Tap below to notify the customer it’s on the way.';
    } else if (showMarkDelivered) {
      fulfillmentHint = showUnassignDriver
          ? 'Once the customer has received their order, mark it as delivered. '
              'If the driver can no longer complete the delivery, you can recall them below.'
          : 'Once the customer has received their order, mark it as delivered to close it out.';
    } else if (showMarkCollected) {
      fulfillmentHint =
          'Mark this order as collected once the customer has picked it up in store.';
    }

    String? paymentHint;
    if (!isPaid && isBnpl && !isBnplApproved) {
      paymentHint =
          'The customer asked to pay later. Approve the transaction, or decline to ask them to pay now.';
    } else if (!isPaid && isBnpl && isBnplApproved) {
      paymentHint =
          'Pay Later was approved. When the customer settles up, mark it paid here.';
    } else if (payment.isNotEmpty) {
      paymentHint =
          'The order has been handed over. Confirm payment once you’ve received the cash or transfer from the customer.';
    }

    const destructiveHint =
        'Use these only if the order can’t be fulfilled — the customer will be notified.';

    addSection('Next step', fulfillment, hint: fulfillmentHint);
    addSection('Payment', payment, hint: paymentHint);
    addSection('Danger zone', destructive, hint: destructiveHint);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: sections,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

enum _BtnKind { primary, tonal, destructive }

class _SectionHint extends StatelessWidget {
  const _SectionHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
    this.kind = _BtnKind.primary,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;
  final _BtnKind kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Color spinnerColor;
    switch (kind) {
      case _BtnKind.primary:
        spinnerColor = scheme.onPrimary;
        break;
      case _BtnKind.tonal:
        spinnerColor = scheme.onSecondaryContainer;
        break;
      case _BtnKind.destructive:
        spinnerColor = scheme.error;
        break;
    }

    final progress = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(spinnerColor),
            ),
          )
        : Icon(icon);

    final labelWidget = Text(busy ? 'Working…' : label);
    final onPressed = busy ? null : onTap;

    Widget child;
    switch (kind) {
      case _BtnKind.primary:
        child = FilledButton.icon(
          onPressed: onPressed,
          icon: progress,
          label: labelWidget,
        );
        break;
      case _BtnKind.tonal:
        child = FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: progress,
          label: labelWidget,
        );
        break;
      case _BtnKind.destructive:
        child = OutlinedButton.icon(
          onPressed: onPressed,
          icon: progress,
          label: labelWidget,
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
          ),
        );
        break;
    }

    return SizedBox(width: double.infinity, child: child);
  }
}
