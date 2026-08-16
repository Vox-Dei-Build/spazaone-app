import 'package:flutter/material.dart';
import 'package:pasella/pages/sales/widgets/combined_online_orders.dart';
import 'package:pasella/pages/settings/setup/merchant_setup_page.dart';
import 'package:pasella/pages/settings/order_options/order_options_page.dart';
import 'package:pasella/pages/settings/share/share.dart';
import 'package:pasella/services/payment_setup_service.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/utils/feature_flags.dart';

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

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  void _loadOverview() {
    _overview = widget.overviewLoader(StoreSession.instance.storeId);
  }

  void _refreshOverview() => setState(_loadOverview);

  void _openSetup() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MerchantSetupPage()),
    );
  }

  void _openShopLink() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SharePage(source: 'online_orders_empty'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MerchantPaymentOverview>(
      future: _overview,
      builder: (context, snapshot) {
        var setupRequired = false;
        if (snapshot.hasData) {
          final payments = snapshot.data!.paymentsV2;
          final owned = effectiveCommerceCapability(
            clientEnabled: FeatureFlags.enableOwnedOrderPayments,
            server: payments.ownedOrders,
          );
          final supplier = effectiveCommerceCapability(
            clientEnabled: FeatureFlags.enableSupplierOrderPayments,
            server: payments.supplierOrders,
          );
          setupRequired = !owned.ready && !supplier.ready;
        }

        return Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: TextButton.icon(
                  key: const ValueKey('online-orders-order-options'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OrderOptionsPage(),
                    ),
                  ),
                  icon: const Icon(Icons.tune_outlined, size: 18),
                  label: const Text('Order options'),
                ),
              ),
            ),
            Expanded(
              child: CombinedOnlineOrders(
                selectedDay: widget.selectedDay,
                startDate: widget.startDate,
                endDate: widget.endDate,
                onDaySelect: widget.onDaySelect,
                onRangeSelect: widget.onRangeSelect,
                onClearDates: widget.onClearDates,
                setupRequired: setupRequired,
                canShareShop: snapshot.hasData && !setupRequired,
                readinessUnavailable: snapshot.hasError,
                onRetryReadiness: _refreshOverview,
                onSetup: _openSetup,
                onShareShop: _openShopLink,
              ),
            ),
          ],
        );
      },
    );
  }
}
