import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_setup_card.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_setup_state.dart';

/// Minimal harness. Uses `fromState` so no Firestore listener is opened
/// and the Hive-backed shop-link dismissal falls back to `false` (see
/// the try/catch inside the card).
Future<void> _pumpCardWith(
  WidgetTester tester,
  MerchantSetupState state, {
  MerchantSetupActions? actions,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MerchantSetupCard.fromState(
            userId: 'user-1',
            actions: actions ?? _noopActions(),
            state: state,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

MerchantSetupActions _noopActions({
  VoidCallback? onAddCustomer,
  VoidCallback? onAddProduct,
  VoidCallback? onChooseWhatsAppProducts,
  VoidCallback? onOpenOrderingLink,
  VoidCallback? onOpenBanking,
  VoidCallback? onCreateTemplate,
}) {
  return MerchantSetupActions(
    onAddCustomer: onAddCustomer ?? () {},
    onAddProduct: onAddProduct ?? () {},
    onChooseWhatsAppProducts: onChooseWhatsAppProducts ?? () {},
    onOpenOrderingLink: onOpenOrderingLink ?? () {},
    onOpenBanking: onOpenBanking ?? () {},
    onCreateTemplate: onCreateTemplate ?? () {},
  );
}

const _empty = MerchantSetupState(
  hasCustomers: false,
  hasProducts: false,
  hasListedProduct: false,
  hasOrderingLink: false,
  hasApprovedTemplate: false,
  hasBank: false,
  shopName: 'Acme Shop',
  orderingUrl: '',
  orderingCode: '',
  fallbackText: '',
  loading: false,
);

const _customerOnly = MerchantSetupState(
  hasCustomers: true,
  hasProducts: false,
  hasListedProduct: false,
  hasOrderingLink: false,
  hasApprovedTemplate: false,
  hasBank: false,
  shopName: 'Acme Shop',
  orderingUrl: '',
  orderingCode: '',
  fallbackText: '',
  loading: false,
);

const _customerAndProduct = MerchantSetupState(
  hasCustomers: true,
  hasProducts: true,
  hasListedProduct: false,
  hasOrderingLink: false,
  hasApprovedTemplate: false,
  hasBank: false,
  shopName: 'Acme Shop',
  orderingUrl: '',
  orderingCode: '',
  fallbackText: '',
  loading: false,
);

/// Everything but automatic promotion setup. Used to verify that when the
/// step becomes the next action, the panel routes into Marketing.
const _allButTemplate = MerchantSetupState(
  hasCustomers: true,
  hasProducts: true,
  hasListedProduct: true,
  hasOrderingLink: true,
  hasApprovedTemplate: false,
  hasBank: true,
  shopName: 'Acme Shop',
  orderingUrl: '',
  orderingCode: 'AC1',
  fallbackText: '',
  loading: false,
);

const _allDone = MerchantSetupState(
  hasCustomers: true,
  hasProducts: true,
  hasListedProduct: true,
  hasOrderingLink: true,
  hasApprovedTemplate: true,
  hasBank: true,
  shopName: 'Acme Shop',
  orderingUrl: 'https://wa.me/1234567890?text=shop%20AC1',
  orderingCode: 'AC1',
  fallbackText: '',
  loading: false,
);

void main() {
  group('MerchantSetupCard header + copy', () {
    testWidgets(
      'renders "Set up your shop" and progress out of six',
      (tester) async {
        await _pumpCardWith(tester, _customerOnly);

        expect(find.text('Set up your shop'), findsOneWidget);
        expect(find.text('1 of 6 done'), findsOneWidget);
      },
    );

    testWidgets(
      'never says "Customer setup" (the renamed scope)',
      (tester) async {
        await _pumpCardWith(tester, _empty);

        final matches = tester.widgetList<Text>(find.byType(Text)).where(
              (w) => (w.data ?? '').toLowerCase() == 'customer setup',
            );
        expect(matches, isEmpty);
      },
    );

    testWidgets('renders "Up next" only when a step is actionable',
        (tester) async {
      await _pumpCardWith(tester, _empty);
      expect(find.text('Up next'), findsOneWidget);

      await _pumpCardWith(tester, _allDone);
      expect(find.text('Up next'), findsNothing);
    });
  });

  group('Next-action targeting', () {
    testWidgets(
      'no customer → next action is customer with Add customer CTA',
      (tester) async {
        await _pumpCardWith(tester, _empty);

        expect(find.text('Up next'), findsOneWidget);
        expect(find.text('Save your first customer'), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, 'Add customer'),
            findsOneWidget);
      },
    );

    testWidgets(
      'customer done, no product → next action is product with Add product',
      (tester) async {
        await _pumpCardWith(tester, _customerOnly);

        expect(find.text('Add your first product'), findsOneWidget);
        expect(
            find.widgetWithText(ElevatedButton, 'Add product'), findsOneWidget);
      },
    );

    testWidgets(
      'all but promotion setup done → next action opens Marketing',
      (tester) async {
        await _pumpCardWith(tester, _allButTemplate);

        expect(find.text('Prepare WhatsApp promotions'), findsOneWidget);
        expect(
          find.widgetWithText(ElevatedButton, 'Open Marketing'),
          findsOneWidget,
        );
      },
    );
  });

  group('Product gating', () {
    testWidgets(
      'no products → WA products, ordering link, template rows show '
      '"Available after a product exists"',
      (tester) async {
        await _pumpCardWith(tester, _customerOnly);

        expect(
          find.textContaining('Available after a product exists'),
          findsNWidgets(3),
        );
      },
    );

    testWidgets(
      'no products → gated rows do not expose a tap chevron',
      (tester) async {
        // With only customer done, the WhatsApp / ordering-link /
        // template rows are all gated (no chevron). The product-add
        // and payout rows are not product-gated, so they do show
        // chevrons — that's 2 total, and lets us prove the gated
        // three are NOT interactive. The current Add product step is
        // promoted into the Up next panel, so only payout remains as a row.
        await _pumpCardWith(tester, _customerOnly);

        final chevrons = tester.widgetList(find.byIcon(Icons.chevron_right));
        expect(
          chevrons.length,
          1,
          reason: 'Only the payout row should remain tappable when the '
              'current Add product action is promoted above the checklist.',
        );
      },
    );

    testWidgets(
      'products exist → gated rows now expose a chevron',
      (tester) async {
        await _pumpCardWith(tester, _customerAndProduct);

        // With customer+product done, WhatsApp/link/payout/template
        // rows are all tappable. Only "First customer" and
        // "First product" are done, so they show check circles, not
        // chevrons. The current WhatsApp-products action is promoted above
        // the checklist, leaving 3 chevrons in the rows.
        final chevrons = find.byIcon(Icons.chevron_right);
        expect(chevrons, findsNWidgets(3));
      },
    );
  });

  group('Complete state', () {
    testWidgets(
      'all six done → swaps to shop link panel with Share on WhatsApp',
      (tester) async {
        await _pumpCardWith(tester, _allDone);

        expect(find.text('Your shop link is ready'), findsOneWidget);
        expect(find.text('Share on WhatsApp'), findsOneWidget);
        // The setup panel is gone.
        expect(find.text('Set up your shop'), findsNothing);
        expect(find.text('Up next'), findsNothing);
      },
    );

    testWidgets(
      'shop link panel renders the ordering URL',
      (tester) async {
        await _pumpCardWith(tester, _allDone);
        expect(
          find.text('https://wa.me/1234567890?text=shop%20AC1'),
          findsOneWidget,
        );
      },
    );
  });

  group('Loading state', () {
    testWidgets(
      'renders skeleton and none of the real header copy while loading',
      (tester) async {
        await _pumpCardWith(tester, const MerchantSetupState.loading());

        expect(find.text('Set up your shop'), findsNothing);
        expect(find.text('Up next'), findsNothing);
        expect(find.textContaining('of 6 done'), findsNothing);
        // The skeleton wraps in a Shimmer; presence of at least one
        // Card is enough to know we're rendering the loading chrome.
        expect(find.byType(Card), findsOneWidget);
      },
    );
  });

  group('CTAs wire through', () {
    testWidgets('Add customer taps the passed handler', (tester) async {
      var tapped = false;
      await _pumpCardWith(
        tester,
        _empty,
        actions: _noopActions(onAddCustomer: () => tapped = true),
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add customer'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets(
      'promotion setup step opens Marketing through the retained callback',
      (tester) async {
        var templateTapped = false;
        var promoTapped = false;

        await _pumpCardWith(
          tester,
          _allButTemplate,
          actions: _noopActions(
            onCreateTemplate: () => templateTapped = true,
            // If the card ever wires template routing through a
            // marketing handler by mistake, this would fire.
            onChooseWhatsAppProducts: () => promoTapped = true,
          ),
        );

        await tester.tap(find.widgetWithText(ElevatedButton, 'Open Marketing'));
        await tester.pump();

        expect(templateTapped, isTrue);
        expect(promoTapped, isFalse);
      },
    );

    testWidgets(
      'tapping a later, actionable row fires its handler '
      '(e.g. banking from a mid-setup state)',
      (tester) async {
        var bankTapped = false;

        await _pumpCardWith(
          tester,
          _customerAndProduct,
          actions: _noopActions(onOpenBanking: () => bankTapped = true),
        );

        // Banking is not the next action — WhatsApp products is —
        // but the banking row is still tappable via its chevron
        // InkWell. Tap on the row title text.
        await tester.tap(find.text('Add payout details'));
        await tester.pump();

        expect(bankTapped, isTrue);
      },
    );
  });
}
