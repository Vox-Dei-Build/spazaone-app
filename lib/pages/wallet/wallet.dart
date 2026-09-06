import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
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
import 'package:pasella/shared/widgets/spaza_shimmer.dart';

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

/// Intersects server-advertised Campaign Credit channels with the payment
/// methods this app build knows how to render. An unavailable capability or
/// an empty/unknown server list always fails closed.
@visibleForTesting
List<String> supportedCampaignTopupChannels(
  MerchantPaymentCapability capability,
) {
  if (!capability.ready) return const <String>[];
  final advertised = capability.channels.map((value) => value.trim()).toSet();
  return List<String>.unmodifiable(
    CampaignTopupChannel.values
        .map((channel) => channel.wireName)
        .where(advertised.contains),
  );
}

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
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: SpazaSpace.sm),
              Text(
                'Use this for WhatsApp messages and promotions.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: kTertiaryColor,
                      height: 1.35,
                    ),
              ),
              if (sharedCampaignCredits) ...[
                const SizedBox(height: SpazaSpace.xs),
                Text(
                  'Shared across your shops',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: kSecondaryAccent,
                      ),
                ),
              ],
              if (onCampaignTap != null) ...[
                const SizedBox(height: SpazaSpace.lg),
                FilledButton(
                  key: const ValueKey('billing-add-money'),
                  onPressed: onCampaignTap,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SpazaRadius.control),
                    ),
                  ),
                  child: const Text('Add money'),
                ),
              ],
            ],
          ),
        ),
        if (salesBalance > 0) ...[
          const SizedBox(height: SpazaSpace.lg),
          Padding(
            key: const ValueKey('billing-balance-legacy'),
            padding: const EdgeInsets.only(top: SpazaSpace.sm),
            child: _SecondaryBalanceRow(
              label: 'Legacy Balance',
              detail: storeName,
              amount: salesBalance,
              icon: SpazaIcons.activity,
            ),
          ),
        ],
        if (cashAdvanceBalance case final amount?) ...[
          const SizedBox(height: SpazaSpace.lg),
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
    final theme = Theme.of(context);
    final description = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: SpazaColors.muted, size: 22),
        const SizedBox(width: SpazaSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              if (detail != null) ...[
                const SizedBox(height: SpazaSpace.xs),
                Text(detail!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ],
    );
    final value = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        CurrencyUtil.format(amount),
        style: theme.textTheme.titleMedium,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 19) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              description,
              const SizedBox(height: SpazaSpace.sm),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: value,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: description),
            const SizedBox(width: SpazaSpace.lg),
            Flexible(child: value),
          ],
        );
      },
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
    return switch (overview!.verification.stage) {
      'approved' => 'Ready',
      'submitted' || 'pending_review' || 'submitting' => 'In review',
      'ready_to_verify' || 'changes_required' || 'rejected' => 'Action needed',
      'blocked' => 'Paused',
      _ => overview!.enabled ? 'Ready' : 'Not set up',
    };
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
          icon: SpazaIcons.sales,
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
          const SizedBox(height: SpazaSpace.lg),
        ],
        for (var index = 0; index < destinations.length; index++) ...[
          _WalletHubTile(destination: destinations[index]),
          if (index < destinations.length - 1)
            const SizedBox(height: SpazaSpace.xs),
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
    Widget block(
            {required double height, double radius = SpazaRadius.control}) =>
        Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return SpazaShimmer(
      key: const ValueKey('wallet-loading-shimmer'),
      semanticsLabel: 'Loading wallet',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showBalance) ...[
            block(height: 190, radius: SpazaRadius.surface),
            const SizedBox(height: SpazaSpace.lg),
          ],
          for (var index = 0; index < destinationCount; index++) ...[
            block(height: 68),
            if (index < destinationCount - 1)
              const SizedBox(height: SpazaSpace.xs),
          ],
        ],
      ),
    );
  }
}

class _WalletBalancePanelLoading extends StatelessWidget {
  const _WalletBalancePanelLoading();

  @override
  Widget build(BuildContext context) => SpazaShimmer(
        key: const ValueKey('wallet-balance-loading-shimmer'),
        semanticsLabel: 'Loading wallet balance',
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
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('wallet-balance-hero'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: SpazaColors.border),
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
      ),
      padding: const EdgeInsets.all(SpazaSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('SpazaOne balance', style: theme.textTheme.bodyMedium),
          const SizedBox(height: SpazaSpace.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              CurrencyUtil.format(balance),
              style: theme.textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: SpazaSpace.sm),
          Text(
            'For WhatsApp messages and promotions.',
            style: theme.textTheme.bodySmall,
          ),
          if (sharedAcrossShops) ...[
            const SizedBox(height: SpazaSpace.xs),
            Text(
              'Shared across your shops',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: SpazaColors.muted),
            ),
          ],
          if (hasPendingPayment) ...[
            const SizedBox(height: SpazaSpace.md),
            Row(
              children: [
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: SpazaSpace.sm),
                Expanded(
                  child: Text(
                    'Payment confirmation in progress',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: SpazaSpace.lg),
          FilledButton(
            onPressed: onAddMoney,
            child: const Text('Add money'),
          ),
        ],
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
    final theme = Theme.of(context);
    return Material(
      key: destination.key,
      color: Colors.transparent,
      child: InkWell(
        onTap: destination.onTap,
        borderRadius: BorderRadius.circular(SpazaRadius.control),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SpazaSpace.xs,
            vertical: SpazaSpace.lg,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: SpazaColors.border)),
          ),
          child: Row(
            children: [
              Icon(destination.icon, color: SpazaColors.muted, size: 22),
              const SizedBox(width: SpazaSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(destination.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: SpazaSpace.xs),
                    Text(
                      destination.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: SpazaColors.muted,
                      ),
                    ),
                    if (destination.status case final status?) ...[
                      const SizedBox(height: SpazaSpace.xs),
                      Text(
                        status,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: switch (status) {
                            'Ready' => SpazaColors.action,
                            'Action needed' => SpazaColors.error,
                            _ => SpazaColors.muted,
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: SpazaSpace.sm),
              const Icon(SpazaIcons.next, color: SpazaColors.muted, size: 20),
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
  bool _openingTopup = false;
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

  Future<void> _openOnlinePayments() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WalletOnlinePaymentsPage(),
      ),
    );
    if (!mounted) return;
    setState(() {
      _overviewFuture = PaymentSetupService.overview(
        StoreSession.instance.storeId,
      );
    });
  }

  Future<void> _openAddMoney() async {
    if (_openingTopup) return;
    if (!FeatureFlags.enableTopUpPaystack) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adding money is temporarily unavailable.'),
        ),
      );
      return;
    }

    setState(() => _openingTopup = true);
    try {
      final merchantId = StoreSession.instance.storeId;
      final overview = await PaymentSetupService.overview(merchantId);
      if (!mounted) return;
      final channels = supportedCampaignTopupChannels(
        overview.paymentsV2.campaignCredits,
      );
      setState(() => _overviewFuture = Future.value(overview));
      if (channels.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adding money is temporarily unavailable.'),
          ),
        );
        return;
      }

      await Navigator.of(context).push<CampaignTopupStatus>(
        MaterialPageRoute(
          builder: (_) => PaystackFormScreen(
            allowedChannels: channels,
          ),
        ),
      );
      if (!mounted) return;
      setState(() {
        _pendingIntentId = CampaignTopupPendingStore.read(merchantId);
        _overviewFuture = PaymentSetupService.overview(merchantId);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not check available payment methods. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingTopup = false);
    }
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
          padding: const EdgeInsets.fromLTRB(
              SpazaSpace.lg, SpazaSpace.lg, SpazaSpace.lg, SpazaSpace.xl),
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
              onOnlinePayments: () => unawaited(_openOnlinePayments()),
              onCosts: () => _openInfo(InfoView.info),
            ),
          ),
        ),
      ),
    );
  }

  Widget _repaymentCard(WalletState walletState) {
    // Compute the same repayment breakdown once for this notice.
    return FutureBuilder<WalletBreakdown>(
      future: WalletUtils.computeBreakdown(walletState),
      builder: (context, snapshot) => WalletRepaymentNotice(
        totalOwed: snapshot.data?.totalOwed ?? '...',
        onView: () => _showRepaymentBottomSheet(context, walletState),
      ),
    );
  }

  void _showRepaymentBottomSheet(
    BuildContext context,
    WalletState walletState,
  ) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        // One breakdown for the whole sheet, as before.
        final breakdown = WalletUtils.computeBreakdown(walletState);
        return FutureBuilder<WalletBreakdown>(
          future: breakdown,
          builder: (context, snapshot) => WalletRepaymentDetailsSheet(
            breakdown: snapshot.data ?? WalletBreakdown.loading,
            onClose: () => Navigator.of(context).pop(),
            onViewReport: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FullRepaymentReportPage(
                    walletState: walletState,
                  ),
                ),
              );
            },
          ),
        );
      },
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
              WalletPendingPaymentActivity(
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

class _WalletOnlinePaymentsPageState extends State<WalletOnlinePaymentsPage>
    with WidgetsBindingObserver {
  late Future<MerchantPaymentOverview> _overview;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(_refresh);
    }
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
            padding: const EdgeInsets.fromLTRB(
                SpazaSpace.lg, SpazaSpace.lg, SpazaSpace.lg, SpazaSpace.xl),
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

/// Pending-payment presentation; checking still runs through the page callback.
class WalletPendingPaymentActivity extends StatelessWidget {
  const WalletPendingPaymentActivity({super.key, required this.onCheckAgain});

  final VoidCallback onCheckAgain;

  @override
  Widget build(BuildContext context) => _WalletStatusNotice(
        title: 'We are still checking your payment',
        detail: Text(
          'Your SpazaOne balance will update only after confirmation.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        leading: const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        actionLabel: 'Check',
        onAction: onCheckAgain,
      );
}

class WalletRepaymentNotice extends StatelessWidget {
  const WalletRepaymentNotice({
    super.key,
    required this.totalOwed,
    required this.onView,
  });

  final String totalOwed;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: SpazaSpace.sm),
        child: _WalletStatusNotice(
          title: 'Repayment Due',
          detail: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child:
                Text(totalOwed, style: Theme.of(context).textTheme.titleMedium),
          ),
          leading: const Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: SpazaColors.error,
          ),
          actionLabel: 'View',
          onAction: onView,
        ),
      );
}

class _WalletStatusNotice extends StatelessWidget {
  const _WalletStatusNotice({
    required this.title,
    required this.detail,
    required this.leading,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final Widget detail;
  final Widget leading;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final description = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: leading),
        const SizedBox(width: SpazaSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: SpazaSpace.xs),
              detail,
            ],
          ),
        ),
      ],
    );
    final action = TextButton(onPressed: onAction, child: Text(actionLabel));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SpazaSpace.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(14) > 19) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  description,
                  const SizedBox(height: SpazaSpace.xs),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: description),
                const SizedBox(width: SpazaSpace.sm),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Data-only repayment details used by the live bottom sheet.
class WalletRepaymentDetailsSheet extends StatelessWidget {
  const WalletRepaymentDetailsSheet({
    super.key,
    required this.breakdown,
    required this.onViewReport,
    required this.onClose,
  });

  final WalletBreakdown breakdown;
  final VoidCallback onViewReport;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SpazaSpace.lg, 0, SpazaSpace.sm, SpazaSpace.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Repayment Details',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close repayment details',
                    onPressed: onClose,
                    icon: const Icon(SpazaIcons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('wallet-repayment-details-scroll'),
                padding: const EdgeInsets.fromLTRB(
                    SpazaSpace.lg, 0, SpazaSpace.lg, SpazaSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RepaymentDetailRow('Fee Charged', breakdown.advanceFee),
                    _RepaymentDetailRow('Bank Fee', breakdown.bankFee),
                    _RepaymentDetailRow(
                        'Penalty Applied', breakdown.penaltyFee),
                    _RepaymentDetailRow('Amount Due', breakdown.totalOwed),
                    _RepaymentDetailRow('Due Date', breakdown.dueDate),
                    _RepaymentDetailRow('Suspended', breakdown.suspended),
                    const SizedBox(height: SpazaSpace.lg),
                    FilledButton(
                      onPressed: onViewReport,
                      child: const Text('View Full Report'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _RepaymentDetailRow extends StatelessWidget {
  const _RepaymentDetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelWidget = Text(label, style: theme.textTheme.bodyMedium);
    final valueWidget = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(value, style: theme.textTheme.titleSmall),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: SpazaSpace.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SpazaColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(14) > 19) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelWidget,
                const SizedBox(height: SpazaSpace.xs),
                valueWidget,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: labelWidget),
              const SizedBox(width: SpazaSpace.lg),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: valueWidget,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
