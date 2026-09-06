import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/reports/business_report_model.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_search_field.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_row.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/orders_summary_bar.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';
import 'package:pasella/pages/reports/business_report/business_report.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'customer orders retain status, total and action at scale $scale',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(scale == 1 ? 390 : 320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
          theme: kCustomThemeData,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: OrderRow(
            id: 'order-123456',
            status: OrderStatus.paid,
            totalText: 'R1 250,00',
            itemsCount: 3,
            relativeTime: '12:45',
            onTap: () => opened++,
            collectedBadge:
                const CollectedBadge(text: 'Uncollected', color: Colors.orange),
          )))));
      expect(find.byType(Card), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textSpan
                      ?.toPlainText()
                      .contains('3 items  ·  12:45  ·  #123456') ==
                  true,
        ),
        findsOneWidget,
      );
      expect(find.text('Uncollected'), findsOneWidget);
      final amount = tester.getRect(find.text('R1 250,00'));
      final chevron = tester.getRect(find.byIcon(Icons.chevron_right_rounded));
      expect(amount.center.dy, closeTo(chevron.center.dy, .1));
      expect(
        tester.getRect(find.text('Uncollected')).top,
        greaterThan(amount.bottom),
      );
      if (scale == 1) {
        expect(tester.getSize(find.byType(OrderRow)).height,
            lessThanOrEqualTo(90));
      }
      expect(amount.right, lessThanOrEqualTo(scale == 1 ? 390 : 320));
      await tester.tap(find.text('R1 250,00'));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('orders summary keeps production left and right anchors',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            OrdersSummaryBar(
              count: 1,
              totalText: 'R200,00',
              rangeText: 'All time',
            ),
          ],
        ),
      ),
    ));

    expect(find.text('1 order'), findsOneWidget);
    expect(
        tester.getSize(find.byKey(const ValueKey('orders-summary-bar'))).width,
        390);
    expect(tester.getRect(find.text('1 order')).left, lessThanOrEqualTo(16));
    expect(
        tester.getRect(find.text('R200,00')).right, greaterThanOrEqualTo(374));
    expect(tester.takeException(), isNull);
  });

  testWidgets('production order search stays compact', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OrderSearchField(controller: controller, onChanged: (_) {}),
      ),
    ));

    expect(
        tester.getSize(find.byType(TextField)).height, lessThanOrEqualTo(52));
    expect(tester.takeException(), isNull);
  });

  testWidgets('summary gives follow-up rows room without explanatory header',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: kCustomThemeData,
        home: Scaffold(
            body: SingleChildScrollView(
                child: CustomerBalanceSummary(
          report: Report(
              totalNumberofNPAs: 1,
              nplRatio: 20,
              cashflowImpact: -150,
              customersWithNPAs: [
                {
                  'id': 'one',
                  'name': 'Naledi Mokoena',
                  'number': '0821234567',
                  'balance': -150
                }
              ]),
          totalCustomers: 5,
        )))));
    await tester.pumpAndSettle();
    expect(find.text('Customers owe you'), findsOneWidget);
    expect(find.text('Active customers'), findsOneWidget);
    expect(find.text('Paid up'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Customers to follow up')).dy,
        lessThan(250));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('customer-follow-up-one')))
            .height,
        lessThanOrEqualTo(80));
    expect(tester.takeException(), isNull);
  });
}
