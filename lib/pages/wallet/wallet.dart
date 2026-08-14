import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/tabs/info_center_tab.dart';
import 'package:pasella/pages/wallet/tabs/sales_balance_tab.dart';
import 'package:pasella/pages/wallet/tabs/unified_history_tab.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/campaign_topup_verification_screen.dart';
import 'package:pasella/pages/wallet/widgets/paystack_form.dart';
import 'package:pasella/pages/wallet/widgets/full_repayment_report.dart';
import 'package:pasella/services/campaign_topup_pending_store.dart';
import 'package:pasella/services/payment_setup_service.dart';
import 'package:pasella/services/paystack_service.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/billing/wallet_balance_provider.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/utils/wallet_utils.dart';
import 'package:provider/provider.dart';

/// Legacy enum values are retained for deep-link compatibility. In 4.8,
/// `withdraw` opens Online payments and `topUp` opens Add money.
enum WalletInitialTab { withdraw, topUp, account }

enum WalletInitialDestination { payouts, addMoney, money }

@visibleForTesting
WalletInitialDestination walletInitialDestination(WalletInitialTab tab) =>
    switch (tab) {
      WalletInitialTab.withdraw => WalletInitialDestination.payouts,
      WalletInitialTab.topUp => WalletInitialDestination.addMoney,
      WalletInitialTab.account => WalletInitialDestination.money,
    };

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
      label: 'SpazaOne balance',
      scope: sharedCampaignCredits ? 'Shared across your shops' : null,
      description: 'Use this balance for customer messages and promotions.',
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
          _BillingBalanceTile(
            key: const ValueKey('billing-balance-campaign'),
            item: campaign,
            horizontal: true,
          ),
          if (salesBalance > 0) ...[
            const SizedBox(height: 10),
            _BillingBalanceTile(
              key: const ValueKey('billing-balance-legacy'),
              item: legacy,
              horizontal: true,
            ),
          ],
          if (cashAdvanceBalance != null) ...[
            const SizedBox(height: 10),
            _BillingBalanceTile(
              key: const ValueKey('billing-balance-cash-advance'),
              item: items.last,
              horizontal: true,
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
    this.description,
    this.onTap,
  });

  final String label;
  final String? scope;
  final String? description;
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
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _BalanceIcon(item: item),
                  const SizedBox(width: 12),
                  Expanded(child: _BalanceLabel(item: item)),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: amount,
                    ),
                  ),
                ],
              ),
              if (item.description case final description?) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade800,
                        height: 1.3,
                      ),
                ),
              ],
              if (item.onTap != null) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: item.onTap,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add money'),
                  ),
                ),
              ],
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

class WalletHubMenu extends StatelessWidget {
  const WalletHubMenu({
    super.key,
    required this.campaignBalance,
    required this.sharedCampaignCredits,
    required this.hasPendingPayment,
    required this.overview,
    required this.overviewLoading,
    required this.overviewHasError,
    required this.showBalance,
    required this.showOnlinePayments,
    required this.showCosts,
    required this.onBalance,
    required this.onOnlinePayments,
    required this.onCosts,
  });

  final double campaignBalance;
  final bool sharedCampaignCredits;
  final bool hasPendingPayment;
  final MerchantPaymentOverview? overview;
  final bool overviewLoading;
  final bool overviewHasError;
  final bool showBalance;
  final bool showOnlinePayments;
  final bool showCosts;
  final VoidCallback onBalance;
  final VoidCallback onOnlinePayments;
  final VoidCallback onCosts;

  String get _onlinePaymentStatus {
    if (overviewLoading) return 'Checking setup…';
    if (overviewHasError || overview == null) {
      return 'Setup status unavailable';
    }
    if (overview!.enabled) return 'Ready to accept online payments';
    if (overview!.profile.bankVerificationStatus == 'pending_review') {
      return 'Bank details are being checked';
    }
    return 'Set up your bank account for online sales';
  }

  @override
  Widget build(BuildContext context) {
    final destinations = <_WalletHubDestination>[
      if (showBalance)
        _WalletHubDestination(
          key: const ValueKey('wallet-hub-balance'),
          icon: Icons.account_balance_wallet_outlined,
          title: 'SpazaOne balance',
          value: CurrencyUtil.format(campaignBalance),
          subtitle: hasPendingPayment
              ? 'Payment confirmation in progress'
              : sharedCampaignCredits
                  ? 'Shared across your shops'
                  : 'Customer messages and promotions',
          color: Colors.green.shade700,
          onTap: onBalance,
        ),
      if (showOnlinePayments)
        _WalletHubDestination(
          key: const ValueKey('wallet-hub-online-payments'),
          icon: Icons.account_balance_outlined,
          title: 'Online payments',
          subtitle: _onlinePaymentStatus,
          color: Colors.blue.shade700,
          onTap: onOnlinePayments,
        ),
      if (showCosts)
        _WalletHubDestination(
          key: const ValueKey('wallet-hub-costs'),
          icon: Icons.info_outline_rounded,
          title: 'Costs and limits',
          subtitle: 'Message prices, payment fees and account limits',
          color: Colors.orange.shade800,
          onTap: onCosts,
        ),
    ];

    return Column(
      key: const ValueKey('wallet-payments-hub'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose what you want to manage',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your balance and online sales are kept separate so each is easier to manage.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < destinations.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          _WalletHubTile(destination: destinations[index]),
        ],
      ],
    );
  }
}

class _WalletHubDestination {
  const _WalletHubDestination({
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.value,
  });

  final Key key;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final Color color;
  final VoidCallback onTap;
}

class _WalletHubTile extends StatelessWidget {
  const _WalletHubTile({required this.destination});

  final _WalletHubDestination destination;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: destination.key,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: destination.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: destination.color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(destination.icon, color: destination.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            destination.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (destination.value case final value?) ...[
                          const SizedBox(width: 8),
                          Text(
                            value,
                            style: TextStyle(
                              color: destination.color,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      destination.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
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

class _WalletPageState extends State<WalletPage> {
  final WalletViewModel walletVM = WalletViewModel();
  late Future<MerchantPaymentOverview> _overviewFuture;
  bool _handledInitialDestination = false;
  String? _pendingIntentId;

  @override
  void initState() {
    super.initState();
    _overviewFuture =
        PaymentSetupService.overview(StoreSession.instance.storeId);
    _pendingIntentId = CampaignTopupPendingStore.read(
      StoreSession.instance.storeId,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledInitialDestination) return;
    _handledInitialDestination = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resumePendingThenOpenInitial();
    });
  }

  @override
  void dispose() {
    walletVM.dispose();
    super.dispose();
  }

  Future<void> _resumePendingThenOpenInitial() async {
    final pendingStatus = await _checkPendingPayment();
    if (!context.mounted) {
      return;
    }
    if (pendingStatus != null) {
      _openBalance();
      return;
    }
    if (widget.initialAccountView case final view?) {
      switch (view) {
        case InfoView.history:
          _openBalance();
        case InfoView.banking:
          _openOnlinePayments();
        case InfoView.info:
          _openInfo(InfoView.info);
      }
      return;
    }
    switch (walletInitialDestination(widget.initialTab)) {
      case WalletInitialDestination.addMoney:
        if (FeatureFlags.enableTopUp) {
          await _openAddMoney();
          if (mounted) _openBalance();
        }
      case WalletInitialDestination.payouts:
        _openOnlinePayments();
      case WalletInitialDestination.money:
        break;
    }
  }

  Future<CampaignTopupStatus?> _checkPendingPayment() async {
    final merchantId = StoreSession.instance.storeId;
    final pendingIntent = _pendingIntentId;
    if (pendingIntent == null) return null;
    final status = await Navigator.of(context).push<CampaignTopupStatus>(
      MaterialPageRoute(
        builder: (_) => CampaignTopupVerificationScreen(
          statusReader: () => PaystackService.campaignTopupStatusV2(
            merchantId: merchantId,
            intentId: pendingIntent,
          ),
        ),
      ),
    );
    if (status != null && status != CampaignTopupStatus.checking) {
      await CampaignTopupPendingStore.clear(merchantId);
      if (mounted) setState(() => _pendingIntentId = null);
    }
    return status;
  }

  void _openInfo(InfoView view) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BillingAccountDestinationPage(
          view: view,
          walletVM: walletVM,
        ),
      ),
    );
  }

  void _openBalance() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WalletBalanceDestinationPage(
          hasPendingIntent: () => _pendingIntentId != null,
          onAddMoney: _openAddMoney,
          onCheckPending: _checkPendingPayment,
          repaymentCardBuilder: _repaymentCard,
        ),
      ),
    );
  }

  void _openOnlinePayments() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WalletOnlinePaymentsPage(),
      ),
    );
  }

  Future<void> _openAddMoney({List<String>? channels}) async {
    await Navigator.of(context).push<CampaignTopupStatus>(
      MaterialPageRoute(
        builder: (_) => PaystackFormScreen(
          allowedChannels: channels ?? const ['eft', 'capitec_pay', 'qr'],
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _pendingIntentId = CampaignTopupPendingStore.read(
        StoreSession.instance.storeId,
      );
      _overviewFuture = PaymentSetupService.overview(
        StoreSession.instance.storeId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final campaignWallet = context.watch<WalletBalanceProvider>();
    return Scaffold(
      appBar: const CustomAppBar(title: 'Wallet & payments'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
          child: FutureBuilder<MerchantPaymentOverview>(
            future: _overviewFuture,
            builder: (context, snapshot) => WalletHubMenu(
              campaignBalance: campaignWallet.virtualBalance,
              sharedCampaignCredits: campaignWallet.sharedCampaignCredits,
              hasPendingPayment: _pendingIntentId != null,
              overview: snapshot.data,
              overviewLoading: snapshot.connectionState != ConnectionState.done,
              overviewHasError: snapshot.hasError,
              showBalance: FeatureFlags.enableTransactionHistory ||
                  FeatureFlags.enableTopUp,
              showOnlinePayments: FeatureFlags.enableBankingDetails,
              showCosts: FeatureFlags.enablePricingInfo,
              onBalance: _openBalance,
              onOnlinePayments: _openOnlinePayments,
              onCosts: () => _openInfo(InfoView.info),
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

class WalletBalanceDestinationPage extends StatefulWidget {
  const WalletBalanceDestinationPage({
    super.key,
    required this.hasPendingIntent,
    required this.onAddMoney,
    required this.onCheckPending,
    required this.repaymentCardBuilder,
  });

  final bool Function() hasPendingIntent;
  final Future<void> Function() onAddMoney;
  final Future<CampaignTopupStatus?> Function() onCheckPending;
  final Widget Function(WalletState) repaymentCardBuilder;

  @override
  State<WalletBalanceDestinationPage> createState() =>
      _WalletBalanceDestinationPageState();
}

class _WalletBalanceDestinationPageState
    extends State<WalletBalanceDestinationPage> {
  final WalletViewModel _walletVM = WalletViewModel();
  late bool _hasPendingIntent;
  int _historyVersion = 0;

  @override
  void initState() {
    super.initState();
    _hasPendingIntent = widget.hasPendingIntent();
  }

  @override
  void dispose() {
    _walletVM.dispose();
    super.dispose();
  }

  Future<void> _addMoney() async {
    await widget.onAddMoney();
    if (!mounted) return;
    setState(() {
      _hasPendingIntent = widget.hasPendingIntent();
      _historyVersion++;
    });
  }

  Future<void> _checkPending() async {
    await widget.onCheckPending();
    if (!mounted) return;
    setState(() {
      _hasPendingIntent = widget.hasPendingIntent();
      _historyVersion++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final campaignWallet = context.watch<WalletBalanceProvider>();
    return Scaffold(
      appBar: const CustomAppBar(title: 'SpazaOne balance'),
      body: SafeArea(
        child: ListView(
          key: const ValueKey('spazaone-balance-page'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            StreamBuilder<WalletState>(
              stream: _walletVM.walletStateStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final walletState = snapshot.data!;
                return Column(
                  children: [
                    BillingBalancePanel(
                      campaignBalance: campaignWallet.virtualBalance,
                      salesBalance: walletState.salesVirtualBalance,
                      storeName: campaignWallet.activeStoreName,
                      sharedCampaignCredits:
                          campaignWallet.sharedCampaignCredits,
                      onCampaignTap:
                          FeatureFlags.enableTopUp ? _addMoney : null,
                      cashAdvanceBalance: FeatureFlags.enableCashAdvance
                          ? walletState.cashAdvanceBalance
                          : null,
                    ),
                    if (FeatureFlags.enableCashAdvance &&
                        walletState.cashAdvanceWithdrawn > 0)
                      widget.repaymentCardBuilder(walletState),
                  ],
                );
              },
            ),
            if (_hasPendingIntent) ...[
              _PendingPaymentActivity(
                onCheckAgain: () => unawaited(_checkPending()),
              ),
              const SizedBox(height: 18),
            ],
            if (FeatureFlags.enableTransactionHistory) ...[
              Text(
                'Balance activity',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              UnifiedHistoryTab(
                key: ValueKey('balance-history-$_historyVersion'),
                viewModel: _walletVM,
                embedded: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class WalletOnlinePaymentsPage extends StatefulWidget {
  const WalletOnlinePaymentsPage({super.key});

  @override
  State<WalletOnlinePaymentsPage> createState() =>
      _WalletOnlinePaymentsPageState();
}

class _WalletOnlinePaymentsPageState extends State<WalletOnlinePaymentsPage> {
  late Future<MerchantPaymentOverview> _overview;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _overview = PaymentSetupService.overview(StoreSession.instance.storeId);
  }

  Future<void> _openSetup() async {
    final setupWalletVM = WalletViewModel();
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BillingAccountDestinationPage(
            view: InfoView.banking,
            walletVM: setupWalletVM,
          ),
        ),
      );
    } finally {
      setupWalletVM.dispose();
    }
    if (!mounted) return;
    setState(_refresh);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Online payments'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(_refresh);
            await _overview;
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            child: FutureBuilder<MerchantPaymentOverview>(
              future: _overview,
              builder: (context, snapshot) => MoneyPayoutsSection(
                overview: snapshot.data,
                loading: snapshot.connectionState != ConnectionState.done,
                hasError: snapshot.hasError,
                onSetup: FeatureFlags.enableBankingDetails ? _openSetup : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingPaymentActivity extends StatelessWidget {
  const _PendingPaymentActivity({required this.onCheckAgain});

  final VoidCallback onCheckAgain;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.orange.withValues(alpha: .08),
      child: ListTile(
        leading: const SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
        title: const Text(
          'We are still checking your payment',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Your SpazaOne balance will update only after confirmation.',
        ),
        trailing: TextButton(
          onPressed: onCheckAgain,
          child: const Text('Check'),
        ),
      ),
    );
  }
}
