import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/reports/business_report/widgets/customer_activity_timeline.dart';
import 'package:pasella/pages/reports/business_report/widgets/date_range_movement_summary_card.dart';
import 'package:pasella/utils/currency_util.dart';

void main() {
  final sale = CustomerActivityEntry(
    id: 'sale',
    customerId: 'customer-a',
    customerName: 'Naledi Mokoena',
    type: 'Credit',
    amount: 250,
    when: DateTime(2026, 9, 3, 9, 30),
  );
  final payment = CustomerActivityEntry(
    id: 'payment',
    customerId: 'customer-b',
    customerName: 'Thabo Dlamini',
    type: 'Payment',
    amount: 100,
    when: DateTime(2026, 9, 4, 12, 45),
  );

  Widget frame(Widget child, {double textScale = 1}) => MaterialApp(
        theme: kCustomThemeData,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(10), child: child),
          ),
        ),
      );

  test('activity movement keeps payments positive and sales negative', () {
    expect(sale.movement, -250);
    expect(payment.movement, 100);
    expect(
      const CustomerActivityEntry(
        id: 'other',
        customerId: 'customer-a',
        customerName: 'Naledi',
        type: 'Note',
        amount: 45,
      ).movement,
      0,
    );
  });

  testWidgets('entries show newest first and open the matching customer', (
    tester,
  ) async {
    CustomerActivityEntry? opened;
    await tester.pumpWidget(frame(CustomerActivityTimeline(
      entries: [sale, payment],
      reportedNet: -150,
      onOpenCustomer: (entry) => opened = entry,
    )));

    expect(find.text('2 entries · 2 customers'), findsOneWidget);
    expect(find.text('Payment received · 12:45'), findsOneWidget);
    expect(find.text('Sale added · 09:30'), findsOneWidget);
    expect(find.text('+R100,00'), findsOneWidget);
    expect(find.text('−R250,00'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Thabo Dlamini')).dy,
      lessThan(tester.getTopLeft(find.text('Naledi Mokoena')).dy),
    );
    expect(find.text('Entries match the net movement above.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('customer-activity-payment')));
    expect(opened?.customerId, 'customer-b');
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px activity remains readable with large text and amounts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var openings = 0;
    await tester.pumpWidget(frame(
      Column(
        children: [
          const CustomerActivitySummary(
            netMovement: -1234567.89,
            salesAmount: 2234567.89,
            salesCount: 104,
            paymentsAmount: 1000000,
            paymentsCount: 26,
          ),
          CustomerActivityTimeline(
            entries: [
              CustomerActivityEntry(
                id: 'long-name',
                customerId: 'customer-a',
                customerName: 'A Customer With A Very Long Surname Mokoena',
                type: 'Credit',
                amount: 2234567.89,
                when: DateTime(2026, 9, 4, 12, 45),
              ),
            ],
            onOpenCustomer: (_) => openings++,
          ),
        ],
      ),
      textScale: 2,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sales added · 104'), findsOneWidget);
    expect(find.text('Payments received · 26'), findsOneWidget);
    expect(find.text('Payments received − sales added'), findsOneWidget);
    for (final amount in [
      CurrencyUtil.format(-1234567.89),
      CurrencyUtil.format(2234567.89),
      CurrencyUtil.format(1000000),
      '−${CurrencyUtil.format(2234567.89)}',
    ]) {
      final rect = tester.getRect(find.text(amount));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('A Customer With A Very Long Surname Mokoena'),
      200,
    );
    await tester.tap(find.text('A Customer With A Very Long Surname Mokoena'));
    expect(openings, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty activity is distinct from a reconciliation mismatch', (
    tester,
  ) async {
    await tester.pumpWidget(frame(CustomerActivityTimeline(
      entries: const [],
      reportedNet: 0,
      onOpenCustomer: (_) {},
    )));
    expect(find.text('No activity for these dates'), findsOneWidget);
    expect(find.text('0 entries · 0 customers'), findsOneWidget);

    await tester.pumpWidget(frame(CustomerActivityTimeline(
      entries: [sale, payment],
      reportedNet: -125,
      onOpenCustomer: (_) {},
    )));
    expect(find.text('No activity for these dates'), findsNothing);
    expect(
      find.textContaining('a difference of R25,00'),
      findsOneWidget,
    );
    expect(find.text('Entries match the net movement above.'), findsNothing);
  });

  testWidgets(
      'activity paging is reachable in landscape and reconciles all entries', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    List<CustomerActivityEntry> makeEntries({double lastAmount = 1}) =>
        List.generate(
          63,
          (index) => CustomerActivityEntry(
            id: 'entry-$index',
            customerId: 'customer-a',
            customerName: 'Naledi Mokoena',
            type: 'Payment',
            amount: index == 62 ? lastAmount : 1,
            when: DateTime(2026, 9, index < 50 ? 4 : 3, 14)
                .subtract(Duration(minutes: index)),
          ),
        );

    Widget timeline({double lastAmount = 1}) => frame(
          CustomerActivityTimeline(
            entries: makeEntries(lastAmount: lastAmount),
            reportedNet: 62 + lastAmount,
            onOpenCustomer: (_) {},
          ),
          textScale: 2,
        );

    await tester.pumpWidget(timeline());
    expect(find.text('63 entries · 1 customer'), findsOneWidget);
    expect(find.text('Showing 50 of 63 entries'), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-activity-entry-49')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('customer-activity-entry-50')), findsNothing);
    expect(find.text('Thu, 3 Sep 2026'), findsNothing);
    expect(find.text('Entries match the net movement above.'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('customer-activity-show-more')),
    );
    await tester.tap(find.byKey(const ValueKey('customer-activity-show-more')));
    await tester.pumpAndSettle();
    expect(find.text('Showing 63 of 63 entries'), findsOneWidget);
    expect(find.text('Thu, 3 Sep 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-activity-entry-62')),
        findsOneWidget);
    expect(find.text('Show more'), findsNothing);

    // New list and entry instances with the same values are normal rebuilds.
    await tester.pumpWidget(timeline());
    expect(find.text('Showing 63 of 63 entries'), findsOneWidget);

    // A real update resets presentation, including a changed hidden amount.
    await tester.pumpWidget(timeline(lastAmount: 3));
    expect(find.text('Showing 50 of 63 entries'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('customer-activity-entry-62')), findsNothing);
    expect(find.text('Entries match the net movement above.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
