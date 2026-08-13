import 'package:flutter/material.dart';
import 'package:pasella/pages/sales/widgets/date_filter_bar.dart';
import 'package:pasella/pages/sales/widgets/online_sales_list.dart';
import 'package:pasella/pages/stock/dropship/commerce_orders_page.dart';
import 'package:pasella/pages/wallet/tabs/info_center_tab.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/services/payment_setup_service.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/utils/feature_flags.dart';

enum OnlineOrderReport { owned, supplier }

class EffectiveCommerceCapability {
  const EffectiveCommerceCapability({
    required this.ready,
    required this.reason,
    required this.channels,
  });

  final bool ready;
  final String reason;
  final List<String> channels;
}

EffectiveCommerceCapability effectiveCommerceCapability({
  required bool clientEnabled,
  required MerchantPaymentCapability server,
}) {
  if (!clientEnabled) {
    return const EffectiveCommerceCapability(
      ready: false,
      reason: 'client_disabled',
      channels: <String>[],
    );
  }
  if (!server.ready) {
    return EffectiveCommerceCapability(
      ready: false,
      reason: server.reason,
      channels: const <String>[],
    );
  }
  return EffectiveCommerceCapability(
    ready: true,
    reason: server.reason,
    channels: server.channels,
  );
}

typedef MerchantOverviewLoader = Future<MerchantPaymentOverview> Function(
  String merchantId,
);

class OnlineCommerceHub extends StatefulWidget {
  const OnlineCommerceHub({
    super.key,
    required this.selectedDay,
    required this.startDate,
    required this.endDate,
    required this.onDaySelect,
    required this.onRangeSelect,
    required this.onClearDates,
    this.overviewLoader = PaymentSetupService.overview,
  });

  final DateTime? selectedDay;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<DateTime> onDaySelect;
  final void Function(DateTime start, DateTime end) onRangeSelect;
  final VoidCallback onClearDates;
  final MerchantOverviewLoader overviewLoader;

  @override
  State<OnlineCommerceHub> createState() => _OnlineCommerceHubState();
}

class _OnlineCommerceHubState extends State<OnlineCommerceHub> {
  late Future<MerchantPaymentOverview> _overview;
  OnlineOrderReport _report = OnlineOrderReport.owned;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _overview = widget.overviewLoader(StoreSession.instance.storeId);
  }

  void _refresh() => setState(_load);

  void _openCredits() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const WalletPage(initialTab: WalletInitialTab.topUp),
      ),
    );
  }

  void _openPaymentSetup() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const WalletPage(
          initialTab: WalletInitialTab.account,
          initialAccountView: InfoView.banking,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MerchantPaymentOverview>(
      future: _overview,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _OverviewUnavailable(onRetry: _refresh);
        }
        final overview = snapshot.data!;
        final payments = overview.paymentsV2;
        final capabilities = <_CapabilityPresentation>[
          _CapabilityPresentation(
            title: 'Add to your SpazaOne balance',
            icon: Icons.campaign_outlined,
            state: effectiveCommerceCapability(
              clientEnabled: FeatureFlags.enableTopUpPaystack,
              server: payments.campaignCredits,
            ),
            requiresPaymentSetup: false,
            onAction: _openCredits,
          ),
          _CapabilityPresentation(
            title: 'Sell your products online',
            icon: Icons.inventory_2_outlined,
            state: effectiveCommerceCapability(
              clientEnabled: FeatureFlags.enableOwnedOrderPayments,
              server: payments.ownedOrders,
            ),
            requiresPaymentSetup: true,
            onAction: _openPaymentSetup,
          ),
          _CapabilityPresentation(
            title: 'Customer account payments',
            icon: Icons.account_balance_wallet_outlined,
            state: effectiveCommerceCapability(
              clientEnabled: FeatureFlags.enableAccountSettlementPayments,
              server: payments.accountPayments,
            ),
            requiresPaymentSetup: true,
            onAction: _openPaymentSetup,
          ),
          _CapabilityPresentation(
            title: 'Supplier-delivered products',
            icon: Icons.local_shipping_outlined,
            state: effectiveCommerceCapability(
              clientEnabled: FeatureFlags.enableSupplierOrderPayments,
              server: payments.supplierOrders,
            ),
            requiresPaymentSetup: true,
            onAction: _openPaymentSetup,
          ),
        ];

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Online commerce',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh readiness',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            SizedBox(
              height: 184,
              child: ListView.separated(
                key: const ValueKey('commerce-capability-list'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: capabilities.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, index) => SizedBox(
                  width: 250,
                  child: _CapabilityCard(capability: capabilities[index]),
                ),
              ),
            ),
            SegmentedButton<OnlineOrderReport>(
              segments: const [
                ButtonSegment(
                  value: OnlineOrderReport.owned,
                  label: Text('Owned orders'),
                  icon: Icon(Icons.inventory_2_outlined),
                ),
                ButtonSegment(
                  value: OnlineOrderReport.supplier,
                  label: Text('Supplier orders'),
                  icon: Icon(Icons.local_shipping_outlined),
                ),
              ],
              selected: {_report},
              onSelectionChanged: (selection) {
                setState(() => _report = selection.first);
              },
            ),
            if (_report == OnlineOrderReport.owned)
              DateFilterBar(
                selectedDay: widget.selectedDay,
                startDate: widget.startDate,
                endDate: widget.endDate,
                onDaySelect: widget.onDaySelect,
                onRangeSelect: widget.onRangeSelect,
                onClear: widget.onClearDates,
              ),
            const SizedBox(height: 4),
            Expanded(
              child: _report == OnlineOrderReport.owned
                  ? OnlineSalesList(
                      key: ValueKey<String>(
                        '${widget.selectedDay?.toIso8601String() ?? ''}|'
                        '${widget.startDate?.toIso8601String() ?? ''}|'
                        '${widget.endDate?.toIso8601String() ?? ''}',
                      ),
                      selectedDay: widget.selectedDay,
                      startDate: widget.startDate,
                      endDate: widget.endDate,
                    )
                  : const CommerceOrdersPage(),
            ),
          ],
        );
      },
    );
  }
}

class _CapabilityPresentation {
  const _CapabilityPresentation({
    required this.title,
    required this.icon,
    required this.state,
    required this.requiresPaymentSetup,
    required this.onAction,
  });

  final String title;
  final IconData icon;
  final EffectiveCommerceCapability state;
  final bool requiresPaymentSetup;
  final VoidCallback onAction;
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.capability});

  final _CapabilityPresentation capability;

  String _reason(String reason) {
    switch (reason) {
      case 'ready':
        return 'Ready for secure online payment';
      case 'merchant_not_enabled':
      case 'merchant_capability_disabled':
        return 'Set up online payments or wait for approval';
      case 'global_suspended':
        return 'Temporarily paused for safety';
      case 'client_disabled':
      case 'master_disabled':
      case 'capability_disabled':
      default:
        return 'Not available right now';
    }
  }

  String _channel(String value) {
    switch (value) {
      case 'card':
        return 'Card';
      case 'eft':
        return 'Instant EFT';
      case 'capitec_pay':
        return 'Capitec Pay';
      case 'qr':
        return 'Scan to Pay';
      default:
        return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = capability.state;
    final color = state.ready ? Colors.green.shade700 : Colors.grey.shade700;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(capability.icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    capability.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              state.ready ? 'Available' : 'Unavailable',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            Text(
              _reason(state.reason),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            if (state.ready && state.channels.isNotEmpty)
              Text(
                state.channels.map(_channel).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w600,
                    ),
              )
            else if (capability.requiresPaymentSetup && !state.ready)
              TextButton.icon(
                onPressed: capability.onAction,
                icon: const Icon(Icons.account_balance_outlined, size: 18),
                label: const Text('Set up online payments'),
              )
            else if (state.ready)
              TextButton(
                onPressed: capability.onAction,
                child: const Text('Add credits'),
              ),
          ],
        ),
      ),
    );
  }
}

class _OverviewUnavailable extends StatelessWidget {
  const _OverviewUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            const Text(
              'Online readiness is temporarily unavailable. New online payments remain off; existing records are unchanged.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
