import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/utils/currency_util.dart';
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

  testWidgets('stock values and low-stock rows stay compact and accurate',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final viewModel = _StockViewModelStub([
      Product(
          id: 'milk', name: 'Milk', cost: 10, sellingPrice: 25, quantity: 2),
      Product(id: 'rice', name: 'Rice', cost: 5, sellingPrice: 15, quantity: 0),
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: Scaffold(body: ProductReportsTab(viewModel: viewModel)),
    ));
    expect(find.text(CurrencyUtil.format(20)), findsOneWidget);
    expect(find.text(CurrencyUtil.format(50)), findsOneWidget);
    expect(find.text(CurrencyUtil.format(30)), findsOneWidget);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('stock-value-summary')))
            .height,
        lessThan(200));
    expect(
        tester.getSize(find.byKey(const ValueKey('stock-alert-milk'))).height,
        lessThanOrEqualTo(64));
    expect(find.text('2 left'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'stock report excludes supplier listings and handles legacy negative stock',
      (tester) async {
    final viewModel = _StockViewModelStub([
      Product(
          id: 'milk', name: 'Milk', cost: 10, sellingPrice: 25, quantity: 2),
      Product(
        id: 'supplier',
        name: 'Supplier kettle',
        cost: 100,
        sellingPrice: 300,
        quantity: 2,
        isDropshipListing: true,
      ),
      Product(
        id: 'legacy-negative',
        name: 'Legacy negative stock',
        cost: 100,
        sellingPrice: 120,
        quantity: -2,
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: Scaffold(body: ProductReportsTab(viewModel: viewModel)),
    ));

    expect(find.text(CurrencyUtil.format(20)), findsOneWidget);
    expect(find.text(CurrencyUtil.format(50)), findsOneWidget);
    expect(find.text(CurrencyUtil.format(30)), findsOneWidget);
    expect(find.text('Supplier kettle'), findsNothing);
    expect(find.text('Legacy negative stock'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Out of stock')).style?.color,
      SpazaColors.error,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('negative possible profit uses the error colour', (tester) async {
    final viewModel = _StockViewModelStub([
      Product(
        id: 'loss',
        name: 'Loss item',
        cost: 20,
        sellingPrice: 10,
        quantity: 1,
      ),
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: Scaffold(body: ProductReportsTab(viewModel: viewModel)),
    ));

    final profit = tester.widget<Text>(
      find.text(CurrencyUtil.format(-10)),
    );
    expect(profit.style?.color, SpazaColors.error);
    final hero = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const ValueKey('stock-value-summary')),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = hero.decoration! as BoxDecoration;
    expect(decoration.color, SpazaColors.error.withValues(alpha: .08));
  });

  testWidgets('stock valuation does not cap valid large quantities',
      (tester) async {
    final viewModel = _StockViewModelStub([
      Product(
        id: 'bulk',
        name: 'Bulk item',
        cost: 2,
        sellingPrice: 3,
        quantity: (1 << 31) + 1,
      ),
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: Scaffold(body: ProductReportsTab(viewModel: viewModel)),
    ));

    expect(
      find.text(CurrencyUtil.format(((1 << 31) + 1) * 2)),
      findsOneWidget,
    );
    expect(
      find.text(CurrencyUtil.format(((1 << 31) + 1) * 3)),
      findsOneWidget,
    );
    expect(
      find.text(CurrencyUtil.format((1 << 31) + 1)),
      findsOneWidget,
    );
  });
}
