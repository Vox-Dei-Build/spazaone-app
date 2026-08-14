import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_report/product_report.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';

class _StockViewModelStub implements StockViewModel {
  _StockViewModelStub(this.products);

  @override
  List<Product> products;

  @override
  List<Product> checkLowStock() => products
      .where((product) => product.quantity != null && product.quantity! <= 5)
      .toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('stock report stays quiet when low-stock products are present',
      (tester) async {
    final viewModel = _StockViewModelStub([
      Product(
        name: 'Sold out item',
        cost: 10,
        sellingPrice: 20,
        quantity: 0,
      ),
      Product(
        name: 'Low item',
        cost: 10,
        sellingPrice: 20,
        quantity: 2,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProductReportsTab(viewModel: viewModel)),
      ),
    );
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Possible profit'), findsOneWidget);
    expect(find.text('Stock cost'), findsOneWidget);
    expect(find.text('Selling value'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.text('Low stock'), findsOneWidget);
  });
}
