import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/commerce/cj_supplier_product.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/stock/dropship/supplier_catalog_page.dart';
import 'package:pasella/pages/stock/product_card/product_card.dart';

void main() {
  CjCatalogProduct supplierProduct(int index) => CjCatalogProduct(
        id: 'product-$index',
        sku: 'SKU-$index',
        title: 'Supplier product $index',
        image: '',
        category: 'Home',
        productCostUsdMinor: 100,
        estimatedProductCostMinor: 1800,
        deliverableVariantId: 'variant-$index',
        estimatedDeliveryCostMinor: 900,
        estimatedLandedCostMinor: 2700,
        logisticAging: '8-14 days',
        deliveryVerifiedAt: '2026-08-05T10:00:00.000Z',
      );

  test('catalog pages append without duplicating products', () {
    final first = [supplierProduct(1), supplierProduct(2)];
    final second = [supplierProduct(2), supplierProduct(3)];

    final merged = mergeCjCatalogPages(first, second);

    expect(merged.map((product) => product.id), [
      'product-1',
      'product-2',
      'product-3',
    ]);
  });

  testWidgets('catalogue keeps earlier products when loading more',
      (tester) async {
    final requestedPages = <int>[];
    Future<CjCatalogPage> search({
      required String query,
      required int page,
      required String cursor,
    }) async {
      requestedPages.add(page);
      final products = page == 1
          ? List.generate(24, supplierProduct)
          : List.generate(6, (index) => supplierProduct(index + 24));
      return CjCatalogPage(
        products: products,
        page: page,
        totalPages: 2,
        totalProducts: 30,
        hasMore: page == 1,
        nextCursor: page == 1 ? 'cj_product_23' : '',
        catalogueRefreshing: false,
        digitalPaymentsEnabled: false,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupplierCatalogPage(searchCatalog: search),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('supplier-product-product-0')), findsOneWidget);
    expect(find.text('24 of 30 products'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('catalog-load-more')),
      600,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('catalog-load-more')));
    await tester.pumpAndSettle();

    expect(requestedPages, [1, 2]);
    expect(find.text('30 products'), findsOneWidget);
  });

  testWidgets('catalogue ignores an old load-more response after a new search',
      (tester) async {
    final oldLoadMore = Completer<CjCatalogPage>();
    Future<CjCatalogPage> search({
      required String query,
      required int page,
      required String cursor,
    }) async {
      if (query == 'lamp') {
        return CjCatalogPage(
          products: [supplierProduct(99)],
          page: 1,
          totalPages: 1,
          totalProducts: 1,
          hasMore: false,
          nextCursor: '',
          catalogueRefreshing: false,
          digitalPaymentsEnabled: false,
        );
      }
      if (page == 2) return oldLoadMore.future;
      return CjCatalogPage(
        products: [supplierProduct(1)],
        page: 1,
        totalPages: 2,
        totalProducts: 2,
        hasMore: true,
        nextCursor: 'cj_product_1',
        catalogueRefreshing: false,
        digitalPaymentsEnabled: false,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SupplierCatalogPage(searchCatalog: search)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('catalog-load-more')),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('catalog-load-more')));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'lamp');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('supplier-product-product-99')), findsOneWidget);

    oldLoadMore.complete(
      CjCatalogPage(
        products: [supplierProduct(2)],
        page: 2,
        totalPages: 2,
        totalProducts: 2,
        hasMore: false,
        nextCursor: '',
        catalogueRefreshing: false,
        digitalPaymentsEnabled: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('supplier-product-product-2')), findsNothing);
    expect(
        find.byKey(const Key('supplier-product-product-99')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
