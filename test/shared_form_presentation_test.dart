import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/forms/date_row.dart';
import 'package:pasella/shared/widgets/forms/transaction_form_scaffold.dart';

void main() {
  Widget app(Widget child, {double textScale = 1}) => MaterialApp(
        theme: kCustomThemeData,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: child,
      );

  Future<void> size(WidgetTester tester, Size value,
      {double keyboard = 0}) async {
    await tester.binding.setSurfaceSize(value);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = value;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.view.resetViewInsets();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('field labels, long validation errors and suffix stay accessible',
      (tester) async {
    await size(tester, const Size(320, 568));
    final semantics = tester.ensureSemantics();
    final formKey = GlobalKey<FormState>();
    var suffixTaps = 0;
    const error =
        'Enter the full mobile number, including the local area code.';
    await tester.pumpWidget(app(
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: formKey,
            child: CustomTextField(
              label: 'Mobile number for account updates',
              hintText: '082 123 4567',
              prefixIcon: Icons.phone_outlined,
              suffixOptions: IconButton(
                tooltip: 'Number help',
                onPressed: () => suffixTaps++,
                icon: const Icon(Icons.help_outline),
              ),
              validator: (_) => error,
            ),
          ),
        ),
      ),
      textScale: 2,
    ));
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pumpAndSettle();
    expect(find.text(error), findsOneWidget);
    expect(tester.getSize(find.byTooltip('Number help')).height,
        greaterThanOrEqualTo(48));
    await tester.tap(find.byTooltip('Number help'));
    expect(suffixTaps, 1);
    expect(
      tester.getSemantics(find.byType(TextField)).getSemanticsData().label,
      contains('Mobile number for account updates'),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
      'custom buttons wrap scaled labels and expose real enabled actions',
      (tester) async {
    await size(tester, const Size(320, 568));
    final semantics = tester.ensureSemantics();
    var taps = 0;
    Widget button(bool disabled) => app(
          Scaffold(
            body: CustomButton(
              title: 'Continue to account verification',
              width: 220,
              height: 35,
              icon: Icons.arrow_forward,
              onTap: () => taps++,
              isDisabled: disabled,
            ),
          ),
          textScale: 2,
        );
    await tester.pumpWidget(button(false));
    expect(tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48));
    expect(
        tester
            .getSemantics(find.byType(CustomButton))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue);
    await tester.tap(find.byType(FilledButton));
    expect(taps, 1);
    await tester.pumpWidget(button(true));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(
        tester
            .getSemantics(find.byType(CustomButton))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
      'primary form action sits above the keyboard and validates before saving',
      (tester) async {
    await size(tester, const Size(390, 844), keyboard: 300);
    var submitted = 0;
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(app(TransactionFormScaffold(
      title: 'Record sale',
      formKey: key,
      primaryActionLabel: 'Save sale',
      onPrimaryAction: () => submitted++,
      body: Column(
        children: [
          for (var index = 0; index < 6; index++)
            CustomTextField(
              label: 'Amount $index',
              hintText: 'Enter amount',
              prefixIcon: Icons.payments_outlined,
              validator: index == 5 ? (_) => 'An amount is required' : null,
            ),
        ],
      ),
    )));
    final action = find.byKey(const ValueKey('transaction-primary-action'));
    expect(tester.getBottomRight(action).dy, lessThanOrEqualTo(544));
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(submitted, 0);
    expect(find.text('An amount is required').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'short landscape form scrolls to its action with keyboard and large text',
      (tester) async {
    await size(tester, const Size(640, 320), keyboard: 170);
    var submitted = 0;
    await tester.pumpWidget(app(
      TransactionFormScaffold(
        title: 'Record sale',
        formKey: GlobalKey<FormState>(),
        primaryActionLabel: 'Confirm transaction',
        onPrimaryAction: () => submitted++,
        totalLabel: const Text('Total: R 1 234,56'),
        body: Column(
          children: [
            for (var index = 0; index < 3; index++)
              CustomTextField(
                label: 'Amount $index',
                hintText: 'Enter amount',
                prefixIcon: Icons.payments_outlined,
              ),
          ],
        ),
      ),
      textScale: 2,
    ));
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
        isNull);
    expect(tester.takeException(), isNull);
    final action = find.byKey(const ValueKey('transaction-primary-action'));
    await tester.scrollUntilVisible(action, 60,
        scrollable: find.byWidgetPredicate((widget) =>
            widget is Scrollable &&
            widget.axisDirection == AxisDirection.down));
    await tester.pumpAndSettle();
    await tester.tap(action);
    expect(submitted, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading form action keeps its label and disables submission',
      (tester) async {
    await size(tester, const Size(320, 568));
    var submitted = 0;
    await tester.pumpWidget(app(
      TransactionFormScaffold(
        title: 'Record sale',
        formKey: GlobalKey<FormState>(),
        primaryActionLabel: 'Confirm transaction and notify customer',
        onPrimaryAction: () => submitted++,
        isLoading: true,
        body: const Text('Form details'),
      ),
      textScale: 2,
    ));
    expect(
        find.text('Confirm transaction and notify customer'), findsOneWidget);
    final action = tester.widget<FilledButton>(
        find.byKey(const ValueKey('transaction-primary-action')));
    expect(action.onPressed, isNull);
    expect(submitted, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('form app bar respects unsaved changes before leaving',
      (tester) async {
    await tester.pumpWidget(app(Builder(builder: (context) {
      return Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TransactionFormScaffold(
              title: 'Edit sale',
              formKey: GlobalKey<FormState>(),
              primaryActionLabel: 'Save changes',
              onPrimaryAction: () {},
              isDirty: true,
              body: const Text('Unsaved form'),
            ),
          )),
          child: const Text('Open form'),
        ),
      );
    })));
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved form'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Open form'), findsOneWidget);
    expect(find.text('Unsaved form'), findsNothing);
  });

  testWidgets(
      'date picker fits large text, clamps initial date and retains time',
      (tester) async {
    await size(tester, const Size(320, 568));
    final original = DateTime.utc(2026, 9, 4, 14, 32, 18, 25, 12);
    DateTime? chosen;
    await tester.pumpWidget(app(
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: DateRow(
            label: 'Expected date of the customer repayment',
            value: original,
            firstDate: DateTime(2026, 9, 5),
            lastDate: DateTime(2026, 10),
            onPick: (date) => chosen = date,
          ),
        ),
      ),
      textScale: 2,
    ));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sep 4, 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(chosen, DateTime.utc(2026, 9, 5, 14, 32, 18, 25, 12));
    expect(chosen!.isUtc, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'app bar without a back action does not infer one from navigation',
      (tester) async {
    await tester.pumpWidget(app(Builder(builder: (context) {
      return Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const Scaffold(
              appBar: CustomAppBar(title: 'Account setup', onBack: false),
            ),
          )),
          child: const Text('Continue'),
        ),
      );
    })));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text('Account setup'), findsOneWidget);
  });
}
