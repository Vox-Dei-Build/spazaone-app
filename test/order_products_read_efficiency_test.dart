import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/ecommerce/orders/widgets/products_section_enhanced.dart';

void main() {
  testWidgets('order product documents load once across unrelated rebuilds', (
    tester,
  ) async {
    var loads = 0;
    final loadedIds = <List<String>>[];

    Future<Map<String, Map<String, dynamic>>> loader(
      String storeId,
      List<String> productIds,
    ) async {
      loads++;
      loadedIds.add(List.of(productIds));
      return {
        for (final id in productIds)
          id: {'name': 'Product $id', 'sellingPrice': 10},
      };
    }

    Widget app(List<Map<String, dynamic>> items) => MaterialApp(
          home: Scaffold(
            body: ProductsSectionEnhanced(
              items: items,
              fallbackUserId: 'store-a',
              productsLoader: loader,
            ),
          ),
        );

    await tester.pumpWidget(app([
      {'productId': 'b', 'quantity': 1},
      {'productId': 'a', 'quantity': 2},
      {'productId': 'a', 'quantity': 1},
    ]));
    await tester.pumpAndSettle();

    expect(loads, 1);
    expect(loadedIds.single, ['a', 'b']);

    await tester.pumpWidget(app([
      {'productId': 'a', 'quantity': 3},
      {'productId': 'b', 'quantity': 1},
    ]));
    await tester.pumpAndSettle();

    expect(loads, 1);

    await tester.pumpWidget(app([
      {'productId': 'c', 'quantity': 1},
    ]));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(loadedIds.last, ['c']);
  });
}
