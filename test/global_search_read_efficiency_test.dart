import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/view_model/global_search_view_model.dart';

void main() {
  test('product search filters locally after one catalogue subscription',
      () async {
    final source = _CountingStream<List<Product>>();
    final viewModel = GlobalSearchViewModel(
      userId: 'store-a',
      productsStream: source,
    );
    addTearDown(() async {
      viewModel.dispose();
      await source.close();
    });

    viewModel.updateSearchQuery('m');
    source.add([
      Product(id: 'milk', name: 'Milk', group: 'Dairy'),
      Product(id: 'meal', name: 'Maize meal', group: 'Pantry'),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(source.listenCount, 1);
    expect(viewModel.searchResults, hasLength(2));

    viewModel.updateSearchQuery('mi');
    viewModel.updateSearchQuery('mil');
    viewModel.updateSearchQuery('');
    viewModel.updateSearchQuery('milk');

    expect(source.listenCount, 1);
    expect(viewModel.searchResults.single.id, 'milk');
  });

  test('group search keeps results within the selected store group', () async {
    final source = _CountingStream<List<Product>>();
    final viewModel = GlobalSearchViewModel(
      userId: 'store-a',
      productsStream: source,
    );
    addTearDown(() async {
      viewModel.dispose();
      await source.close();
    });

    viewModel.updateSearchQuery('m', isGroupSearch: true, groupName: 'Dairy');
    source.add([
      Product(id: 'milk', name: 'Milk', group: 'Dairy'),
      Product(id: 'meal', name: 'Maize meal', group: 'Pantry'),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.searchResults.map((product) => product.id), ['milk']);
  });

  test('a late catalogue snapshot cannot refill a cleared search', () async {
    final source = _CountingStream<List<Product>>();
    final viewModel = GlobalSearchViewModel(
      userId: 'store-a',
      productsStream: source,
    );
    addTearDown(() async {
      viewModel.dispose();
      await source.close();
    });

    viewModel.updateSearchQuery('milk');
    viewModel.updateSearchQuery('');
    source.add([Product(id: 'milk', name: 'Milk', group: 'Dairy')]);
    await Future<void>.delayed(Duration.zero);

    expect(source.listenCount, 1);
    expect(viewModel.searchResults, isEmpty);
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
