import 'package:flutter/material.dart';
import 'package:pasella/pages/wallet/tabs/banking_details_tab.dart';
import 'package:pasella/pages/wallet/tabs/pricing_tab.dart';
import 'package:pasella/pages/wallet/tabs/unified_history_tab.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/feature_flags.dart';

enum InfoView { history, banking, info }

/// Billing's Account landing page.
///
/// Account remains a top-level Billing tab, but its destinations use ordinary
/// list navigation instead of another segmented control nested inside the
/// tab. Each destination opens as a full page with standard back navigation.
class InfoCenterTab extends StatefulWidget {
  const InfoCenterTab({
    super.key,
    required this.walletVM,
    this.initialView,
  });

  final WalletViewModel walletVM;
  final InfoView? initialView;

  @override
  State<InfoCenterTab> createState() => _InfoCenterTabState();
}

class _InfoCenterTabState extends State<InfoCenterTab> {
  bool _openedInitialView = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_openedInitialView || !_isEnabled(widget.initialView)) return;
    _openedInitialView = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(widget.initialView!);
    });
  }

  bool _isEnabled(InfoView? view) {
    switch (view) {
      case InfoView.history:
        return FeatureFlags.enableTransactionHistory;
      case InfoView.banking:
        return FeatureFlags.enableBankingDetails;
      case InfoView.info:
        return FeatureFlags.enablePricingInfo;
      case null:
        return false;
    }
  }

  void _open(InfoView view) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BillingAccountDestinationPage(
          view: view,
          walletVM: widget.walletVM,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BillingAccountMenu(
      showHistory: FeatureFlags.enableTransactionHistory,
      showBanking: FeatureFlags.enableBankingDetails,
      showFees: FeatureFlags.enablePricingInfo,
      onHistory: () => _open(InfoView.history),
      onBanking: () => _open(InfoView.banking),
      onFees: () => _open(InfoView.info),
    );
  }
}

/// Testable, Firebase-free presentation for the Account landing page.
class BillingAccountMenu extends StatelessWidget {
  const BillingAccountMenu({
    super.key,
    required this.showHistory,
    required this.showBanking,
    required this.showFees,
    required this.onHistory,
    required this.onBanking,
    required this.onFees,
  });

  final bool showHistory;
  final bool showBanking;
  final bool showFees;
  final VoidCallback onHistory;
  final VoidCallback onBanking;
  final VoidCallback onFees;

  @override
  Widget build(BuildContext context) {
    final destinations = <_AccountDestination>[
      if (showHistory)
        _AccountDestination(
          key: const ValueKey('billing-account-history'),
          icon: Icons.receipt_long_outlined,
          title: 'Transaction history',
          color: Colors.green.shade700,
          onTap: onHistory,
        ),
      if (showBanking)
        _AccountDestination(
          key: const ValueKey('billing-account-banking'),
          icon: Icons.account_balance_outlined,
          title: 'Payment setup',
          color: Colors.blue.shade700,
          onTap: onBanking,
        ),
      if (showFees)
        _AccountDestination(
          key: const ValueKey('billing-account-fees'),
          icon: Icons.info_outline,
          title: 'Fees and limits',
          color: Colors.orange.shade800,
          onTap: onFees,
        ),
    ];

    if (destinations.isEmpty) {
      return const Center(child: Text('No account information available'));
    }

    return Padding(
      key: const ValueKey('billing-account-dashboard'),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      child: Column(
        children: [
          for (var index = 0; index < destinations.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            Expanded(
              child: _AccountMenuTile(destination: destinations[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountDestination {
  const _AccountDestination({
    required this.key,
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final Key key;
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
}

class _AccountMenuTile extends StatelessWidget {
  const _AccountMenuTile({
    required this.destination,
  });

  final _AccountDestination destination;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: destination.key,
      color: destination.color.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: destination.color.withValues(alpha: .16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: destination.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: destination.color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  destination.icon,
                  size: 25,
                  color: destination.color,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  destination.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: destination.color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BillingAccountDestinationPage extends StatelessWidget {
  const BillingAccountDestinationPage({
    super.key,
    required this.view,
    required this.walletVM,
  });

  final InfoView view;
  final WalletViewModel walletVM;

  String get _title {
    switch (view) {
      case InfoView.history:
        return 'Transaction History';
      case InfoView.banking:
        return 'Payment Setup';
      case InfoView.info:
        return 'Fees and Limits';
    }
  }

  Widget get _content {
    switch (view) {
      case InfoView.history:
        return UnifiedHistoryTab(viewModel: walletVM);
      case InfoView.banking:
        return const BankingDetailsTab();
      case InfoView.info:
        return const PricingInfoTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: _title),
      body: SafeArea(child: _content),
    );
  }
}
