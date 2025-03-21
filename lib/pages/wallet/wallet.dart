import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/tabs/balance_payout_tab.dart';
import 'package:pasella/pages/wallet/tabs/banking_details_tab.dart';
import 'package:pasella/pages/wallet/tabs/cash_advance_tab.dart';
import 'package:pasella/pages/wallet/tabs/histroy_tab.dart';
import 'package:pasella/pages/wallet/tabs/payout_history_tab.dart';
import 'package:pasella/pages/wallet/tabs/pricing_tab.dart';
import 'package:pasella/pages/wallet/tabs/top_up_tab.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/full_repayment_report.dart';
import 'package:pasella/shared/widgets/page_header.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/feature_flags.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  static const id = '/walletPage';

  @override
  _WalletPageState createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> with TickerProviderStateMixin {
  late TabController _tabController;
  final WalletViewModel walletVM = WalletViewModel();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _getTabCount(), vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Rerender when tab changes
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int _getTabCount() {
    return [
      FeatureFlags.enableTopUp,
      FeatureFlags.enableCashAdvance,
      FeatureFlags.enableTransactionHistory,
      FeatureFlags.enableBalancePayout,
      FeatureFlags.enableBankingDetails,
      FeatureFlags.enablePricingInfo,
      FeatureFlags.enablePayoutHistory
    ].where((enabled) => enabled).length;
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 Dynamically generate the tab views based on feature flags
    final List<Widget> tabViews = [];
    final List<Tab> tabLabels = [];

    if (FeatureFlags.enableTopUp) {
      tabLabels.add(const Tab(text: 'Top-Up'));
      tabViews.add(const TopUpTab());
    }

    if (FeatureFlags.enableCashAdvance) {
      tabLabels.add(const Tab(text: 'Cash Advance'));
      tabViews.add(const CashAdvanceTab());
    }

    if (FeatureFlags.enableBalancePayout) {
      tabLabels.add(const Tab(text: 'Withdraw'));
      tabViews.add(const BalancePayoutTab());
    }

    if (FeatureFlags.enableBankingDetails) {
      tabLabels.add(const Tab(text: 'Banking Details'));
      tabViews.add(const BankingDetailsTab());
    }

    if (FeatureFlags.enableTransactionHistory) {
      tabLabels.add(const Tab(text: 'Transaction History'));
      tabViews.add(const TransactionHistoryTab());
    }

    if (FeatureFlags.enablePayoutHistory) {
      tabLabels.add(const Tab(text: 'Payout History'));
      tabViews.add(const PayoutHistoryTab());
    }

    if (FeatureFlags.enablePricingInfo) {
      tabLabels.add(const Tab(text: 'Pricing Info'));
      tabViews.add(const PricingInfoTab());
    }

    return DefaultTabController(
      length: tabLabels.length,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: SizeConfig.imageSizeMultiplier * 4),
            child: Column(
              children: [
                SizedBox(height: SizeConfig.heightMultiplier * 2),
                const PageHeader(),
                SizedBox(height: SizeConfig.heightMultiplier * 3),

                // 🟢 Dynamically show the correct balance based on selected tab
                StreamBuilder<WalletState>(
                  stream: walletVM.walletStateStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final walletState = snapshot.data!;

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _balanceCard(
                          title: 'App Balance',
                          amount: walletState.balance,
                          description: 'For in-app use only',
                          color: Colors.green,
                          icon: Icons.account_balance_wallet,
                        ),
                        _balanceCard(
                          title: 'Cash Advance',
                          amount: walletState.cashAdvanceBalance,
                          description: 'Available for withdrawal',
                          color: Colors.blue,
                          icon: Icons.account_balance_wallet,
                        ),
                        if (walletState.cashAdvanceWithdrawn > 0)
                          _repaymentCard(walletState),
                      ],
                    );
                  },
                ),

                // 🟢 Tab Bar
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelStyle: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.8,
                    fontWeight: FontWeight.normal,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.8,
                    fontWeight: FontWeight.normal,
                  ),
                  tabs: tabLabels,
                ),

                // 🟢 Expanded Tab Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: tabViews,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 🔥 Optimized & Compact Balance Card UI
  Widget _balanceCard({
    required String title,
    required double amount,
    required String description,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
          vertical: SizeConfig.heightMultiplier * 2,
          horizontal: SizeConfig.imageSizeMultiplier * 4),
      margin: EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 0.8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 🔹 Left Section: Icon + Text
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.2),
                child: Icon(icon,
                    size: SizeConfig.textMultiplier * 2.5, color: color),
              ),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 3),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.8,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.4,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 🔹 Right Section: Balance Amount
          Text(
            CurrencyUtil.format(amount),
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 2,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _repaymentCard(WalletState walletState) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 1),
      color: Colors.red.shade50,
      child: ListTile(
        leading: const Icon(Icons.warning, color: Colors.red),
        title: Text(
            "💸 Repayment Due: ${CurrencyUtil.format(walletState.cashAdvanceBalance * 1.1)}",
            style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.6)),
        trailing: TextButton(
          onPressed: () => _showRepaymentBottomSheet(context, walletState),
          child: const Text("View", style: TextStyle(color: Colors.red)),
        ),
      ),
    );
  }

  void _showRepaymentBottomSheet(
      BuildContext context, WalletState walletState) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 2),
              const Text('Repayment Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              SizedBox(height: SizeConfig.heightMultiplier * 2),
              _infoRow('Amount Due',
                  CurrencyUtil.format(walletState.cashAdvanceBalance * 1.1)),
              _infoRow(
                  'Penalty',
                  walletState.penaltyFee > 0
                      ? CurrencyUtil.format(walletState.penaltyFee)
                      : 'No penalty'),
              _infoRow(
                  'Due Date',
                  walletState.cashAdvanceDueDate != null
                      ? DateFormat('dd MMM yyyy')
                          .format(walletState.cashAdvanceDueDate!)
                      : 'Not Set'),
              _infoRow(
                  'Suspended', walletState.accountSuspended ? 'Yes' : 'No'),
              SizedBox(height: SizeConfig.heightMultiplier * 2),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          FullRepaymentReportPage(walletState: walletState),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('View Full Report',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding:
          EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.6)),
          Text(value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: SizeConfig.textMultiplier * 1.6,
              )),
        ],
      ),
    );
  }
}
