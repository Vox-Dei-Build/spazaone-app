import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/shared/billing/wallet_balance_provider.dart';
import 'package:provider/provider.dart';
import 'package:pasella/utils/currency_util.dart';

/// Inline footer that shows the user's live wallet balance vs. an action's
/// cost, and renders either a confirm button (if affordable) or a "Top Up
/// Wallet" CTA (if not).
///
/// Replaces the duplicated StreamBuilder pattern previously in the run-/view-
/// promotion screens (`run_promotion_page.dart:208-284`,
/// `view_promotion.dart:128-183`).
///
/// Reads balance from the global [WalletBalanceProvider].
class WalletAffordabilityFooter extends StatelessWidget {
  /// The cost of the action in ZAR.
  final double cost;

  /// Label for the affordable confirm button (e.g. "Send Promotion").
  final String confirmLabel;

  /// Optional icon for the confirm button.
  final IconData? confirmIcon;

  /// Called when the user taps the affordable confirm button.
  final Future<void> Function()? onConfirm;

  /// True while the parent is performing the action (disables the button and
  /// shows a spinner).
  final bool busy;

  /// Optional secondary "Back" button shown to the left.
  final VoidCallback? onBack;

  /// Optional left-side action that is always shown (e.g. "Save"). When
  /// provided, the affordability state controls only the right-hand button.
  final Widget? leadingAction;

  /// What to do when the user taps "Top Up Wallet". Defaults to popping to
  /// root + [AppModel.goToBilling].
  final VoidCallback? onTopUp;

  const WalletAffordabilityFooter({
    Key? key,
    required this.cost,
    required this.confirmLabel,
    this.confirmIcon,
    this.onConfirm,
    this.busy = false,
    this.onBack,
    this.leadingAction,
    this.onTopUp,
  }) : super(key: key);

  void _defaultTopUp(BuildContext context) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    // PAS-UX-WTC: open WalletPage on the Top-Up tab so the CTA name
    // and the destination match.
    Provider.of<AppModel>(
      context,
      listen: false,
    ).goToBilling(context, initialTab: WalletInitialTab.topUp);
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletBalanceProvider>();
    final balance = wallet.virtualBalance;
    final loading = wallet.isLoading;
    final canAfford = balance >= cost;

    final balanceLabel = wallet.sharedCampaignCredits
        ? 'Shared campaign credits'
        : 'Campaign credits';
    final statusText = loading
        ? 'Checking campaign credits…'
        : '$balanceLabel: ${CurrencyUtil.format(balance)} • '
            'this costs ${CurrencyUtil.format(cost)}'
            '${canAfford ? ' • ${CurrencyUtil.format(balance - cost)} after' : ''}'
            '${wallet.sharedCampaignCredits ? ' • Sending as ${wallet.activeStoreName}' : ''}';

    final statusColor = loading
        ? Colors.black54
        : (canAfford ? Colors.black87 : Colors.orange.shade800);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          statusText,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 1.6,
            color: statusColor,
            fontWeight: canAfford ? FontWeight.normal : FontWeight.w600,
          ),
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 1),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (onBack != null)
              OutlinedButton(onPressed: onBack, child: const Text('Back'))
            else
              const SizedBox.shrink(),
            if (leadingAction != null) leadingAction!,
            if (loading)
              const ElevatedButton(
                onPressed: null,
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (canAfford)
              ElevatedButton.icon(
                icon: Icon(confirmIcon ?? Icons.check),
                label: busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(confirmLabel),
                onPressed:
                    (busy || onConfirm == null) ? null : () => onConfirm!(),
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.account_balance_wallet),
                label: const Text('Top Up Wallet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => (onTopUp ?? () => _defaultTopUp(context))(),
              ),
          ],
        ),
      ],
    );
  }
}
