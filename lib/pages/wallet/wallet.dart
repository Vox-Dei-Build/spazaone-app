import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
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
import 'package:shimmer/shimmer.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey('billing-balance-campaign'),
          container: true,
          label: 'SpazaOne balance ${CurrencyUtil.format(campaignBalance)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Available balance',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: kSecondaryAccent,
                    ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  CurrencyUtil.format(campaignBalance),
                  style: const TextStyle(
                    color: kTertiaryColor,
                    fontSize: 40,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Use this for WhatsApp messages and promotions.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: kTertiaryColor,
                      height: 1.35,
                    ),
              ),
              if (sharedCampaignCredits) ...[
                const SizedBox(height: 3),
                Text(
                  'Shared across your shops',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: kSecondaryAccent,
                      ),
                ),
              ],
              if (onCampaignTap != null) ...[
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey('billing-add-money'),
                  onPressed: onCampaignTap,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Add money'),
                ),
              ],
            ],
          ),
        ),
        if (salesBalance > 0) ...[
          const SizedBox(height: 24),
          Padding(
            key: const ValueKey('billing-balance-legacy'),
            padding: const EdgeInsets.only(top: 20),
            child: _SecondaryBalanceRow(
              label: 'Legacy Balance',
              detail: storeName,
              amount: salesBalance,
              icon: Icons.history_rounded,
            ),
          ),
        ],
        if (cashAdvanceBalance case final amount?) ...[
          const SizedBox(height: 20),
          _SecondaryBalanceRow(
            label: 'Cash advance',
            amount: amount,
            icon: Icons.account_balance_outlined,
          ),
        ],
      ],
    );
  }
}

class _SecondaryBalanceRow extends StatelessWidget {
  const _SecondaryBalanceRow({
    required this.label,
    required this.amount,
    required this.icon,
    this.detail,
  });

  final String label;
  final String? detail;
  final double amount;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kHighLightColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: kPrimaryColor, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (detail != null)
                Text(
                  detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: kSecondaryAccent,
                      ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          CurrencyUtil.format(amount),
          style: const TextStyle(
            color: kTertiaryColor,
            fontWeight: FontWeight.w800,
            fontSize: 18,
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
    this.balanceLoading = false,
    required this.showBalance,
    required this.showOnlinePayments,
    required this.showCosts,
    required this.onAddMoney,
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
  final bool balanceLoading;
  final bool showBalance;
  final bool showOnlinePayments;
  final bool showCosts;
  final VoidCallback onAddMoney;
  final VoidCallback onBalance;
  final VoidCallback onOnlinePayments;
  final VoidCallback onCosts;

  String get _onlinePaymentStatus {
    if (overviewLoading) return 'Checking setup…';
    if (overviewHasError || overview == null) {
      return 'Setup status unavailable';
    }
    if (overview!.enabled) return 'Ready';
    if (overview!.profile.bankVerificationStatus == 'pending_review') {
      return 'Being checked';
    }
    return 'Not set up';
  }

  @override
  Widget build(BuildContext context) {
    if (balanceLoading || (overviewLoading && overview == null)) {
      return _WalletHubLoading(
        showBalance: showBalance,
        destinationCount:
            [showBalance, showOnlinePayments, showCosts].where((v) => v).length,
      );
    }

    final destinations = <_WalletHubDestination>[
      if (showBalance)
        _WalletHubDestination(
          key: const ValueKey('wallet-hub-balance'),
          icon: Icons.receipt_long_outlined,
          title: 'Balance activity',
          subtitle: 'Money added and message costs',
          onTap: onBalance,
        ),
      if (showOnlinePayments)
        _WalletHubDestination(
          key: const ValueKey('wallet-hub-online-payments'),
          icon: Icons.account_balance_outlined,
          title: 'Online payments',
          subtitle: 'Set up where your online sales are paid',
          status: _onlinePaymentStatus,
          onTap: onOnlinePayments,
        ),
      if (showCosts)
        _WalletHubDestination(
          key: const ValueKey('wallet-hub-costs'),
          icon: Icons.calculate_outlined,
          title: 'Costs & limits',
          subtitle: 'Message costs and payment fees',
          onTap: onCosts,
        ),
    ];

    return Column(
      key: const ValueKey('wallet-payments-hub'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBalance) ...[
          _WalletBalanceHero(
            balance: campaignBalance,
            sharedAcrossShops: sharedCampaignCredits,
            hasPendingPayment: hasPendingPayment,
            onAddMoney: onAddMoney,
          ),
          const SizedBox(height: 28),
        ],
        for (var index = 0; index < destinations.length; index++) ...[
          _WalletHubTile(destination: destinations[index]),
          if (index < destinations.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _WalletHubLoading extends StatelessWidget {
  const _WalletHubLoading({
    required this.showBalance,
    required this.destinationCount,
  });

  final bool showBalance;
  final int destinationCount;

  @override
  Widget build(BuildContext context) {
    Widget block({required double height, double radius = 16}) => Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return Shimmer.fromColors(
      key: const ValueKey('wallet-loading-shimmer'),
      baseColor: Colors.black12,
      highlightColor: Colors.black26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showBalance) ...[
            block(height: 210, radius: 22),
            const SizedBox(height: 28),
          ],
          for (var index = 0; index < destinationCount; index++) ...[
            block(height: 74),
            if (index < destinationCount - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _WalletBalancePanelLoading extends StatelessWidget {
  const _WalletBalancePanelLoading();

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        key: const ValueKey('wallet-balance-loading-shimmer'),
        baseColor: Colors.black12,
        highlightColor: Colors.black26,
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      );
}

class _WalletBalanceHero extends StatelessWidget {
  const _WalletBalanceHero({
    required this.balance,
    required this.sharedAcrossShops,
    required this.hasPendingPayment,
    required this.onAddMoney,
  });

  final double balance;
  final bool sharedAcrossShops;
  final bool hasPendingPayment;
  final VoidCallback onAddMoney;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('wallet-balance-hero'),
      decoration: BoxDecoration(
        color: kHighLightColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: kPrimaryColor,
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'SpazaOne balance',
                    style: TextStyle(
                      color: kPrimaryColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                CurrencyUtil.format(balance),
                style: const TextStyle(
                  color: kTertiaryColor,
                  fontSize: 38,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'For WhatsApp messages and promotions.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: kTertiaryColor,
                    height: 1.35,
                  ),
            ),
            if (sharedAcrossShops) ...[
              const SizedBox(height: 2),
              Text(
                'Shared across your shops',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: kSecondaryAccent,
                    ),
              ),
            ],
            if (hasPendingPayment) ...[
              const SizedBox(height: 10),
              const Row(
                children: [
                  SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Payment confirmation in progress',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onAddMoney,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Add money'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletHubDestination {
  const _WalletHubDestination({
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.status,
  });

  final Key key;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? status;
  final VoidCallback onTap;
}

class _WalletHubTile extends StatelessWidget {
  const _WalletHubTile({required this.destination});

  final _WalletHubDestination destination;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: destination.key,
      color: kHighLightColor.withValues(alpha: .62),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: destination.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: kHighLightColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(destination.icon, color: kPrimaryColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.title,
                      style: const TextStyle(
                        color: kTertiaryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
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
              if (destination.status case final status?) ...[
                const SizedBox(width: 8),
                Text(
                  status,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: status == 'Ready'
                            ? kPrimaryColor
                            : Colors.orange.shade800,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: kTertiaryColor,
              ),
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

  Future<void> _openAddMoneyFromHub() async {
    await _openAddMoney();
    if (mounted) _openBalance();
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
              balanceLoading: campaignWallet.isLoading,
              showBalance: FeatureFlags.enableTransactionHistory ||
                  FeatureFlags.enableTopUp,
              showOnlinePayments: FeatureFlags.enableBankingDetails,
              showCosts: FeatureFlags.enablePricingInfo,
              onAddMoney: () => unawaited(_openAddMoneyFromHub()),
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
                if (!snapshot.hasData || campaignWallet.isLoading) {
                  return const _WalletBalancePanelLoading();
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
            const SizedBox(height: 30),
            if (_hasPendingIntent) ...[
              _PendingPaymentActivity(
                onCheckAgain: () => unawaited(_checkPending()),
              ),
              const SizedBox(height: 18),
            ],
            if (FeatureFlags.enableTransactionHistory) ...[
              Text(
                'Activity',
                key: const ValueKey('wallet-balance-activity-heading'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: kTertiaryColor,
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
