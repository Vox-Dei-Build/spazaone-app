import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/auth/widgets/otp_code_dialog.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required OtpVerifyCallback onVerify,
    OtpResendCallback? onResend,
    bool enableAutosubmit = false,
    bool enableResend = false,
    Duration resendDelay = const Duration(seconds: 30),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    showOtpCodeDialog(
                      context,
                      maskedNumber: '+27***567',
                      onVerify: onVerify,
                      onResend: onResend,
                      enableAutosubmit: enableAutosubmit,
                      enableResend: enableResend,
                      resendDelay: resendDelay,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('auto-submits a complete 6-digit code once', (tester) async {
    var verifyCalls = 0;
    await pumpDialog(
      tester,
      enableAutosubmit: true,
      onVerify: (code) async {
        verifyCalls += 1;
        expect(code, '123456');
        return true;
      },
    );

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pumpAndSettle();

    expect(verifyCalls, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('keeps the dialog open when verification fails', (tester) async {
    await pumpDialog(tester, onVerify: (_) async => false);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text("That code didn't work. Check the SMS and try again."),
      findsOneWidget,
    );
  });

  testWidgets('resend is gated by the countdown', (tester) async {
    var resendCalls = 0;
    await pumpDialog(
      tester,
      enableResend: true,
      resendDelay: const Duration(seconds: 1),
      onVerify: (_) async => false,
      onResend: () async {
        resendCalls += 1;
      },
    );

    await tester.tap(find.text('Resend'));
    await tester.pump();
    expect(resendCalls, 0);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Resend'));
    await tester.pump();

    expect(resendCalls, 1);
  });
}
