import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/widgets/add_banking_details.dart';
import 'package:pasella/services/payment_setup_service.dart';

const _supportedBanks = <SupportedSettlementBank>[
  SupportedSettlementBank(
    name: 'Example Bank',
    branchCode: '632005',
    supportedAccountTypes: ['personal', 'business'],
  ),
  SupportedSettlementBank(
    name: 'Second Bank',
    branchCode: '470010',
    supportedAccountTypes: ['personal'],
  ),
];

class _FakeBankingDetailsFormController
    implements BankingDetailsFormController {
  @override
  final TextEditingController bankName = TextEditingController();

  @override
  final TextEditingController accountHolderName = TextEditingController();

  @override
  final TextEditingController accountNumber = TextEditingController();

  @override
  final TextEditingController accountType = TextEditingController();

  @override
  final TextEditingController branchCode = TextEditingController();

  @override
  final TextEditingController reference = TextEditingController();

  @override
  final ValueNotifier<bool> isProcessing = ValueNotifier(false);

  var saveCount = 0;

  @override
  Future<void> saveBankingDetails() async => saveCount += 1;

  void dispose() {
    bankName.dispose();
    accountHolderName.dispose();
    accountNumber.dispose();
    accountType.dispose();
    branchCode.dispose();
    reference.dispose();
    isProcessing.dispose();
  }
}

void main() {
  testWidgets('supported bank choices drive branch code and account type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    final controller = _FakeBankingDetailsFormController();
    addTearDown(() {
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
          child: AddBankingDetailsPage.forTesting(
            formController: controller,
            loadSupportedBanks: () async => _supportedBanks,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Where should payouts go?'), findsOneWidget);
    expect(find.text('Choose a supported bank'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('supported-settlement-bank')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example Bank').last);
    await tester.pumpAndSettle();

    expect(controller.bankName.text, 'Example Bank');
    expect(controller.branchCode.text, '632005');
    expect(find.text('Universal branch code'), findsOneWidget);
    expect(find.text('632005'), findsOneWidget);

    final accountTypeField = find.byKey(
      const ValueKey('settlement-bank-account-type'),
    );
    await tester.ensureVisible(accountTypeField);
    await tester.pumpAndSettle();
    await tester.tap(accountTypeField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal').last);
    await tester.pumpAndSettle();

    expect(controller.accountType.text, 'Personal');
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-banking-details')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bank load failure is calm, retryable, and keeps the form usable',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    final controller = _FakeBankingDetailsFormController();
    var attempts = 0;
    addTearDown(() {
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<List<SupportedSettlementBank>> loadBanks() async {
      attempts += 1;
      if (attempts == 1) throw StateError('provider unavailable');
      return _supportedBanks;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: AddBankingDetailsPage.forTesting(
          formController: controller,
          loadSupportedBanks: loadBanks,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Supported banks are unavailable right now. Your saved details have not changed.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('supported-bank-load-error')),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Try again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(
      find.byKey(const ValueKey('supported-bank-load-error')),
      findsNothing,
    );
    await tester.fling(find.byType(ListView), const Offset(0, 1000), 1000);
    await tester.pumpAndSettle();
    final bankField = find.byKey(
      const ValueKey('supported-settlement-bank'),
    );
    await tester.ensureVisible(bankField);
    await tester.pumpAndSettle();
    await tester.tap(bankField);
    await tester.pumpAndSettle();
    expect(find.text('Example Bank'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
