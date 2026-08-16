import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/settings/share/share.dart';

Widget _panel({
  required bool hasListedProduct,
  VoidCallback? onAddProduct,
  VoidCallback? onShare,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: OrderingLinkPanel(
          shopName: 'Test Shop',
          code: 'ABC123',
          orderingUrl: 'https://wa.me/27600000000?text=shop%20ABC123',
          pasellaWhatsappNumber: '+27600000000',
          fallbackText: 'Send SHOP ABC123 on WhatsApp.',
          regenerating: false,
          hasListedProduct: hasListedProduct,
          onAddProduct: onAddProduct ?? () {},
          onCopyCode: () {},
          onCopyLink: () {},
          onShare: onShare ?? () {},
          onWhatsApp: onShare ?? () {},
          onRegenerate: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('empty catalogue keeps the link but warns before sharing',
      (tester) async {
    var addProductTaps = 0;
    var shareTaps = 0;
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _panel(
        hasListedProduct: false,
        onAddProduct: () => addProductTaps++,
        onShare: () => shareTaps++,
      ),
    );

    expect(find.text('Add a product before sharing'), findsOneWidget);
    expect(
      find.text(
        'Your shop link is ready, but customers will not see products yet.',
      ),
      findsOneWidget,
    );
    expect(find.text('Share anyway on WhatsApp'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);

    await tester.tap(find.text('Add product'));
    await tester.tap(find.text('Share anyway on WhatsApp'));
    expect((addProductTaps, shareTaps), (1, 1));
  });

  testWidgets('listed catalogue uses the normal sharing actions',
      (tester) async {
    await tester.pumpWidget(_panel(hasListedProduct: true));
    expect(find.text('Share on WhatsApp'), findsOneWidget);
    expect(find.text('Share another way'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ordering-link-empty-catalogue')),
      findsNothing,
    );
  });

  test('callable failures map to stable recovery messages', () {
    expect(
      orderingLinkErrorMessage('failed-precondition'),
      'Shop link setup is not ready yet. Please try again later.',
    );
    expect(
      orderingLinkErrorMessage('permission-denied'),
      contains('permission'),
    );
    expect(orderingLinkErrorMessage('unknown'), contains('try again'));
  });
}
