import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/tabs/banking_details_tab.dart';

void main() {
  testWidgets(
    'bank verification remains usable above a small-device keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });

      BankAccountVerificationDetails? result;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.3),
              viewInsets: EdgeInsets.only(bottom: 300),
            ),
            child: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () async {
                    result = await showDialog<BankAccountVerificationDetails>(
                      context: context,
                      builder: (_) => const BankAccountVerificationDialog(),
                    );
                  },
                  child: const Text('Open verification'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open verification'));
      await tester.pumpAndSettle();

      expect(find.text('Verify bank account'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Validate'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.enterText(
        find.byKey(const ValueKey('bank-verification-document-number')),
        '9001010000000',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('submit-bank-account-verification')),
      );
      await tester.tap(
        find.byKey(const ValueKey('submit-bank-account-verification')),
      );
      await tester.pumpAndSettle();

      expect(result?.accountType, 'personal');
      expect(result?.documentType, 'identityNumber');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('business verification fits at 320px and closes cleanly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BankAccountVerificationDialog()),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('bank-verification-account-type')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Business').last);
    await tester.pumpAndSettle();

    expect(find.text('Business registration number'), findsOneWidget);
    expect(find.text('South African ID'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
