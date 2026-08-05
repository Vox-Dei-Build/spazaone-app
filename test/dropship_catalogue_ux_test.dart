import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/stock/dropship/supplier_catalog_page.dart';
import 'package:pasella/pages/stock/product_card/product_card.dart';

void main() {
  testWidgets('markup stays visibly editable under the app input theme',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var latest = '';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          inputDecorationTheme: const InputDecorationTheme(
            enabledBorder: UnderlineInputBorder(),
          ),
        ),
        home: Scaffold(
          body: DropshipMarkupField(
            controller: controller,
            onChanged: (value) => latest = value,
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(
      find.byKey(const Key('dropship-markup-field')),
    );
    expect(field.decoration?.enabledBorder, isA<OutlineInputBorder>());
    expect(field.decoration?.focusedBorder, isA<OutlineInputBorder>());
    expect(field.decoration?.filled, isTrue);
    expect(field.decoration?.prefixText, 'R ');
    expect(field.decoration?.hintText, '0.00');
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('dropship-markup-field')),
      '123,45',
    );
    expect(latest, '123,45');
    expect(dropshipMarkupMinor(latest), 12345);
  });

  testWidgets('dropship product uses the standard Promote affordance',
      (tester) async {
    final promotedProducts = <LinkedProductRef>[];
    final product = Product(
      id: 'dropship-product',
      name: 'Summer bag',
      cost: 120,
      sellingPrice: 180,
      whatsappListed: true,
      isDropshipListing: true,
      fulfilmentMode: 'seller_manual_cj_order',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              height: 360,
              child: ProductCard(
                product: product,
                docID: product.id!,
                promotionLauncher: (_, promotedProduct) async {
                  promotedProducts.add(promotedProduct);
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Promote'), findsOneWidget);
    expect(find.text('Share'), findsNothing);

    await tester.tap(find.text('Promote'));
    await tester.pump();

    expect(promotedProducts, hasLength(1));
    expect(promotedProducts.single.id, 'dropship-product');
    expect(promotedProducts.single.name, 'Summer bag');
    expect(promotedProducts.single.sellingPrice, 180);
    expect(promotedProducts.single.whatsappListed, isTrue);

    await tester.tap(find.text('Summer Bag'));
    await tester.pumpAndSettle();

    expect(find.text('Promote on WhatsApp'), findsOneWidget);
    expect(find.text('Share Order on WhatsApp'), findsNothing);

    await tester.tap(find.text('Promote on WhatsApp'));
    await tester.pump();

    expect(promotedProducts, hasLength(2));
    expect(promotedProducts.last.id, 'dropship-product');
  });
}
