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

  // Deterministic balance values for the layout regression harness. Keeping
  // these private prevents production call sites from bypassing the live
  // WalletBalanceProvider.
  final double? _testBalance;
  final bool _testLoading;
  final bool _testSharedCampaignCredits;
  final String _testStoreName;

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
  })  : _testBalance = null,
        _testLoading = false,
        _testSharedCampaignCredits = false,
        _testStoreName = '',
        super(key: key);

  @visibleForTesting
  const WalletAffordabilityFooter.test({
    Key? key,
    required this.cost,
    required this.confirmLabel,
    this.confirmIcon,
    this.onConfirm,
    this.busy = false,
    this.onBack,
    this.leadingAction,
    this.onTopUp,
    required double balance,
    bool loading = false,
    bool sharedCampaignCredits = false,
    String activeStoreName = '',
  })  : _testBalance = balance,
        _testLoading = loading,
        _testSharedCampaignCredits = sharedCampaignCredits,
        _testStoreName = activeStoreName,
        super(key: key);

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
    final wallet =
        _testBalance == null ? context.watch<WalletBalanceProvider>() : null;
    final balance = _testBalance ?? wallet!.virtualBalance;
    final loading = _testBalance == null ? wallet!.isLoading : _testLoading;
    final sharedCampaignCredits = _testBalance == null
        ? wallet!.sharedCampaignCredits
        : _testSharedCampaignCredits;
    final activeStoreName =
        _testBalance == null ? wallet!.activeStoreName : _testStoreName;
    final canAfford = balance >= cost;

    final balanceLabel =
        sharedCampaignCredits ? 'Shared campaign credits' : 'Campaign credits';
    final statusText = loading
        ? 'Checking campaign credits…'
        : '$balanceLabel ${CurrencyUtil.format(balance)}'
            '${canAfford ? ' · ${CurrencyUtil.format(balance - cost)} after' : ' · ${CurrencyUtil.format(cost - balance)} short'}'
            '${sharedCampaignCredits ? ' • Sending as $activeStoreName' : ''}';

    final statusColor = loading
        ? Colors.black54
        : (canAfford ? Colors.black87 : Colors.orange.shade800);
    final ButtonStyle compactButtonStyle = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
    final Widget primaryAction;
    if (loading) {
      primaryAction = ElevatedButton(
        style: compactButtonStyle,
        onPressed: null,
        child: const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (canAfford) {
      primaryAction = ElevatedButton.icon(
        style: compactButtonStyle,
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
            : Text(confirmLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
        onPressed: (busy || onConfirm == null) ? null : () => onConfirm!(),
      );
    } else {
      primaryAction = ElevatedButton.icon(
        icon: const Icon(Icons.account_balance_wallet),
        label: const Text(
          'Top Up Wallet',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: compactButtonStyle.copyWith(
          backgroundColor: const WidgetStatePropertyAll(Colors.orange),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
        ),
        onPressed: () => (onTopUp ?? () => _defaultTopUp(context))(),
      );
    }

    return Column(
      // This footer is also used inside Scaffold.bottomNavigationBar. Keep it
      // content-sized so it cannot expand over the promotion body.
      mainAxisSize: MainAxisSize.min,
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
          children: [
            if (onBack != null) ...[
              SizedBox(
                width: 82,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: onBack,
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (leadingAction != null) ...[
              Expanded(child: leadingAction!),
              const SizedBox(width: 10),
            ],
            Expanded(flex: 2, child: primaryAction),
          ],
        ),
      ],
    );
  }
}
