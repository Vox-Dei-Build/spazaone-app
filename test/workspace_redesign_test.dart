import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/common/balance_summary_model.dart';
import 'package:pasella/pages/reports/business_report/widgets/date_range_movement_summary_card.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/pages/sales/widgets/date_filter_bar.dart';
import 'package:pasella/pages/sales/widgets/sales_stats_card.dart';
import 'package:pasella/pages/stock/product_report/widget/product_summary_card.dart';
import 'package:pasella/pages/stock/stock.dart';

class _SalesViewModelStub implements SalesViewModel {
  @override
  double totalSales = 1250;

  @override
  double totalCost = 800;

  @override
  double totalProfit = 450;

  @override
  int totalNumberOfSales = 7;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _phone({
  required Widget child,
  double width = 320,
  double height = 640,
  double textScale = 1,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('date control stays visible and overflow-free at large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _phone(
        textScale: 2,
        child: DateFilterBar(
          selectedDay: DateTime(2026, 8, 14),
          startDate: null,
          endDate: null,
          onDaySelect: (_) {},
          onRangeSelect: (_, __) {},
          onClear: () {},
        ),
      ),
    );

    expect(find.text('Showing'), findsOneWidget);
    expect(find.text('Change dates'), findsOneWidget);
    expect(find.byType(PopupMenuButton), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Change dates'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Choose a date range'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stock summary stacks cleanly at large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _phone(
        textScale: 2,
        child: const SingleChildScrollView(
          child: ProductValueSummary(
            costValue: 1200,
            salesValue: 1800,
            potentialProfit: 600,
          ),
        ),
      ),
    );

    expect(find.text('Stock value'), findsOneWidget);
    expect(find.text('What stock cost'), findsOneWidget);
    expect(find.text('Selling value'), findsOneWidget);
    expect(find.text('Possible profit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer activity summary stacks cleanly at large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _phone(
        textScale: 2,
        child: SingleChildScrollView(
          child: DateRangeMovementSummaryContent(
            summary: BalanceSummary(
              netBalance: -250,
              paymentCount: 2,
              paymentAmount: 150,
              creditCount: 3,
              creditAmount: 400,
              totalCustomers: 4,
              owingNumberOfCustomers: 2,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Movement in this period'), findsOneWidget);
    expect(find.text('3 transactions'), findsOneWidget);
    expect(find.text('2 payments'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recorded sales summary stays clear on a narrow phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final viewModel = _SalesViewModelStub();

    await tester.pumpWidget(
      _phone(
        textScale: 2,
        child: Column(
          children: [
            SalesStatsCard(
              viewModel: viewModel,
              selectedDay: DateTime(2026, 8, 14),
            ),
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ),
    );

    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Profit'), findsOneWidget);
    expect(find.text('Recorded'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product context actions keep their label and actions visible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _phone(
        textScale: 1.8,
        child: StockTabActions(
          title: 'Manage your products',
          showProductSearch: true,
          onSearch: () {},
          onHelp: () {},
        ),
      ),
    );

    expect(find.text('Manage your products'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-my-products')), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-help')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
