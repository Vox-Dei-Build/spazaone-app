import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';

void main() {
  test('stock report state follows live product additions and edits', () async {
    final products = StreamController<List<Product>>();
    final viewModel = StockViewModel(
      userId: 'merchant-1',
      productsStream: products.stream,
    );
    addTearDown(() async {
      viewModel.dispose();
      await products.close();
    });

    viewModel.watchProducts();
    products.add([
      Product(
        id: 'product-1',
        name: 'Bread',
        cost: 10,
        sellingPrice: 15,
        quantity: 4,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.products, hasLength(1));
    expect(viewModel.checkLowStock().single.name, 'Bread');

    products.add([
      Product(
        id: 'product-1',
        name: 'Bread',
        cost: 10,
        sellingPrice: 15,
        quantity: 12,
      ),
      Product(
        id: 'product-2',
        name: 'Milk',
        cost: 12,
        sellingPrice: 18,
        quantity: 2,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.products, hasLength(2));
    expect(viewModel.products.first.quantity, 12);
    expect(viewModel.checkLowStock().map((product) => product.name), ['Milk']);
  });
}
