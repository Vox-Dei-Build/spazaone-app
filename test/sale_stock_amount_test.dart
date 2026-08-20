import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/pages/sales/widgets/sale_detail_page.dart';
import 'package:pasella/pages/sales/widgets/stock_amount_field.dart';
import 'package:provider/provider.dart';

void main() {
  group('Sale stock amount compatibility', () {
    test('old sales without stockAmount default to zero', () {
      final sale = Sale.fromMap({
        'amount': 2430,
        'type': 'Cash',
        'products': <String, int>{},
        'dateAdded': '2026-08-20T14:40:00.000',
      }, 'sale-1');

      expect(sale.stockAmount, 0);
    });

    test('stockAmount accepts numeric and string Firestore values', () {
      Sale parse(dynamic value) => Sale.fromMap({
            'amount': 2430,
            'stockAmount': value,
            'type': 'Cash',
            'products': <String, int>{},
            'dateAdded': '2026-08-20T14:40:00.000',
          }, 'sale-1');

      expect(parse(1200).stockAmount, 1200);
      expect(parse(1200.50).stockAmount, 1200.50);
      expect(parse('875.25').stockAmount, 875.25);
    });

    test('period totals combine sales and stock without calling it profit', () {
      Sale sale(double sales, double stock) => Sale(
            id: '$sales-$stock',
            amount: sales,
            stockAmount: stock,
            type: 'Cash',
            products: const {},
            dateAdded: DateTime(2026, 8, 20),
          );

      final totals = SalesStockTotals.fromSales([
        sale(2430, 1200),
        sale(1980, 0),
        sale(3100, 2400),
      ]);

      expect(totals.salesAmount, 7510);
      expect(totals.stockAmount, 3600);
      expect(totals.difference, 3910);
      expect(totals.entryCount, 3);
    });
  });

  group('Stock amount field', () {
    test('is optional but rejects invalid and negative values', () {
      expect(validateStockAmount(null), isNull);
      expect(validateStockAmount(''), isNull);
      expect(validateStockAmount('0'), isNull);
      expect(validateStockAmount('1250.50'), isNull);
      expect(validateStockAmount('-1'), isNotNull);
      expect(validateStockAmount('twelve hundred'), isNotNull);
    });

    testWidgets('explains that the field is money rather than stock units',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppModel(),
          child: MaterialApp(
            theme: kCustomThemeData,
            home: Scaffold(
              body: StockAmountField(controller: controller),
            ),
          ),
        ),
      );

      expect(find.text('Stock amount (optional)'), findsOneWidget);
      expect(find.text('Enter amount spent on stock'), findsOneWidget);
      expect(
        find.text('Money spent buying stock today — not units on hand.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('sale details show the recorded stock amount', (tester) async {
    final sale = Sale(
      id: 'sale-1',
      amount: 2430,
      stockAmount: 1200,
      type: 'Cash',
      products: const {},
      dateAdded: DateTime(2026, 8, 20, 14, 40),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: kCustomThemeData,
        home: SaleDetailPage(sale: sale),
      ),
    );
    await tester.pump();

    expect(find.text('Sales amount'), findsOneWidget);
    expect(find.text('Stock amount'), findsOneWidget);
    expect(find.textContaining('1 200'), findsOneWidget);
  });
}
