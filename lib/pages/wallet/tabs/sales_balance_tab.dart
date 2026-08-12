import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/tabs/cash_advance_tab.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/services/payment_setup_service.dart';
import 'package:pasella/services/store_session.dart';

class SalesBalanceTab extends StatefulWidget {
  const SalesBalanceTab({super.key});

  @override
  State<SalesBalanceTab> createState() => _SalesBalanceTabState();
}

enum SalesView { sales, cashAdvance }

class _SalesBalanceTabState extends State<SalesBalanceTab> {
  final WalletViewModel walletVM = WalletViewModel();
  SalesView _selected = SalesView.sales;

  @override
  void dispose() {
    walletVM.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_selected == SalesView.cashAdvance) {
      content = const CashAdvanceTab();
    } else {
      content = const _SettlementOverview();
    }

    return Column(
      children: [
        if (FeatureFlags.enableCashAdvance)
          Theme(
            data: Theme.of(context).copyWith(
              segmentedButtonTheme: SegmentedButtonThemeData(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? Colors.green
                        : Colors.white,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? Colors.white
                        : Colors.black87,
                  ),
                ),
              ),
            ),
            child: Padding(
              padding:
                  EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier),
              child: SegmentedButton<SalesView>(
                segments: const [
                  ButtonSegment(
                    value: SalesView.sales,
                    label: Text('Sales'),
                    icon: Icon(Icons.monetization_on),
                  ),
                  ButtonSegment(
                    value: SalesView.cashAdvance,
                    label: Text('Cash Advance'),
                    icon: Icon(Icons.account_balance),
                  ),
                ],
                selected: <SalesView>{_selected},
                onSelectionChanged: (selection) {
                  setState(() => _selected = selection.first);
                },
              ),
            ),
          ),
        Expanded(child: content),
      ],
    );
  }
}

class _SettlementOverview extends StatelessWidget {
  const _SettlementOverview();

  String _money(int minor) => 'R ${(minor / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MerchantPaymentOverview>(
      future: PaymentSetupService.overview(StoreSession.instance.storeId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Settlement information is temporarily unavailable. Your manual sales records are unchanged.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final overview = snapshot.data!;
        final profile = overview.profile;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Online settlement destination',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      profile.maskedAccount.isEmpty
                          ? 'No verified settlement account'
                          : '${profile.bankName} · ${profile.maskedAccount}',
                    ),
                    if (profile.resolvedAccountName.isNotEmpty)
                      Text(profile.resolvedAccountName),
                    const SizedBox(height: 8),
                    Text(
                      overview.enabled
                          ? 'Enabled for verified online collections'
                          : profile.bankVerificationStatus == 'pending_review'
                              ? 'Pending Spaza One review'
                              : 'Online collections are not enabled',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Recent settlements',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (overview.settlements.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No verified online settlements yet. Cash, manual transfer and Pay Later remain in their existing records.',
                  ),
                ),
              )
            else
              for (final settlement in overview.settlements)
                Card(
                  child: ListTile(
                    title: Text(
                      'Order ${settlement.orderId.substring(0, settlement.orderId.length < 8 ? settlement.orderId.length : 8)}',
                    ),
                    subtitle: Text(
                      'Spaza One ${_money(settlement.platformFeeMinor)} · Paystack ${_money(settlement.providerFeeMinor)}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _money(settlement.merchantNetProceedsMinor),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(settlement.status.replaceAll('_', ' ')),
                      ],
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
