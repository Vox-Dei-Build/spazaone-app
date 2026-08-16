import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_card/product_card.dart';
import 'package:pasella/pages/stock/search/widgets/search_product_list.dart';

void main() {
  final products = List.generate(
    4,
    (index) => Product(
      id: 'product-$index',
      name: 'A deliberately long product name $index',
      cost: 12,
      sellingPrice: 18,
      quantity: 4,
    ),
  );

  testWidgets('product results switch to safe rows above the keyboard',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              viewInsets: EdgeInsets.only(bottom: 300),
            ),
            child: SearchProductList(products: products),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('compact-product-search-results')),
      findsOneWidget,
    );
    expect(find.byType(ProductCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product results remain compact in phone landscape',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(size: Size(720, 320)),
            child: SearchProductList(products: products),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('compact-product-search-results')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
