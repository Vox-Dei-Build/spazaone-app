import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_card/product_card.dart';
import 'package:pasella/pages/stock/search/widgets/search_product_list.dart';

void main() {
  testWidgets('product cards are keyed by stable Firestore document ID', (
    tester,
  ) async {
    final first = Product(id: 'product-a', name: 'First');
    final second = Product(id: 'product-b', name: 'Second');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchProductList(products: [first, second]),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('product-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('product-b')),
      findsOneWidget,
    );

    final firstCard = tester.widget<ProductCard>(
      find.byKey(const ValueKey<String>('product-a')),
    );
    final secondCard = tester.widget<ProductCard>(
      find.byKey(const ValueKey<String>('product-b')),
    );

    expect(firstCard.docID, 'product-a');
    expect(firstCard.product, same(first));
    expect(secondCard.docID, 'product-b');
    expect(secondCard.product, same(second));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchProductList(products: [second, first]),
        ),
      ),
    );

    final reorderedFirstCard = tester.widget<ProductCard>(
      find.byKey(const ValueKey<String>('product-a')),
    );
    final reorderedSecondCard = tester.widget<ProductCard>(
      find.byKey(const ValueKey<String>('product-b')),
    );

    expect(reorderedFirstCard.docID, 'product-a');
    expect(reorderedFirstCard.product, same(first));
    expect(reorderedSecondCard.docID, 'product-b');
    expect(reorderedSecondCard.product, same(second));
  });
}
