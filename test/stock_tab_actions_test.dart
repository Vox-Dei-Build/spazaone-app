import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/stock/stock.dart';

void main() {
  testWidgets('product search and add share one compact toolbar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var searchTaps = 0;
    var addTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductWorkspaceToolbar(
            onTap: () => searchTaps++,
            onAddProduct: () => addTaps++,
          ),
        ),
      ),
    );

    expect(find.text('Search products'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ProductWorkspaceToolbar)).height,
      lessThan(70),
    );

    await tester.tap(find.byKey(const ValueKey('search-products-launcher')));
    await tester.tap(find.byKey(const ValueKey('add-product-action')));
    expect(searchTaps, 1);
    expect(addTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product search is visible and scoped to Products', (
    tester,
  ) async {
    var searchTaps = 0;
    var helpTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockTabActions(
            showProductSearch: true,
            onSearch: () => searchTaps++,
            onHelp: () => helpTaps++,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('search-my-products')), findsOneWidget);
    expect(find.byTooltip('Search my products'), findsOneWidget);
    expect(find.byType(PopupMenuButton), findsNothing);

    await tester.tap(find.byKey(const ValueKey('search-my-products')));
    await tester.tap(find.byKey(const ValueKey('stock-help')));
    expect(searchTaps, 1);
    expect(helpTaps, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockTabActions(
            showProductSearch: false,
            onSearch: () => searchTaps++,
            onHelp: () => helpTaps++,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('search-my-products')), findsNothing);
    expect(find.byKey(const ValueKey('stock-help')), findsOneWidget);
  });
}
