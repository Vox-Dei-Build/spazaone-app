import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_onboarding_intro.dart';

void main() {
  testWidgets('merchant onboarding intro focuses the activation path', (
    tester,
  ) async {
    var openedCustomers = false;
    var openedProducts = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantOnboardingIntro(
            onOpenCustomers: () => openedCustomers = true,
            onOpenProducts: () => openedProducts = true,
          ),
        ),
      ),
    );

    expect(find.text('Set up Pasella clearly'), findsOneWidget);
    expect(find.text('Start with one customer'), findsOneWidget);
    expect(
      find.textContaining('record Pay Later credit'),
      findsOneWidget,
    );

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Link a product to credit'), findsOneWidget);
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();

    expect(openedProducts, isTrue);
    expect(openedCustomers, isFalse);
  });

  testWidgets('merchant onboarding intro opens customer capture', (
    tester,
  ) async {
    var openedCustomers = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantOnboardingIntro(
            onOpenCustomers: () => openedCustomers = true,
            onOpenProducts: () {},
          ),
        ),
      ),
    );

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Add Customer'));
    await tester.pumpAndSettle();

    expect(openedCustomers, isTrue);
  });
}
