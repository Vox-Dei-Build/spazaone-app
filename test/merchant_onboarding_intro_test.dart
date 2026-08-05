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

    expect(find.text('Welcome to Spaza One'), findsOneWidget);
    expect(find.text('Add a customer'), findsOneWidget);
    expect(find.text('Add a product'), findsOneWidget);
    expect(find.text('Next'), findsNothing);

    await tester.tap(find.text('Add my first customer'));
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
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => MerchantOnboardingIntro(
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

    expect(find.text('Welcome to Spaza One'), findsOneWidget);

    await tester.tap(find.text('I’ll do this later'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Spaza One'), findsNothing);
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
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                action =
                    await showModalBottomSheet<MerchantOnboardingIntroAction>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => MerchantOnboardingIntro(
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
    await tester.tap(find.text('Add my first customer'));
    await tester.pumpAndSettle();

    expect(action, MerchantOnboardingIntroAction.openCustomers);
    expect(
      openedCustomers,
      isFalse,
      reason: 'Dashboard should route after the sheet completes.',
    );
  });

  testWidgets('intro stays concise and never uses credit wording', (
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

    final joined = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join('\n')
        .toLowerCase();
    expect(
      joined.contains('credit'),
      isFalse,
      reason: 'Credit is reserved for wallet top-up copy.',
    );
    expect(joined.contains('shop setup'), isTrue);
  });

  testWidgets('small phone keeps the primary action reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    MerchantOnboardingIntroAction? action;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                action =
                    await showModalBottomSheet<MerchantOnboardingIntroAction>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => MerchantOnboardingIntro(
                    onOpenCustomers: () {},
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
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Add my first customer'));
    await tester.tap(find.text('Add my first customer'));
    await tester.pumpAndSettle();

    expect(action, MerchantOnboardingIntroAction.openCustomers);
    expect(tester.takeException(), isNull);
  });
}
