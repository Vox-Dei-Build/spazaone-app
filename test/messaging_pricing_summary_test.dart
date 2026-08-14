import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/tabs/pricing_tab.dart';

void main() {
  testWidgets('shows configured message prices without narrow-screen overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    final overflows = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) {
        overflows.add(details);
      } else {
        previousOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MessagingPricingSummary(
              smsCustomerRate: 1.74,
              smsPaymentRate: 1.74,
              whatsappUtilityRate: 0.20,
              whatsappPromotionRate: 1.00,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WhatsApp customer updates'), findsOneWidget);
    expect(find.text('SMS payment confirmations'), findsOneWidget);
    expect(find.text('R0,20'), findsOneWidget);
    expect(find.text('R1,00'), findsOneWidget);
    expect(find.text('R1,74'), findsNWidgets(2));
    expect(find.text('R0,00'), findsNothing);
    expect(overflows, isEmpty);
  });
}
