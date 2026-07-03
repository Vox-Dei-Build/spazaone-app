import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/stock/product_group_page/widgets/product_list.dart';

/// Widget tests for `ProductListEmptyState`, extracted from
/// `ProductList` so the empty-state's copy and CTA wiring can be
/// asserted without a Firestore stream or view model.
///
/// The primary regression these guard against is the pre-branch state
/// where the empty catalogue told merchants to "Start with your first
/// customer" and offered a `Add your first customer` button — that
/// misdirection was flagged in the review as breaking the product
/// empty-state contract ("Product empty state must not tell merchants
/// to start with customers"). We assert here that:
///
///  - the top-level empty catalogue says "Add your first product" and
///    talks about products,
///  - it never uses the words "customer" or "customers",
///  - the CTA fires the passed handler,
///  - the tutorial link is only rendered when a handler is supplied,
///  - the group-drilldown mode (`showOnboarding == false`) falls back
///    to the compact placeholder.
void main() {
  Future<void> pumpEmpty(
    WidgetTester tester, {
    required bool showOnboarding,
    VoidCallback? onAddProduct,
    VoidCallback? onWatchTutorial,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductListEmptyState(
            userId: '', // empty so the coach mark bypasses Hive
            showOnboarding: showOnboarding,
            onAddProduct: onAddProduct,
            onWatchTutorial: onWatchTutorial,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('top-level empty catalogue', () {
    testWidgets('renders product-first hero copy', (tester) async {
      await pumpEmpty(
        tester,
        showOnboarding: true,
        onAddProduct: () {},
      );

      expect(find.text('Add your first product'), findsWidgets);
      expect(
        find.textContaining('Start with the item you sell most often'),
        findsOneWidget,
      );
    });

    testWidgets(
      'never redirects a fresh merchant back to customers',
      (tester) async {
        await pumpEmpty(
          tester,
          showOnboarding: true,
          onAddProduct: () {},
        );

        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => (w.data ?? '').toLowerCase())
            .join('\n');
        expect(texts.contains('customer'), isFalse);
        expect(texts.contains('customers'), isFalse);
      },
    );

    testWidgets('CTA fires the passed handler', (tester) async {
      var tapped = false;
      await pumpEmpty(
        tester,
        showOnboarding: true,
        onAddProduct: () => tapped = true,
      );

      // The button is `ElevatedButton.icon`, which returns a private
      // subclass — `find.byType(ElevatedButton)` uses exact-type
      // match and misses it. Tap the label text; the tap propagates
      // up through the button's gesture recognizer.
      await tester.tap(find.text('Add your first product').last);
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('walkthrough link only appears when handler is set',
        (tester) async {
      await pumpEmpty(
        tester,
        showOnboarding: true,
        onAddProduct: () {},
      );
      expect(find.text('Watch a 2-min walkthrough'), findsNothing);

      await pumpEmpty(
        tester,
        showOnboarding: true,
        onAddProduct: () {},
        onWatchTutorial: () {},
      );
      expect(find.text('Watch a 2-min walkthrough'), findsOneWidget);
    });
  });

  group('group-drilldown empty group', () {
    testWidgets(
      'falls back to "No products in this group" without hero copy or CTA',
      (tester) async {
        await pumpEmpty(tester, showOnboarding: false);

        expect(find.text('No products in this group'), findsOneWidget);
        expect(find.text('Add your first product'), findsNothing);
        expect(find.byType(ElevatedButton), findsNothing);
      },
    );
  });
}
