import 'package:flutter/material.dart';
import 'package:pasella/pages/wallet/tabs/banking_details_tab.dart';
import 'package:pasella/pages/wallet/tabs/cash_advance_tab.dart';
import 'package:pasella/pages/wallet/tabs/pricing_tab.dart';
import 'package:pasella/pages/wallet/tabs/unified_history_tab.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/utils/feature_flags.dart';

class InfoCenterTab extends StatelessWidget {
  final WalletViewModel walletVM;

  const InfoCenterTab({super.key, required this.walletVM});

  @override
  Widget build(BuildContext context) {
    final List<Tab> tabLabels = [];
    final List<Widget> tabViews = [];

    if (FeatureFlags.enableCashAdvance) {
      tabLabels.add(const Tab(text: 'Cash Advance'));
      tabViews.add(const CashAdvanceTab());
    }
    if (FeatureFlags.enableTransactionHistory) {
      tabLabels.add(const Tab(text: 'Transaction History'));
      tabViews.add(UnifiedHistoryTab(viewModel: walletVM));
    }
    if (FeatureFlags.enableBankingDetails) {
      tabLabels.add(const Tab(text: 'Banking Details'));
      tabViews.add(const BankingDetailsTab());
    }
    if (FeatureFlags.enablePricingInfo) {
      tabLabels.add(const Tab(text: 'Info'));
      tabViews.add(const PricingInfoTab());
    }

    if (tabLabels.isEmpty) {
      return const Center(child: Text('No information available'));
    }

    return DefaultTabController(
      length: tabLabels.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabs: tabLabels,
          ),
          Expanded(
            child: TabBarView(
              children: tabViews,
            ),
          ),
        ],
      ),
    );
  }
}
