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
  List<MerchantSettlement> settlements = const [],
  int outstandingMinor = 0,
  int testOnlyMinor = 0,
  String? verificationStage,
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
      verification: MerchantVerificationJourney(
        stage: verificationStage ??
            (bankStatus == 'pending_review'
                ? 'pending_review'
                : ready
                    ? 'approved'
                    : 'ready_to_submit'),
        reason: 'test',
        bankName: bankName,
        maskedAccount: maskedAccount,
      ),
      settlements: settlements,
      outstandingSettlementMinor: outstandingMinor,
      testOnlySettlementMinor: testOnlyMinor,
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
        'Request verification for your bank account so online-sale payouts go to the right place.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Start verification'));
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
    expect(find.text('Bank details submitted'), findsOneWidget);
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
    expect(
      find.byKey(const ValueKey('online-payments-loading-shimmer')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
  });

  testWidgets('test payouts never claim money is on the way', (tester) async {
    await pumpSection(
      tester,
      overview(
        testOnlyMinor: 1250,
        settlements: const [
          MerchantSettlement(
            orderId: 'order-test',
            status: 'processing',
            grossAmountMinor: 1500,
            platformFeeMinor: 250,
            providerFeeMinor: 0,
            merchantNetProceedsMinor: 1250,
            testOnly: true,
          ),
        ],
      ),
    );
    expect(find.text('Test only — not sent to bank'), findsOneWidget);
    expect(
        find.text('Test payments are not sent to your bank.'), findsOneWidget);
    expect(find.text('On the way'), findsNothing);
  });

  test('live payout status uses exact date or T+2 estimate', () {
    expect(
      merchantSettlementStatusLabel(
        const MerchantSettlement(
          orderId: 'paid',
          status: 'completed',
          grossAmountMinor: 100,
          platformFeeMinor: 0,
          providerFeeMinor: 0,
          merchantNetProceedsMinor: 100,
          providerSettlementAtMs: 1787004000000,
        ),
      ),
      startsWith('Paid · '),
    );
    expect(
      merchantSettlementStatusLabel(
        const MerchantSettlement(
          orderId: 'pending',
          status: 'processing',
          grossAmountMinor: 100,
          platformFeeMinor: 0,
          providerFeeMinor: 0,
          merchantNetProceedsMinor: 100,
          expectedSettlementAtMs: 1787004000000,
        ),
      ),
      startsWith('Expected by '),
    );
  });
}
