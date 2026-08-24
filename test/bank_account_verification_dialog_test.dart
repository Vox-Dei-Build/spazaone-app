import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/tabs/banking_details_tab.dart';
import 'package:pasella/services/payment_setup_service.dart';

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
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(
                  const ValueKey('bank-verification-document-number'),
                ),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        isTrue,
      );
      final visibilityControl = find.byKey(
        const ValueKey('bank-verification-document-visibility'),
      );
      await tester.ensureVisible(visibilityControl);
      await tester.pumpAndSettle();
      await tester.tap(visibilityControl);
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(
                  const ValueKey('bank-verification-document-number'),
                ),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        isFalse,
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

  testWidgets('submitted verification is persistent and not shown as an error',
      (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MerchantVerificationJourneyCard(
            journey: MerchantVerificationJourney(
              stage: 'submitted',
              reason: 'authorization_review_pending',
              bankName: 'Example Bank',
              maskedAccount: '•••• 1234',
            ),
            isSubmitting: false,
          ),
        ),
      ),
    );

    expect(find.text('Verification request sent'), findsOneWidget);
    expect(find.textContaining('progress is saved'), findsOneWidget);
    expect(find.text('Example Bank · •••• 1234'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('authorized merchant can continue at large text on a small phone',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: MerchantVerificationJourneyCard(
                journey: const MerchantVerificationJourney(
                  stage: 'ready_to_verify',
                  reason: 'authorization_ready',
                ),
                isSubmitting: false,
                onVerify: () async => continued = true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Continue verification'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue verification'));
    await tester.pump();
    expect(continued, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('consumed attempts explain provider failure and prevent retry',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MerchantVerificationJourneyCard(
            journey: MerchantVerificationJourney(
              stage: 'blocked',
              reason: 'approved_attempts_consumed',
            ),
            isSubmitting: false,
          ),
        ),
      ),
    );

    expect(find.text('Approved bank checks used'), findsOneWidget);
    expect(find.textContaining('could not validate'), findsOneWidget);
    expect(find.textContaining('saved banking details are unchanged'),
        findsOneWidget);
    expect(find.textContaining('Do not retry'), findsOneWidget);
    expect(find.text('Continue verification'), findsNothing);
  });
}
