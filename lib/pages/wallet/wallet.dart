import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/wallet/tabs/info_center_tab.dart';
import 'package:pasella/pages/wallet/tabs/sales_balance_tab.dart';
import 'package:pasella/pages/wallet/tabs/top_up_tab.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/full_repayment_report.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/billing/wallet_balance_provider.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/utils/wallet_utils.dart';
import 'package:provider/provider.dart';

/// Legacy enum values are retained for deep-link compatibility. In 4.8,
/// `withdraw` opens Settlements and `topUp` opens Campaign Credits.
enum WalletInitialTab { withdraw, topUp, account }

/// Visual summary for the balances merchants use most.
class BillingBalancePanel extends StatelessWidget {
  const BillingBalancePanel({
    super.key,
    required this.campaignBalance,
    required this.salesBalance,
    required this.storeName,
    required this.sharedCampaignCredits,
    this.onCampaignTap,
    this.cashAdvanceBalance,
  });

  final double campaignBalance;
  final double salesBalance;
  final String storeName;
  final bool sharedCampaignCredits;
  final VoidCallback? onCampaignTap;
  final double? cashAdvanceBalance;

  @override
  Widget build(BuildContext context) {
    final campaignColor = campaignBalance < 5 && onCampaignTap != null
        ? Colors.orange.shade800
        : Colors.green.shade700;
    final campaign = _BillingBalanceItem(
      label: 'Campaign Credits',
      scope: sharedCampaignCredits ? 'All stores' : null,
      amount: campaignBalance,
      icon: Icons.campaign_outlined,
      color: campaignColor,
      onTap: onCampaignTap,
    );
    final legacy = _BillingBalanceItem(
      label: 'Legacy Balance',
      scope: storeName,
      amount: salesBalance,
      icon: Icons.history_rounded,
      color: Colors.orange.shade900,
    );
    final items = <_BillingBalanceItem>[
      campaign,
      if (cashAdvanceBalance case final amount?)
        _BillingBalanceItem(
          label: 'Cash advance',
          amount: amount,
          icon: Icons.account_balance_outlined,
          color: Colors.orange.shade800,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          SizedBox(
            height: 112,
            child: _BillingBalanceTile(
              key: const ValueKey('billing-balance-campaign'),
              item: campaign,
              horizontal: true,
            ),
          ),
          if (salesBalance > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 88,
              child: _BillingBalanceTile(
                key: const ValueKey('billing-balance-legacy'),
                item: legacy,
                horizontal: true,
              ),
            ),
          ],
          if (cashAdvanceBalance != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 88,
              child: _BillingBalanceTile(
                key: const ValueKey('billing-balance-cash-advance'),
                item: items.last,
                horizontal: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BillingBalanceItem {
  const _BillingBalanceItem({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    this.scope,
    this.onTap,
  });

  final String label;
  final String? scope;
  final double amount;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
}

class _BillingBalanceTile extends StatelessWidget {
  const _BillingBalanceTile({
    super.key,
    required this.item,
    this.horizontal = false,
  });

  final _BillingBalanceItem item;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final amount = Text(
      CurrencyUtil.format(item.amount),
      maxLines: 1,
      style: TextStyle(
        fontSize: horizontal ? 21 : 24,
        height: 1,
        fontWeight: FontWeight.w800,
        color: item.color,
      ),
    );
    final content = horizontal
        ? Row(
            children: [
              _BalanceIcon(item: item),
              const SizedBox(width: 12),
              Expanded(child: _BalanceLabel(item: item)),
              const SizedBox(width: 12),
              FittedBox(fit: BoxFit.scaleDown, child: amount),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _BalanceIcon(item: item),
                  if (item.onTap != null)
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: item.color,
                    ),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: amount,
              ),
              const SizedBox(height: 8),
              _BalanceLabel(item: item),
            ],
          );

    return Material(
      color: item.color.withValues(alpha: .09),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: item.color.withValues(alpha: .18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: EdgeInsets.all(horizontal ? 14 : 16),
          child: content,
        ),
      ),
    );
  }
}

class _BalanceIcon extends StatelessWidget {
  const _BalanceIcon({required this.item});

  final _BillingBalanceItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(item.icon, size: 21, color: item.color),
    );
  }
}

class _BalanceLabel extends StatelessWidget {
  const _BalanceLabel({required this.item});

  final _BillingBalanceItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (item.scope case final scope?)
          Text(
            scope,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade700,
                ),
          ),
      ],
    );
  }
}

class WalletPage extends StatefulWidget {
  const WalletPage({
    super.key,
    this.initialTab = WalletInitialTab.account,
    this.initialAccountView,
  });

  static const id = '/walletPage';

  final WalletInitialTab initialTab;
  final InfoView? initialAccountView;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> with TickerProviderStateMixin {
  late TabController _tabController;
  final WalletViewModel walletVM = WalletViewModel();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _getTabCount(),
      vsync: this,
      initialIndex: _getInitialTabIndex(),
    );
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {}); // Rerender when tab changes
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    walletVM.dispose();
    super.dispose();
  }

  int _getTabCount() {
    // Settlements is always present. Credits and setup/info respect the
    // existing feature flags so released configurations remain compatible.
    int count = 1; // Settlements
    if (FeatureFlags.enableTopUp) count++;
    if (FeatureFlags.enableCashAdvance ||
        FeatureFlags.enableTransactionHistory ||
        FeatureFlags.enableBankingDetails ||
        FeatureFlags.enablePricingInfo) {
      count++; // Info tab
    }
    return count;
  }

  bool get _hasInfoTab =>
      FeatureFlags.enableCashAdvance ||
      FeatureFlags.enableTransactionHistory ||
      FeatureFlags.enableBankingDetails ||
      FeatureFlags.enablePricingInfo;

  int _getInitialTabIndex() {
    switch (widget.initialTab) {
      case WalletInitialTab.account:
        return 0;
      case WalletInitialTab.topUp:
        return _topUpTabIndex() ?? 0;
      case WalletInitialTab.withdraw:
        return _withdrawTabIndex();
    }
  }

  int _withdrawTabIndex() {
    var index = 0;
    if (_hasInfoTab) index++;
    if (FeatureFlags.enableTopUp) index++;
    return index;
  }

  /// PAS-UX-WTC: index of the Top-Up tab in the current configuration,
  /// or null when [FeatureFlags.enableTopUp] is off. Used by the App
  /// Balance card's inline "Top up" action so it can jump to the tab
  /// without needing a separate navigation surface.
  int? _topUpTabIndex() {
    if (!FeatureFlags.enableTopUp) return null;
    return _hasInfoTab ? 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    final campaignWallet = context.watch<WalletBalanceProvider>();
    // 🔥 Dynamically generate the tab views based on feature flags
    final List<Widget> tabViews = [];
    final List<Tab> tabLabels = [];

    final bool hasInfoTab = _hasInfoTab;

    if (hasInfoTab) {
      tabLabels.add(const Tab(text: 'Setup & Info'));
      tabViews.add(
        InfoCenterTab(
          walletVM: walletVM,
          initialView: widget.initialAccountView,
        ),
      );
    }

    if (FeatureFlags.enableTopUp) {
      tabLabels.add(const Tab(text: 'Campaign Credits'));
      tabViews.add(const TopUpTab());
    }

    // Verified online proceeds settle directly; there is no public withdrawal
    // action for V2 money.
    tabLabels.add(const Tab(text: 'Settlements'));
    tabViews.add(const SalesBalanceTab());

    return DefaultTabController(
      length: tabLabels.length,
      child: Scaffold(
        appBar: const CustomAppBar(title: 'Billing & Payments'),
        body: SafeArea(
          child: Padding(
            padding: LayoutConstants.padding10Horizontal,
            child: Column(
              children: [
                SizedBox(height: SizeConfig.heightMultiplier * 2),

                // 🟢 Dynamically show the correct balance based on selected tab
                StreamBuilder<WalletState>(
                  stream: walletVM.walletStateStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final walletState = snapshot.data!;

                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            BillingBalancePanel(
                              campaignBalance: campaignWallet.virtualBalance,
                              salesBalance: walletState.salesVirtualBalance,
                              storeName: campaignWallet.activeStoreName,
                              sharedCampaignCredits:
                                  campaignWallet.sharedCampaignCredits,
                              onCampaignTap: FeatureFlags.enableTopUp
                                  ? () {
                                      final index = _topUpTabIndex();
                                      if (index != null) {
                                        _tabController.animateTo(index);
                                      }
                                    }
                                  : null,
                              cashAdvanceBalance: FeatureFlags.enableCashAdvance
                                  ? walletState.cashAdvanceBalance
                                  : null,
                            ),
                            if (FeatureFlags.enableCashAdvance &&
                                walletState.cashAdvanceWithdrawn > 0)
                              _repaymentCard(walletState),
                          ],
                        ),
                      ),
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

  Widget _repaymentCard(WalletState walletState) {
    // PAS-UX-12: single FutureBuilder for the only computed value
    // on this card. Previously this title had its own per-row
    // builder while the bottom sheet had three more, all hitting
    // RemoteConfig in parallel.
    return Card(
      margin: EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 1),
      color: Colors.red.shade50,
      child: ListTile(
        leading: const Icon(Icons.warning, color: Colors.red),
        title: FutureBuilder<WalletBreakdown>(
          future: WalletUtils.computeBreakdown(walletState),
          builder: (context, snapshot) {
            final due = snapshot.data?.totalOwed ?? '...';
            return Text(
              "💸 Repayment Due: $due",
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.6),
            );
          },
        ),
        trailing: TextButton(
          onPressed: () => _showRepaymentBottomSheet(context, walletState),
          child: const Text("View", style: TextStyle(color: Colors.red)),
        ),
      ),
    );
  }

  void _showRepaymentBottomSheet(
    BuildContext context,
    WalletState walletState,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        // PAS-UX-12: one breakdown for the whole sheet. The future
        // is created inside the builder which is fine: the sheet
        // doesn't rebuild itself once it has resolved, and closing
        // the sheet drops the subscription.
        final breakdown = WalletUtils.computeBreakdown(walletState);
        return Padding(
          padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
          child: FutureBuilder<WalletBreakdown>(
            future: breakdown,
            builder: (context, snapshot) {
              final b = snapshot.data ?? WalletBreakdown.loading;
              return Column(
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
                  Text(
                    'Repayment Details',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: SizeConfig.textMultiplier * 2,
                    ),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  _infoRow('Fee Charged', b.advanceFee),
                  _infoRow('Bank Fee', b.bankFee),
                  _infoRow('Penalty Applied', b.penaltyFee),
                  _infoRow('Amount Due', b.totalOwed),
                  _infoRow('Due Date', b.dueDate),
                  _infoRow('Suspended', b.suspended),
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FullRepaymentReportPage(
                            walletState: walletState,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'View Full Report',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 0.5,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.6),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: SizeConfig.textMultiplier * 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
