import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/commerce/cj_supplier_product.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/stock/dropship/dropship_listing_page.dart';
import 'package:pasella/pages/stock/dropship/supplier_catalog_page.dart';
import 'package:pasella/pages/stock/product_card/product_card.dart';
import 'package:pasella/services/commerce_service.dart';
import 'package:pasella/utils/currency_util.dart';

void main() {
  CjCatalogProduct supplierProduct(
    int index, {
    int productCostMinor = 1800,
    int deliveryCostMinor = 900,
    String? verifiedAt,
  }) {
    final quoteVersion = verifiedAt ??
        DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 1))
            .toIso8601String();
    return CjCatalogProduct(
      id: 'product-$index',
      sku: 'SKU-$index',
      title: 'Supplier product $index',
      image: '',
      category: 'Home',
      productCostUsdMinor: 100,
      estimatedProductCostMinor: productCostMinor,
      deliverableVariantId: 'variant-$index',
      estimatedDeliveryCostMinor: deliveryCostMinor,
      estimatedLandedCostMinor: productCostMinor + deliveryCostMinor,
      logisticAging: '8-14 days',
      deliveryVerifiedAt: quoteVersion,
      catalogQuoteVersion: quoteVersion,
    );
  }

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

  testWidgets('catalogue gives browsing space to products on a small phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<CjCatalogPage> search({
      required String query,
      required int page,
      required String cursor,
    }) async =>
        CjCatalogPage(
          products: [supplierProduct(0), supplierProduct(1)],
          page: 1,
          totalPages: 1,
          totalProducts: 2,
          hasMore: false,
          nextCursor: '',
          catalogueRefreshing: false,
          digitalPaymentsEnabled: false,
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SupplierCatalogPage(searchCatalog: search)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Search supplier products'), findsOneWidget);
    expect(find.text('Supplier catalogue'), findsNothing);
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .every((chip) => chip.side != BorderSide.none),
      isTrue,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('supplier-product-product-0'))).dy,
      lessThan(230),
    );
    await tester.tap(find.byKey(const Key('catalog-sort')));
    await tester.pumpAndSettle();
    final recommendedLabel = find.text('Recommended');
    expect(recommendedLabel, findsOneWidget);
    expect(tester.getSize(recommendedLabel).width, greaterThan(80));
    expect(tester.getSize(recommendedLabel).height, lessThan(30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalogue keeps category chips directly scrollable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final queries = <String>[];

    Future<CjCatalogPage> search({
      required String query,
      required int page,
      required String cursor,
    }) async {
      queries.add(query);
      return CjCatalogPage(
        products: [supplierProduct(0)],
        page: 1,
        totalPages: 1,
        totalProducts: 1,
        hasMore: false,
        nextCursor: '',
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
    expect(tester.takeException(), isNull);

    expect(find.byKey(const Key('catalog-all-filters')), findsNothing);
    expect(find.byKey(const Key('catalog-category-strip')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('catalog-category-accessories')),
      180,
      scrollable: find.descendant(
        of: find.byKey(const Key('catalog-category-strip')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('catalog-category-accessories')).hitTestable(),
    );
    await tester.pumpAndSettle();

    expect(queries.last, 'accessories');
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalogue moves controls beside products in phone landscape',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<CjCatalogPage> search({
      required String query,
      required int page,
      required String cursor,
    }) async =>
        CjCatalogPage(
          products: List.generate(4, supplierProduct),
          page: 1,
          totalPages: 1,
          totalProducts: 4,
          hasMore: false,
          nextCursor: '',
          catalogueRefreshing: false,
          digitalPaymentsEnabled: false,
        );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(720, 320)),
          child: Scaffold(body: SupplierCatalogPage(searchCatalog: search)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalog-landscape-layout')), findsOneWidget);
    expect(
      find.byKey(const Key('catalog-landscape-filters')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('catalog-sort')), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('catalog-landscape-filters')),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('catalog-category-accessories')).hitTestable(),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('supplier-product-product-0'))).dy,
      lessThan(20),
    );
    expect(tester.takeException(), isNull);
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

  testWidgets('unknown catalogue total still labels continuation as load more',
      (tester) async {
    Future<CjCatalogPage> search({
      required String query,
      required int page,
      required String cursor,
    }) async =>
        CjCatalogPage(
          products: [supplierProduct(80)],
          page: 1,
          totalPages: 2,
          totalProducts: 0,
          totalProductsExact: false,
          usableProductsLowerBound: 2,
          hasMore: true,
          nextCursor: 'raw_after_product_80',
          catalogueRefreshing: true,
          digitalPaymentsEnabled: false,
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SupplierCatalogPage(searchCatalog: search)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('catalog-load-more')),
      300,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('1 product'), findsOneWidget);
    expect(find.text('Load more products'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('empty bounded scan continues from its server cursor',
      (tester) async {
    final requests = <({int page, String cursor})>[];
    Future<CjCatalogPage> search({
      required String query,
      required int page,
      required String cursor,
    }) async {
      requests.add((page: page, cursor: cursor));
      if (page == 1) {
        return const CjCatalogPage(
          products: [],
          page: 1,
          totalPages: 2,
          totalProducts: 0,
          totalProductsExact: false,
          scanLimited: true,
          hasMore: true,
          nextCursor: 'last_checked_stale_raw_doc',
          catalogueRefreshing: true,
          digitalPaymentsEnabled: false,
        );
      }
      return CjCatalogPage(
        products: [supplierProduct(81)],
        page: 2,
        totalPages: 2,
        totalProducts: 0,
        totalProductsExact: false,
        usableProductsLowerBound: 1,
        hasMore: false,
        nextCursor: '',
        catalogueRefreshing: true,
        digitalPaymentsEnabled: false,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SupplierCatalogPage(searchCatalog: search)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('More products available'), findsOneWidget);
    expect(find.text('Adding matching products'), findsNothing);
    await tester.tap(find.text('Continue loading products'));
    await tester.pumpAndSettle();

    expect(requests, [
      (page: 1, cursor: ''),
      (page: 2, cursor: 'last_checked_stale_raw_doc'),
    ]);
    expect(
      find.byKey(const Key('supplier-product-product-81')),
      findsOneWidget,
    );
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

  testWidgets('failed new search retry restarts from page one', (tester) async {
    final requests = <({String query, int page, String cursor})>[];
    var failedLampSearch = false;
    Future<CjCatalogPage> search({
      required String query,
      required int page,
      required String cursor,
    }) async {
      requests.add((query: query, page: page, cursor: cursor));
      if (query == 'lamp') {
        if (!failedLampSearch) {
          failedLampSearch = true;
          throw Exception('connection lost');
        }
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
      return CjCatalogPage(
        products: [supplierProduct(page)],
        page: page,
        totalPages: 2,
        totalProducts: 2,
        hasMore: page == 1,
        nextCursor: page == 1 ? 'page-one-cursor' : '',
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
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'lamp');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Could not refresh products'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(requests.sublist(requests.length - 2), [
      (query: 'lamp', page: 1, cursor: ''),
      (query: 'lamp', page: 1, cursor: ''),
    ]);
    expect(
      find.byKey(const Key('supplier-product-product-99')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'server-approved catalogue card opens without a second details request',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<CjCatalogPage> search({
      required String query,
      required int page,
      required String cursor,
    }) async =>
        CjCatalogPage(
          products: [supplierProduct(1)],
          page: 1,
          totalPages: 1,
          totalProducts: 1,
          hasMore: false,
          nextCursor: '',
          catalogueRefreshing: false,
          digitalPaymentsEnabled: false,
        );

    var createCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupplierCatalogPage(
            searchCatalog: search,
            createListing: ({
              required supplierProductId,
              required supplierVariantId,
              required catalogQuoteVersion,
              required markupMinor,
            }) async {
              createCalls++;
              return const DropshipListingResult(
                listingId: 'listing-1',
                sellerProductId: 'product-1',
                checkoutUrl: 'https://example.test/checkout',
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('supplier-product-product-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Product unavailable right now'), findsNothing);
    expect(find.byKey(const Key('dropship-markup-field')), findsOneWidget);
    expect(find.text('Recommended option'), findsOneWidget);
    expect(find.text('Add product'), findsOneWidget);
    expect(createCalls, 0);
    await tester.ensureVisible(
      find.byKey(const Key('dropship-markup-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dropship-markup-field')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('dropship-markup-field')),
      '25.00',
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(ElevatedButton, 'Add product').hitTestable(),
      findsOneWidget,
    );
    final addButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Add product'),
    );
    expect(addButton.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed quote updates the same sheet and requires confirmation',
      (tester) async {
    Future<CjCatalogPage> search({
      required String query,
      required int page,
      required String cursor,
    }) async =>
        CjCatalogPage(
          products: [supplierProduct(2)],
          page: 1,
          totalPages: 1,
          totalProducts: 1,
          hasMore: false,
          nextCursor: '',
          catalogueRefreshing: false,
          digitalPaymentsEnabled: false,
        );

    var createCalls = 0;
    final changed = supplierProduct(
      2,
      productCostMinor: 2100,
      deliveryCostMinor: 1100,
      verifiedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupplierCatalogPage(
            searchCatalog: search,
            createListing: ({
              required supplierProductId,
              required supplierVariantId,
              required catalogQuoteVersion,
              required markupMinor,
            }) async {
              createCalls++;
              if (createCalls == 1) {
                throw DropshipListingQuoteChanged(
                  product: changed,
                  message: 'Price or delivery changed.',
                );
              }
              return const DropshipListingResult(
                listingId: 'listing-2',
                sellerProductId: 'seller-product-2',
                checkoutUrl: 'https://example.test/checkout',
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('supplier-product-product-2')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dropship-markup-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('dropship-markup-field')),
      '25.00',
    );
    await tester.pump();
    await tester
        .ensureVisible(find.widgetWithText(ElevatedButton, 'Add product'));
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Add product').hitTestable(),
    );
    await tester.pumpAndSettle();

    expect(createCalls, 1);
    expect(
      find.text(
        'Price or delivery changed. Review the updated costs, then tap Add product again.',
      ),
      findsOneWidget,
    );
    expect(find.text(CurrencyUtil.format(32)), findsWidgets);

    await tester
        .ensureVisible(find.widgetWithText(ElevatedButton, 'Add product'));
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Add product').hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(createCalls, 2);
    expect(find.text('Added to your products'), findsOneWidget);
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
    expect(field.textInputAction, TextInputAction.done);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    await tester.tap(find.byKey(const Key('dropship-markup-field')));
    await tester.pump();
    expect(find.byKey(const Key('dropship-markup-done')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('dropship-markup-field')),
      '123,45',
    );
    expect(latest, '123,45');
    expect(dropshipMarkupMinor(latest), 12345);

    await tester.tap(find.byKey(const Key('dropship-markup-done')));
    await tester.pump();
    expect(find.byKey(const Key('dropship-markup-done')), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
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

  testWidgets('supplier inventory listing can change markup and pause',
      (tester) async {
    int? savedMarkup;
    String? savedState;
    final product = Product(
      id: 'dropship-product',
      name: 'Supplier lamp',
      cost: 100,
      sellingPrice: 120,
      baseCostMinor: 10000,
      markupMinor: 2000,
      sellPriceMinor: 12000,
      whatsappListed: true,
      isDropshipListing: true,
      commerceListingId: 'listing-1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DropshipListingPage(
          product: product,
          docID: product.id!,
          listingUpdater: ({
            required sellerProductId,
            required listingId,
            required markupMinor,
            required state,
          }) async {
            savedMarkup = markupMinor;
            savedState = state;
            return DropshipListingUpdateResult(
              state: state,
              markupMinor: markupMinor,
              sellPriceMinor: 10000 + markupMinor,
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('edit-dropship-listing')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('edit-dropship-markup')),
      '35.50',
    );
    await tester.tap(find.byKey(const ValueKey('edit-dropship-state')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paused').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-dropship-listing')));
    await tester.pumpAndSettle();

    expect(savedMarkup, 3550);
    expect(savedState, 'paused');
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('dropship-listing-state'),
              skipOffstage: false,
            ),
          )
          .data,
      'Paused',
    );
    final promote = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('promote-dropship-listing')),
    );
    expect(promote.onPressed, isNull);
  });

  testWidgets('saved catalogue products persist and remain visibly unavailable',
      (tester) async {
    final available = supplierProduct(1);
    final unavailable = CjCatalogProduct(
      id: 'product-2',
      sku: 'SKU-2',
      title: 'Saved village lamp',
      image: '',
      category: 'Home',
      productCostUsdMinor: 100,
      estimatedProductCostMinor: 1800,
      deliverableVariantId: 'variant-2',
      estimatedDeliveryCostMinor: 900,
      estimatedLandedCostMinor: 2700,
      logisticAging: '8-14 days',
      deliveryVerifiedAt: DateTime.now().toUtc().toIso8601String(),
      saved: true,
      availability: 'unavailable',
    );
    final savedProducts = <CjCatalogProduct>[unavailable];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupplierCatalogPage(
            searchCatalog: ({
              required query,
              required page,
              required cursor,
            }) async =>
                CjCatalogPage(
              products: [available],
              page: 1,
              totalPages: 1,
              totalProducts: 1,
              hasMore: false,
              nextCursor: '',
              catalogueRefreshing: false,
              digitalPaymentsEnabled: false,
            ),
            loadSavedProducts: () async => List.of(savedProducts),
            setSavedProduct: (product, {required bool saved}) async {
              if (saved) {
                savedProducts.add(available);
              } else {
                savedProducts.removeWhere(
                  (savedProduct) => savedProduct.id == product.id,
                );
              }
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('save-supplier-product-product-1')),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalog-saved-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Saved village lamp'), findsOneWidget);
    expect(find.text('Currently unavailable'), findsOneWidget);
  });
}
