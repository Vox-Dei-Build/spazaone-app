import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/tabs/sales_balance_tab.dart';
import 'package:pasella/services/payment_setup_service.dart';

MerchantPaymentOverview overview({
  String status = 'not_started',
  String bankStatus = 'not_started',
  String bankName = '',
  String maskedAccount = '',
  String accountName = '',
  bool ready = false,
}) =>
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
      profile: SettlementProfileSummary(
        status: status,
        bankVerificationStatus: bankStatus,
        bankName: bankName,
        resolvedAccountName: accountName,
        maskedAccount: maskedAccount,
      ),
      settlements: const [],
    );

Future<void> pumpSection(
  WidgetTester tester,
  MerchantPaymentOverview data, {
  VoidCallback? onSetup,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MoneyPayoutsSection(overview: data, onSetup: onSetup),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('not-configured payout state offers plain bank setup', (
    tester,
  ) async {
    var tapped = false;
    await pumpSection(tester, overview(), onSetup: () => tapped = true);
    expect(
      find.text(
        'Add your bank account so customers can pay online and you can receive your money.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Set up bank account'));
    expect(tapped, isTrue);
  });

  testWidgets('pending payout state shows masked bank data only', (
    tester,
  ) async {
    await pumpSection(
      tester,
      overview(
        status: 'pending_review',
        bankStatus: 'pending_review',
        bankName: 'Example Bank',
        maskedAccount: '•••• 1234',
        accountName: 'Sensitive Account Holder',
      ),
    );
    expect(find.text('We’re checking your bank details'), findsOneWidget);
    expect(find.text('Example Bank · •••• 1234'), findsOneWidget);
    expect(find.text('Sensitive Account Holder'), findsNothing);
  });

  testWidgets('approved payout state remains compact at large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.8),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MoneyPayoutsSection(
              overview: overview(
                status: 'enabled',
                bankStatus: 'verified',
                bankName: 'Example Bank',
                maskedAccount: '•••• 1234',
                ready: true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Ready for online sales'), findsOneWidget);
    expect(find.text('No payouts yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('payout loading and error states are buyer-safe', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MoneyPayoutsSection(overview: null, loading: true),
              MoneyPayoutsSection(overview: null, hasError: true),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
  });
}
