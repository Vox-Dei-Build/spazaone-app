import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_group_page/widgets/product_list.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';

void main() {
  final products = [
    Product(id: 'normal', name: 'Bread', sellingPrice: 18.5, quantity: 12),
    Product(id: 'low', name: 'Milk', sellingPrice: 22, quantity: 3),
    Product(
      id: 'empty',
      name: 'Rice',
      sellingPrice: 45,
      quantity: 0,
      whatsappListed: true,
    ),
    Product(
      id: 'supplier',
      name: 'Supplier kettle',
      sellingPrice: 199,
      quantity: 0,
      isDropshipListing: true,
    ),
    Product(id: 'unset', name: 'Soap', sellingPrice: 12),
  ];

  Future<void> pumpCatalogue(
    WidgetTester tester, {
    List<Product>? items,
    ValueChanged<Product>? onOpenProduct,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProductCatalogueView(
            products: items ?? products,
            onOpenProduct: onOpenProduct ?? (_) {},
          ),
        ),
      ));

  testWidgets('stock filters exclude supplier products and unknown quantities',
      (tester) async {
    await pumpCatalogue(tester);
    expect(find.text('All  5'), findsOneWidget);
    expect(find.text('Low stock  1'), findsOneWidget);
    expect(find.text('Out of stock  1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('product-filter-low')));
    await tester.pumpAndSettle();
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Bread'), findsNothing);
    expect(find.text('Rice'), findsNothing);
    expect(find.text('Supplier Kettle'), findsNothing);
    expect(find.text('Soap'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('product-filter-out')));
    await tester.pumpAndSettle();
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('Milk'), findsNothing);
    expect(find.text('Supplier Kettle'), findsNothing);
    expect(find.text('Soap'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('product-filter-all')));
    await tester.pumpAndSettle();
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('Milk'), findsOneWidget);
  });

  testWidgets(
      'parent rebuilds retain the selected filter and live subscription',
      (tester) async {
    final updates = StreamController<List<Product>>.broadcast();
    final viewModel = _CatalogueStockViewModel(updates.stream);
    addTearDown(viewModel.dispose);
    addTearDown(updates.close);
    Future<void> pumpList() => tester.pumpWidget(MaterialApp(
          home: Scaffold(body: ProductList(viewModel: viewModel)),
        ));

    await pumpList();
    updates.add(products);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('product-filter-low')));
    await tester.pump();
    await pumpList();
    expect(viewModel.subscriptionRequests, 1);
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Bread'), findsNothing);

    updates.add([
      Product(id: 'low', name: 'Milk', sellingPrice: 22, quantity: 10),
    ]);
    await tester.pump();
    expect(find.text('No products running low'), findsOneWidget);
  });

  testWidgets('opening a filtered product retains its identity',
      (tester) async {
    Product? opened;
    await pumpCatalogue(tester, onOpenProduct: (product) => opened = product);
    await tester.tap(find.byKey(const ValueKey('product-filter-out')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rice'));
    expect(identical(opened, products[2]), isTrue);
  });

  testWidgets('filter stays current after live quantity changes',
      (tester) async {
    await pumpCatalogue(tester);
    await tester.tap(find.byKey(const ValueKey('product-filter-low')));
    await tester.pumpAndSettle();
    await pumpCatalogue(tester, items: [
      Product(id: 'low', name: 'Milk', sellingPrice: 22, quantity: 10),
    ]);
    expect(find.text('No products running low'), findsOneWidget);
    expect(find.text('Low stock  0'), findsOneWidget);
    await tester.tap(find.text('Show all products'));
    await tester.pumpAndSettle();
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('10 in stock'), findsOneWidget);
  });

  testWidgets('passive online visibility never masks or crowds stock status',
      (tester) async {
    await pumpCatalogue(tester, items: [products[2]]);
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.text('Pending'), findsNothing);
  });

  testWidgets('unknown stock is distinct from out of stock', (tester) async {
    await pumpCatalogue(tester, items: [products[4]]);
    expect(find.text('Stock not set'), findsOneWidget);
    expect(find.text('Out of stock'), findsNothing);
  });

  testWidgets('normal product rows are thin and retain a full tap target',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: ProductCatalogueView(
            products: [products.first, products[1]],
            onOpenProduct: (_) {},
          ),
        ),
      ),
    ));
    expect(
        tester
            .getSize(find.widgetWithText(ProductCatalogueRow, 'Bread'))
            .height,
        inInclusiveRange(64, 68));
    expect(
        tester.getSize(find.widgetWithText(ProductCatalogueRow, 'Milk')).height,
        inInclusiveRange(64, 68));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a passive WhatsApp status stays out of the product row',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpCatalogue(
      tester,
      items: [
        Product(
          id: 'listed',
          name: 'Bread',
          sellingPrice: 18.5,
          quantity: 12,
          whatsappListed: true,
        ),
      ],
    );

    expect(
      tester.getSize(find.widgetWithText(ProductCatalogueRow, 'Bread')).height,
      inInclusiveRange(64, 68),
    );
    expect(find.text('Pending'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short catalogue viewport scrolls filters away to open a product',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Product? opened;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: SizedBox(
            height: 60,
            child: ProductCatalogueView(
              products: [products.first],
              onOpenProduct: (product) => opened = product,
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    final verticalScroll = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    await tester.scrollUntilVisible(find.text('Bread'), 40,
        scrollable: verticalScroll);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bread'));
    expect(identical(opened, products.first), isTrue);
    expect(find.text('All  1').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short catalogue viewport can recover from an empty stock filter',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: SizedBox(
            height: 60,
            child: ProductCatalogueView(
              products: [products.first],
              onOpenProduct: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester
        .ensureVisible(find.byKey(const ValueKey('product-filter-low')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('product-filter-low')));
    await tester.pumpAndSettle();
    final verticalScroll = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    await tester.scrollUntilVisible(find.text('Show all products'), 40,
        scrollable: verticalScroll);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show all products'));
    await tester.pumpAndSettle();
    expect(find.text('No products running low'), findsNothing);
    expect(find.text('Bread'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalogue rows fit narrow screens with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: ProductCatalogueView(
            products: [
              Product(
                id: 'long',
                name: 'A long product name in a family value pack',
                sellingPrice: 123456.78,
                quantity: 2,
                whatsappListed: true,
              ),
            ],
            onOpenProduct: (_) {},
          ),
        ),
      ),
    ));
    expect(find.text('Low stock · 2 left'), findsOneWidget);
    expect(find.text('Pending'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('price and arrow stay aligned at text scale $scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: kCustomThemeData,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: ProductCatalogueView(
              products: [
                products.first,
                Product(
                  id: 'long',
                  name: 'A family value pack of breakfast cereal',
                  sellingPrice: 1234567.89,
                  quantity: 0,
                  whatsappListed: true,
                ),
              ],
              onOpenProduct: (_) {},
            ),
          ),
        ),
      ));

      final priceRows = find.byKey(const ValueKey('product-price-and-arrow'));
      expect(priceRows, findsNWidgets(2));
      double? arrowRight;
      for (final row in priceRows.evaluate()) {
        final withinRow = find.byWidget(row.widget);
        final amount =
            find.descendant(of: withinRow, matching: find.byType(Text));
        final arrow = find.descendant(
            of: withinRow, matching: find.byIcon(SpazaIcons.next));
        expect(tester.getCenter(amount).dy,
            closeTo(tester.getCenter(arrow).dy, .1));
        final right = tester.getRect(arrow).right;
        if (arrowRight != null) expect(right, closeTo(arrowRight, .1));
        arrowRight = right;
      }
      expect(find.text('Out of stock'), findsOneWidget);
      expect(find.text('Pending'), findsNothing);
      final title = find.text('A Family Value Pack Of Breakfast Cereal');
      expect(tester.getSize(title).width, greaterThanOrEqualTo(120));
      expect(tester.takeException(), isNull);
    });
  }
}

class _CatalogueStockViewModel extends StockViewModel {
  _CatalogueStockViewModel(this.updates) : super(userId: 'preview-store');

  final Stream<List<Product>> updates;
  int subscriptionRequests = 0;

  @override
  Stream<List<Product>> streamProductsByGroup(String? groupName) {
    subscriptionRequests++;
    return updates.map((products) => products);
  }
}
