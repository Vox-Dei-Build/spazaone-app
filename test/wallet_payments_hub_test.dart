import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/services/payment_setup_service.dart';

MerchantPaymentOverview _overview({bool ready = false}) =>
    MerchantPaymentOverview(
      paymentsV2: MerchantPaymentsV2(
        schemaVersion: 1,
        campaignCredits: MerchantPaymentCapability.unavailable,
        ownedOrders: MerchantPaymentCapability(
          ready: ready,
          reason: ready ? 'ready' : 'payment_setup_required',
          channels: ready ? const ['eft'] : const [],
        ),
        accountPayments: MerchantPaymentCapability.unavailable,
        supplierOrders: MerchantPaymentCapability.unavailable,
      ),
      profile: const SettlementProfileSummary(
        status: 'not_started',
        bankVerificationStatus: 'not_started',
        bankName: '',
        resolvedAccountName: '',
        maskedAccount: '',
      ),
      settlements: const [],
    );

void main() {
  for (final width in <double>[320, 360]) {
    testWidgets(
      'Wallet & payments hub stays focused at ${width.toInt()}dp',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var balanceTaps = 0;
        var addMoneyTaps = 0;
        var onlineTaps = 0;
        var costsTaps = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: WalletHubMenu(
                  campaignBalance: 65,
                  sharedCampaignCredits: true,
                  hasPendingPayment: false,
                  overview: _overview(),
                  overviewLoading: false,
                  overviewHasError: false,
                  showBalance: true,
                  showOnlinePayments: true,
                  showCosts: true,
                  onAddMoney: () => addMoneyTaps++,
                  onBalance: () => balanceTaps++,
                  onOnlinePayments: () => onlineTaps++,
                  onCosts: () => costsTaps++,
                ),
              ),
            ),
          ),
        );

        expect(find.text('SpazaOne balance'), findsOneWidget);
        expect(find.text('Online payments'), findsOneWidget);
        expect(find.text('Costs & limits'), findsOneWidget);
        expect(find.text('Online sales payouts'), findsNothing);
        expect(find.text('Legacy Balance'), findsNothing);
        expect(find.byType(Divider), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Add money'));
        await tester.tap(find.text('Balance activity'));
        await tester.ensureVisible(find.text('Online payments'));
        await tester.tap(find.text('Online payments'));
        await tester.ensureVisible(find.text('Costs & limits'));
        await tester.tap(find.text('Costs & limits'));
        expect(addMoneyTaps, 1);
        expect((balanceTaps, onlineTaps, costsTaps), (1, 1, 1));
      },
    );
  }

  testWidgets('hub exposes pending confirmation without adding another panel',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WalletHubMenu(
            campaignBalance: 10,
            sharedCampaignCredits: false,
            hasPendingPayment: true,
            overview: _overview(ready: true),
            overviewLoading: false,
            overviewHasError: false,
            showBalance: true,
            showOnlinePayments: true,
            showCosts: true,
            onAddMoney: () {},
            onBalance: () {},
            onOnlinePayments: () {},
            onCosts: () {},
          ),
        ),
      ),
    );

    expect(find.text('Payment confirmation in progress'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
