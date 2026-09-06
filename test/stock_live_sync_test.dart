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

  test('report, full list, and group drilldown share one upstream subscription',
      () async {
    final source = _CountingStream<List<Product>>();
    final viewModel = StockViewModel(
      userId: 'merchant-1',
      productsStream: source,
    );
    addTearDown(() async {
      viewModel.dispose();
      await source.close();
    });

    viewModel.watchProducts();
    final listValues = <List<Product>>[];
    final listSubscription =
        viewModel.streamProductsByGroup(null).listen(listValues.add);
    final groupValues = <List<Product>>[];
    final groupSubscription =
        viewModel.streamProductsByGroup('Bakery').listen(groupValues.add);
    addTearDown(listSubscription.cancel);
    addTearDown(groupSubscription.cancel);

    source.add([
      Product(id: 'bread', name: 'Bread', quantity: 3, group: 'Bakery'),
      Product(id: 'milk', name: 'Milk', quantity: 2, group: 'Dairy'),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(source.listenCount, 1);
    expect(viewModel.products, hasLength(2));
    expect(listValues.single, hasLength(2));
    expect(groupValues.single.single.id, 'bread');
  });
}

class _CountingStream<T> extends Stream<T> {
  final StreamController<T> _controller = StreamController<T>.broadcast();
  int listenCount = 0;

  void add(T value) => _controller.add(value);
  Future<void> close() => _controller.close();

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listenCount++;
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
