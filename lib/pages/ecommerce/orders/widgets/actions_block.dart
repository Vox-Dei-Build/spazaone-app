import 'package:flutter/material.dart';

class ActionsBlock extends StatelessWidget {
  const ActionsBlock({
    super.key,
    required this.paymentMethod,
    required this.isPaid,
    required this.isBnpl,
    required this.isBnplApproved,
    required this.onAcceptBnpl,
    required this.onRejectBnpl,
    required this.onMarkCash,
    required this.onSettleBnpl,
    required this.onMarkCollected,
    required this.showMarkCollected,
    this.showMarkCash,
    this.busy = false,
    this.busyAction,
    this.showEmptyMessage = true,
  });

  final String paymentMethod;
  final bool isPaid;
  final bool isBnpl;
  final bool isBnplApproved;

  final VoidCallback onAcceptBnpl;
  final VoidCallback onRejectBnpl;
  final VoidCallback onMarkCash;
  final VoidCallback onSettleBnpl;
  final VoidCallback onMarkCollected;
  final bool showMarkCollected;
  final bool? showMarkCash;
  final bool busy;
  final String? busyAction;

  final bool showEmptyMessage; // NEW

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];
    final payMethod = (paymentMethod).trim().toLowerCase();

    void addGap() {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(height: 8));
    }

    if (!isPaid && isBnpl && !isBnplApproved) {
      buttons.add(_ActionBtn(
        label: 'Accept BNPL',
        icon: Icons.account_balance_wallet_outlined,
        onTap: onAcceptBnpl,
        busy: busy && busyAction == 'ACCEPT_BNPL',
      ));
      addGap();
      buttons.add(_ActionBtn(
        label: 'Reject BNPL',
        icon: Icons.cancel_outlined,
        onTap: onRejectBnpl,
        busy: busy && busyAction == 'REJECT_BNPL',
      ));
    }

    if (!isPaid && isBnpl && isBnplApproved) {
      addGap();
      buttons.add(_ActionBtn(
        label: 'Mark as Paid (Settle BNPL)',
        icon: Icons.done_all_outlined,
        onTap: onSettleBnpl,
        busy: busy && busyAction == 'SETTLE_BNPL',
      ));
    }

    final canShowCash =
        (showMarkCash ?? true) && !isPaid && payMethod == 'cash';
    if (canShowCash) {
      addGap();
      buttons.add(_ActionBtn(
        label: 'Mark Cash Received',
        icon: Icons.payments_outlined,
        onTap: onMarkCash,
        busy: busy && busyAction == 'MARK_CASH_RECEIVED',
      ));
    }

    if (showMarkCollected) {
      addGap();
      buttons.add(_ActionBtn(
        label: 'Mark Collected',
        icon: Icons.inventory_2_outlined,
        onTap: onMarkCollected,
        busy: busy && busyAction == 'MARK_COLLECTED',
      ));
    }

    if (buttons.isEmpty) {
      if (!showEmptyMessage) return const SizedBox.shrink(); // NEW
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No further actions available.'),
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(children: buttons),
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
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: busy ? null : onTap,
        icon: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              )
            : Icon(icon),
        label: Text(busy ? 'Working…' : label),
      ),
    );
  }
}
