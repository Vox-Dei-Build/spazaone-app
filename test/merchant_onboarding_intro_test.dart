import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_onboarding_intro.dart';

void main() {
  testWidgets('merchant onboarding intro explains WhatsApp Store setup', (
    tester,
  ) async {
    var openedProducts = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantOnboardingIntro(
            onOpenProducts: () => openedProducts = true,
          ),
        ),
      ),
    );

    expect(find.text('Set up Pasella clearly'), findsOneWidget);
    expect(find.text('WhatsApp Store setup'), findsOneWidget);
    expect(
      find.textContaining('customer-facing ordering surface'),
      findsOneWidget,
    );

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Billing and Wallet'), findsOneWidget);
    await tester.tap(find.text('Start with Products'));
    await tester.pumpAndSettle();

    expect(openedProducts, isTrue);
  });
}
