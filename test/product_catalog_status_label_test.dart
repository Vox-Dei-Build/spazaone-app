import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/models/stock/whatsapp_catalog_status.dart';
import 'package:pasella/pages/stock/product_group_page/widgets/product_list.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';

WhatsAppCatalogSnapshot snapshotWith(String status, {String action = 'none'}) {
  return WhatsAppCatalogSnapshot.fromMap({
    'schemaVersion': 2,
    'checkedAtMs': 1000,
    'freshUntilMs': 301000,
    'rollout': 'enabled',
    'summary': {
      'totalProducts': 1,
      'eligible': 1,
      'live': status == 'live' ? 1 : 0,
      'syncing': status == 'syncing' ? 1 : 0,
      'needsAttention': 0,
      'removalSyncing': 0,
      'supportReview': 0,
      'canBrowseFive': false,
      'canBrowseTen': false,
    },
    'products': [
      {
        'productId': 'bread',
        'status': status,
        'reasonCodes': const <String>[],
        'action': action,
        'updatedAtMs': 1000,
      },
    ],
    'catalogVersion': 'version-a',
  });
}

void main() {
  Future<void> pumpList(
    WidgetTester tester, {
    WhatsAppCatalogSnapshot? snapshot,
  }) async {
    final product = Product(
      id: 'bread',
      name: 'Bread',
      sellingPrice: 18,
      quantity: 5,
      whatsappListed: true,
    );
    final viewModel = StockViewModel(
      userId: 'store-a',
      productsStream: Stream.value([product]),
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductList(
            viewModel: viewModel,
            catalogSnapshot: snapshot,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a local listing request stays out of the compact product row',
      (tester) async {
    await pumpList(tester);

    expect(find.text('Pending'), findsNothing);
    expect(find.text('Online'), findsNothing);
  });

  testWidgets('passive server status stays in the catalogue summary',
      (tester) async {
    await pumpList(tester, snapshot: snapshotWith('live'));

    expect(find.text('Live on WhatsApp'), findsNothing);
    expect(find.text('Pending'), findsNothing);
  });

  testWidgets('refresh status action retains its callable and stock warning',
      (tester) async {
    var refreshes = 0;
    final viewModel = StockViewModel(
      userId: 'store-a',
      productsStream: Stream.value([
        Product(id: 'bread', name: 'Bread', quantity: 0, whatsappListed: true),
      ]),
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductList(
          viewModel: viewModel,
          catalogSnapshot: snapshotWith('stale', action: 'refresh'),
          onCatalogRefresh: () async => refreshes++,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Out of stock'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('product-catalog-action')));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status action uses the selected filtered product identity',
      (tester) async {
    Product? actionProduct;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductCatalogueView(
          products: [
            Product(id: 'milk', name: 'Milk', quantity: 10),
            Product(id: 'bread', name: 'Bread', quantity: 0),
          ],
          catalogSnapshot:
              snapshotWith('needs_attention', action: 'edit_product'),
          onOpenProduct: (_) =>
              fail('Status action must not trigger the row action'),
          onCatalogAction: (product) => actionProduct = product,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('product-filter-out')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.widgetWithText(ProductCatalogueRow, 'Bread')).height,
      inInclusiveRange(64, 68),
    );
    await tester.tap(find.byKey(const ValueKey('product-catalog-action')));
    expect(actionProduct?.id, 'bread');
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalogue summary remains available when product loading fails',
      (tester) async {
    final products = StreamController<List<Product>>();
    final viewModel = StockViewModel(
      userId: 'store-a',
      productsStream: products.stream,
    );
    addTearDown(viewModel.dispose);
    addTearDown(products.close);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductList(
          viewModel: viewModel,
          header: const Text('Independent catalogue status'),
        ),
      ),
    ));
    expect(find.text('Independent catalogue status'), findsOneWidget);
    products.addError(StateError('Product stream unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Independent catalogue status'), findsOneWidget);
    expect(find.text('Could not load products. Please try again.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
