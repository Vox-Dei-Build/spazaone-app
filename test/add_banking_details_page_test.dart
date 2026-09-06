import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/widgets/add_banking_details.dart';
import 'package:pasella/pages/wallet/tabs/banking_details_tab.dart';
import 'package:pasella/models/wallet/banking_detail_model.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/services/store_session.dart';
import '../tool/commerce_design_previews.dart';
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

class _FakeBankingDetailsFormController {
  final TextEditingController bankName = TextEditingController();

  final TextEditingController accountHolderName = TextEditingController();

  final TextEditingController accountNumber = TextEditingController();

  final TextEditingController accountType = TextEditingController();

  final TextEditingController branchCode = TextEditingController();

  final TextEditingController reference = TextEditingController();

  final ValueNotifier<bool> isProcessing = ValueNotifier(false);

  var saveCount = 0;

  var reloadCount = 0;
  bool failSave = false;
  bool canEdit = true;
  String activeStore = 'demo';

  BankingDetails get initialDetails => BankingDetails(
        bankName: bankName.text,
        accountHolderName: accountHolderName.text,
        accountNumber: accountNumber.text,
        accountType: accountType.text,
        branchCode: branchCode.text,
        reference: reference.text,
      );

  void setExisting() {
    bankName.text = 'Example Bank';
    accountHolderName.text = 'Neighbourhood Store';
    accountNumber.text = '1234567890';
    accountType.text = 'Business';
    branchCode.text = '632005';
    reference.text = 'Shop payouts';
  }

  Future<void> saveBankingDetails(BankingDetails details) async {
    saveCount++;
    if (failSave) throw StateError('offline');
    bankName.text = details.bankName;
    accountHolderName.text = details.accountHolderName;
    accountNumber.text = details.accountNumber;
    accountType.text = details.accountType;
    branchCode.text = details.branchCode;
    reference.text = details.reference;
  }

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

class _BankingFlow extends StatefulWidget {
  const _BankingFlow(this.controller);
  final _FakeBankingDetailsFormController controller;
  @override
  State<_BankingFlow> createState() => _BankingFlowState();
}

class _BankingFlowState extends State<_BankingFlow> {
  Future<void> _edit() async {
    final controller = widget.controller;
    final storeId = controller.activeStore;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => AddBankingDetailsPage(
        initialDetails: controller.initialDetails,
        isEditing: true,
        canEdit: () => controller.canEdit && controller.activeStore == storeId,
        onSave: controller.saveBankingDetails,
        loadSupportedBanks: () async => _supportedBanks,
      ),
    ));
    if (saved == true && mounted) {
      controller.reloadCount++;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: SingleChildScrollView(
        child: BankingDetailsPanel(
            details: widget.controller.initialDetails,
            canEdit: widget.controller.canEdit,
            onEdit: _edit),
      ));
}

Future<void> _openExisting(
    WidgetTester tester, _FakeBankingDetailsFormController controller,
    {double scale = 1}) async {
  await tester.pumpWidget(MaterialApp(
    theme: kCustomThemeData,
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: _BankingFlow(controller),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('edit-banking-details')));
  await tester.pumpAndSettle();
}

Future<void> _tapAction(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('failed details load cannot open an empty Add or Edit form',
      (tester) async {
    var edits = 0;
    var retries = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BankingDetailsPanel(
      details: null,
      detailsLoaded: false,
      canEdit: true,
      onEdit: () => edits++,
      onRetry: () => retries++,
    ))));
    expect(find.byKey(const ValueKey('add-banking-details')), findsNothing);
    expect(find.byKey(const ValueKey('edit-banking-details')), findsNothing);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
    expect(edits, 0);
  });

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
          child: AddBankingDetailsPage(
            initialDetails: controller.initialDetails,
            onSave: controller.saveBankingDetails,
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

    expect(controller.bankName.text, isEmpty);
    expect(controller.branchCode.text, isEmpty);
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

    expect(controller.accountType.text, isEmpty);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -1000));
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
        home: AddBankingDetailsPage(
          initialDetails: controller.initialDetails,
          onSave: controller.saveBankingDetails,
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
    await tester.fling(
        find.byType(SingleChildScrollView), const Offset(0, 1000), 1000);
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
  testWidgets('saved details open populated and save updates the summary once',
      (tester) async {
    final controller = _FakeBankingDetailsFormController()..setExisting();
    addTearDown(controller.dispose);
    await _openExisting(tester, controller);
    expect(find.text('Edit banking details'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('settlement-account-holder')))
            .controller!
            .text,
        'Neighbourhood Store');
    final number = find.byKey(const ValueKey('settlement-account-number'));
    await tester.ensureVisible(number);
    await tester.enterText(number, '9876543210');
    expect(controller.accountNumber.text, '1234567890');
    await _tapAction(tester, 'save-banking-details');
    expect(controller.saveCount, 1);
    expect(controller.reloadCount, 1);
    expect(find.text('9876543210'), findsOneWidget);
    expect(find.byType(AddBankingDetailsPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cancel discards edits and catalogue normalization without saving or reloading',
      (tester) async {
    final controller = _FakeBankingDetailsFormController()..setExisting();
    controller.bankName.text = 'EXAMPLE BANK';
    controller.branchCode.text = '123456';
    final original = controller.initialDetails.toJson();
    addTearDown(controller.dispose);
    await _openExisting(tester, controller);
    final holder = find.byKey(const ValueKey('settlement-account-holder'));
    await tester.ensureVisible(holder);
    await tester.enterText(holder, 'Unsaved name');
    await _tapAction(tester, 'cancel-banking-details');
    expect(controller.initialDetails.toJson(), original);
    expect(controller.saveCount, 0);
    expect(controller.reloadCount, 0);
    expect(find.text('Neighbourhood Store'), findsOneWidget);
  });

  testWidgets('system Back discards the draft without saving or reloading',
      (tester) async {
    final controller = _FakeBankingDetailsFormController()..setExisting();
    final original = controller.initialDetails.toJson();
    addTearDown(controller.dispose);
    await _openExisting(tester, controller);
    final holder = find.byKey(const ValueKey('settlement-account-holder'));
    await tester.ensureVisible(holder);
    await tester.enterText(holder, 'Unsaved name');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AddBankingDetailsPage), findsNothing);
    expect(controller.initialDetails.toJson(), original);
    expect(controller.saveCount, 0);
    expect(controller.reloadCount, 0);
  });

  testWidgets(
      'switching shops prevents saving an open editor to the previous shop',
      (tester) async {
    final controller = _FakeBankingDetailsFormController()..setExisting();
    addTearDown(controller.dispose);
    await _openExisting(tester, controller);
    controller.activeStore = 'another-shop';
    await _tapAction(tester, 'save-banking-details');
    expect(controller.saveCount, 0);
    expect(controller.reloadCount, 0);
    expect(find.byType(AddBankingDetailsPage), findsOneWidget);
    expect(find.textContaining('Only the active shop owner'), findsOneWidget);
  });

  testWidgets(
      'failed save retains the draft and saved account until retry succeeds',
      (tester) async {
    final controller = _FakeBankingDetailsFormController()
      ..setExisting()
      ..failSave = true;
    addTearDown(controller.dispose);
    await _openExisting(tester, controller);
    final holder = find.byKey(const ValueKey('settlement-account-holder'));
    await tester.ensureVisible(holder);
    await tester.enterText(holder, 'Updated Store');
    await _tapAction(tester, 'save-banking-details');
    expect(find.byType(AddBankingDetailsPage), findsOneWidget);
    expect(controller.accountHolderName.text, 'Neighbourhood Store');
    expect(controller.reloadCount, 0);
    controller.failSave = false;
    await _tapAction(tester, 'save-banking-details');
    expect(controller.accountHolderName.text, 'Updated Store');
    expect(controller.reloadCount, 1);
    expect(tester.takeException(), isNull);
  });

  for (final role in StoreRole.values) {
    testWidgets('${role.name} banking edit permission follows store membership',
        (tester) async {
      final membership =
          StoreMembership(storeId: 'demo', storeName: 'Demo', role: role);
      final controller = _FakeBankingDetailsFormController()
        ..setExisting()
        ..canEdit = membership.canManageOperators;
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(home: _BankingFlow(controller)));
      expect(find.byKey(const ValueKey('edit-banking-details')),
          role == StoreRole.operator ? findsNothing : findsOneWidget);
      if (role == StoreRole.operator) {
        expect(find.textContaining('Only the shop owner'), findsOneWidget);
      }
    });
  }

  testWidgets('revoked edit access prevents saving an open form',
      (tester) async {
    final controller = _FakeBankingDetailsFormController()..setExisting();
    addTearDown(controller.dispose);
    await _openExisting(tester, controller);
    controller.canEdit = false;
    await _tapAction(tester, 'save-banking-details');
    expect(controller.saveCount, 0);
    expect(controller.reloadCount, 0);
    expect(find.byType(AddBankingDetailsPage), findsOneWidget);
    expect(find.textContaining('Only the active shop owner'), findsOneWidget);
  });

  testWidgets('editing remains usable at 320 pixels and 2x text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _FakeBankingDetailsFormController()..setExisting();
    addTearDown(controller.dispose);
    await _openExisting(tester, controller, scale: 2);
    expect(tester.takeException(), isNull);
    final holder = find.byKey(const ValueKey('settlement-account-holder'));
    await tester.ensureVisible(holder);
    await tester.enterText(holder, 'New Shop');
    await _tapAction(tester, 'save-banking-details');
    expect(controller.saveCount, 1);
    expect(controller.accountHolderName.text, 'New Shop');
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery bank account supports local edit and save',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: kCustomThemeData,
        home: Builder(builder: commerceDesignPreviews()['Bank details']!)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-banking-details')));
    await tester.pumpAndSettle();
    final holder = find.byKey(const ValueKey('settlement-account-holder'));
    await tester.ensureVisible(holder);
    await tester.enterText(holder, 'Demo Shop');
    await _tapAction(tester, 'save-banking-details');
    expect(find.text('Demo Shop'), findsOneWidget);
    expect(find.byType(AddBankingDetailsPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
