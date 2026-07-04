import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_onboarding_intro.dart';

void main() {
  testWidgets('merchant onboarding intro leads with customer capture', (
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

    expect(find.text('Set up your shop'), findsOneWidget);
    expect(find.text('Start with one customer'), findsOneWidget);
    expect(
      find.textContaining('record Pay Later transactions'),
      findsOneWidget,
    );

    // Slide two — product — is the terminal slide. Two slides means
    // one Next tap to reach it.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Then add your first product'), findsOneWidget);

    // Terminal CTA is a single primary — routes to customers, keeping
    // the customer-first ordering the sheet just taught.
    await tester.tap(find.text('Start with a customer'));
    await tester.pumpAndSettle();

    expect(openedCustomers, isTrue);
  });

  testWidgets('Later dismisses the sheet without opening either surface', (
    tester,
  ) async {
    var openedCustomers = false;
    var openedProducts = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: ElevatedButton(
                  onPressed:
                      () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder:
                            (_) => MerchantOnboardingIntro(
                              onOpenCustomers: () => openedCustomers = true,
                              onOpenProducts: () => openedProducts = true,
                            ),
                      ),
                  child: const Text('open'),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Set up your shop'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.text('Set up your shop'), findsNothing);
    expect(openedCustomers, isFalse);
    expect(openedProducts, isFalse);
  });

  testWidgets('terminal CTA returns an action when shown as a bottom sheet', (
    tester,
  ) async {
    MerchantOnboardingIntroAction? action;
    var openedCustomers = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    action = await showModalBottomSheet<
                      MerchantOnboardingIntroAction
                    >(
                      context: context,
                      isScrollControlled: true,
                      builder:
                          (_) => MerchantOnboardingIntro(
                            onOpenCustomers: () => openedCustomers = true,
                            onOpenProducts: () {},
                          ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start with a customer'));
    await tester.pumpAndSettle();

    expect(action, MerchantOnboardingIntroAction.openCustomers);
    expect(
      openedCustomers,
      isFalse,
      reason: 'Dashboard should route after the sheet completes.',
    );
  });

  testWidgets('intro copy uses transaction wording, never credit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantOnboardingIntro(
            onOpenCustomers: () {},
            onOpenProducts: () {},
          ),
        ),
      ),
    );

    // Walk both slides.
    final texts = <String>[];
    void collect() {
      for (final w in tester.widgetList<Text>(find.byType(Text))) {
        final s = w.data;
        if (s != null) texts.add(s);
      }
    }

    collect();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    collect();

    final joined = texts.join('\n').toLowerCase();
    expect(
      joined.contains('credit'),
      isFalse,
      reason:
          'Onboarding intro must say "transaction" — "credit" is reserved '
          'for wallet top-up copy.',
    );
    expect(joined.contains('pay later transactions'), isTrue);
  });
}
