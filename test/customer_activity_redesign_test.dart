import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/common/balance_summary_model.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/reports/business_report/business_report.dart';
import 'package:pasella/pages/reports/business_report/widgets/customer_activity_timeline.dart';
import 'package:pasella/pages/reports/business_report/widgets/date_range_movement_summary_card.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

class _StubBalanceSummaryProvider extends ChangeNotifier
    implements BalanceSummaryProvider {
  @override
  final BalanceSummary balanceSummary = BalanceSummary(
    netBalance: 0,
    paymentCount: 0,
    paymentAmount: 0,
    creditCount: 0,
    creditAmount: 0,
    totalCustomers: 0,
    owingNumberOfCustomers: 0,
  );

  @override
  bool isLedgerLoading = false;

  @override
  Future<void> fetchBalanceSummary(
      {DateTime? startDate, DateTime? endDate}) async {}

  @override
  void updateBalanceSummaryFromMap(Map<String, dynamic> data) {}

  @override
  void updateCustomDateRange(
    BuildContext context,
    DateTime start,
    DateTime end,
  ) {}
}

Widget _frame(Widget child, {double textScale = 1}) => MaterialApp(
      theme: kCustomThemeData,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: Scaffold(
          body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(10), child: child))),
    );

void main() {
  final sale = CustomerActivityEntry(
      id: 'sale',
      customerId: 'customer-a',
      customerName: 'Naledi Mokoena',
      type: 'Credit',
      amount: 250,
      when: DateTime(2026, 9, 3, 9, 30));
  final payment = CustomerActivityEntry(
      id: 'payment',
      customerId: 'customer-b',
      customerName: 'Thabo Dlamini',
      type: 'Payment',
      amount: 100,
      when: DateTime(2026, 9, 4, 12, 45));

  test('activity movement keeps payments positive and transactions negative',
      () {
    expect(sale.movement, -250);
    expect(payment.movement, 100);
    expect(
        const CustomerActivityEntry(
                id: 'note',
                customerId: 'a',
                customerName: 'Naledi',
                type: 'Note',
                amount: 45)
            .movement,
        0);
  });

  testWidgets('activity groups customers and opens their ledger from details',
      (tester) async {
    CustomerActivityEntry? opened;
    await tester.pumpWidget(_frame(CustomerActivityTimeline(entries: [
      sale,
      payment,
      CustomerActivityEntry(
          id: 'payment-a',
          customerId: 'customer-a',
          customerName: 'Naledi Mokoena',
          type: 'Payment',
          amount: 50,
          when: DateTime(2026, 9, 4, 10))
    ], reportedNet: -100, onOpenCustomer: (entry) => opened = entry)));
    expect(find.text('3 entries · 2 customers'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNWidgets(2));
    expect(find.byType(Card), findsNWidgets(2));
    final avatars = tester.widgetList<ProfileImageWidget>(
      find.byType(ProfileImageWidget),
    );
    expect(avatars, hasLength(2));
    expect(avatars.every((avatar) => avatar.radius == 20), isTrue);
    expect(find.byKey(const ValueKey('customer-activity-sale')), findsNothing);
    expect(tester.getTopLeft(find.text('Naledi Mokoena')).dy,
        lessThan(tester.getTopLeft(find.text('Thabo Dlamini')).dy));
    expect(find.text(CurrencyUtil.format(-200)), findsOneWidget);
    await tester.tap(find.text('Naledi Mokoena'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('customer-activity-sale')), findsOneWidget);
    expect(find.text('−R250,00'), findsOneWidget);
    expect(find.text('+R50,00'), findsOneWidget);
    expect(
        tester
            .getTopLeft(
                find.byKey(const ValueKey('customer-activity-payment-a')))
            .dy,
        lessThan(tester
            .getTopLeft(find.byKey(const ValueKey('customer-activity-sale')))
            .dy));
    await tester.ensureVisible(find.text('Open customer ledger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open customer ledger'));
    expect(opened?.customerId, 'customer-a');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'expanded activity figures share one right edge at standard and large text sizes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entries = [
      CustomerActivityEntry(
          id: 'small-sale',
          customerId: 'customer-a',
          customerName: 'Tshepo Number',
          type: 'Credit',
          amount: 10,
          when: DateTime(2026, 8, 15, 0, 27)),
      CustomerActivityEntry(
          id: 'large-sale',
          customerId: 'customer-a',
          customerName: 'Tshepo Number',
          type: 'Credit',
          amount: 200,
          when: DateTime(2026, 8, 14, 17, 43)),
      CustomerActivityEntry(
          id: 'payment',
          customerId: 'customer-a',
          customerName: 'Tshepo Number',
          type: 'Payment',
          amount: 1,
          when: DateTime(2026, 8, 13, 9)),
    ];
    const amountKeys = [
      'customer-activity-amount-small-sale',
      'customer-activity-amount-large-sale',
      'customer-activity-amount-payment',
      'customer-activity-total-transactions',
      'customer-activity-total-payments',
      'customer-activity-total-net-movement',
    ];

    Future<void> expectAlignedFigures(double textScale) async {
      await tester.pumpWidget(_frame(
        CustomerActivityTimeline(
            key: ValueKey('activity-figures-$textScale'),
            entries: entries,
            onOpenCustomer: (_) {}),
        textScale: textScale,
      ));
      await tester.tap(find.text('Tshepo Number'));
      await tester.pumpAndSettle();

      final rightEdges = amountKeys
          .map((key) => tester.getRect(find.byKey(ValueKey(key))).right)
          .toList();
      for (final edge in rightEdges.skip(1)) {
        expect(edge, closeTo(rightEdges.first, .01));
      }
      expect(find.text('−R10,00'), findsOneWidget);
      expect(find.text('−R200,00'), findsOneWidget);
      expect(find.text('+R1,00'), findsOneWidget);
      expect(find.text('R210,00'), findsOneWidget);
      expect(find.text('R1,00'), findsOneWidget);
      expect(find.text('-R209,00'), findsNWidgets(2));
      expect(rightEdges.first, lessThanOrEqualTo(390));
      expect(tester.takeException(), isNull);
    }

    await expectAlignedFigures(1);
    await expectAlignedFigures(2);
  });

  testWidgets('320px activity retains long names and full amounts at 200%',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var openings = 0;
    await tester.pumpWidget(_frame(
        Column(children: [
          const CustomerActivitySummary(
              netMovement: -1234567.89,
              salesAmount: 2234567.89,
              salesCount: 104,
              paymentsAmount: 1000000,
              paymentsCount: 26),
          CustomerActivityTimeline(entries: [
            CustomerActivityEntry(
                id: 'long-name',
                customerId: 'customer-a',
                customerName: 'A Customer With A Very Long Surname Mokoena',
                type: 'Credit',
                amount: 2234567.89,
                when: DateTime(2026, 9, 4, 12, 45))
          ], onOpenCustomer: (_) => openings++),
        ]),
        textScale: 2));
    await tester.pumpAndSettle();
    expect(find.text('Sales · 104'), findsOneWidget);
    expect(find.text('Payments · 26'), findsOneWidget);
    for (final amount in <double>[
      -1234567.89,
      2234567.89,
      1000000,
      -2234567.89
    ]) {
      final rect = tester.getRect(find.text(CurrencyUtil.format(amount)));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
    await tester.ensureVisible(
        find.text('A Customer With A Very Long Surname Mokoena'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A Customer With A Very Long Surname Mokoena'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open customer ledger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open customer ledger'));
    expect(openings, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reconciliation appears only for a real mismatch',
      (tester) async {
    await tester.pumpWidget(_frame(CustomerActivityTimeline(
        entries: const [], reportedNet: 0, onOpenCustomer: (_) {})));
    expect(find.text('No activity for these dates'), findsOneWidget);
    expect(find.textContaining('Entries match'), findsNothing);
    await tester.pumpWidget(_frame(CustomerActivityTimeline(
        entries: [sale, payment], reportedNet: -125, onOpenCustomer: (_) {})));
    expect(find.text('No activity for these dates'), findsNothing);
    expect(find.textContaining('a difference of R25,00'), findsOneWidget);
  });

  testWidgets('all-time activity never mounts the per-customer query',
      (tester) async {
    final provider = _StubBalanceSummaryProvider();
    addTearDown(provider.dispose);
    var buildCount = 0;
    DateTime? receivedStart;
    DateTime? receivedEnd;
    final start = DateTime(2026, 9, 1);
    final end = DateTime(2026, 9, 6, 23, 59, 59, 999);

    Widget frameRange({DateTime? rangeStart, DateTime? rangeEnd}) {
      return ChangeNotifierProvider<BalanceSummaryProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: CustomerActivityRangeContent(
              startDate: rangeStart,
              endDate: rangeEnd,
              drilldownBuilder: (actualStart, actualEnd, _) {
                buildCount++;
                receivedStart = actualStart;
                receivedEnd = actualEnd;
                return const SizedBox(
                  key: ValueKey('customer-activity-query'),
                );
              },
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(frameRange());
    expect(buildCount, 0);
    expect(find.byKey(const ValueKey('customer-activity-query')), findsNothing);
    expect(find.text('Net movement'), findsOneWidget);

    // A half-open selection is invalid too; both bounds must be explicit.
    await tester.pumpWidget(frameRange(rangeStart: start));
    expect(buildCount, 0);
    expect(find.byKey(const ValueKey('customer-activity-query')), findsNothing);

    await tester.pumpWidget(frameRange(rangeStart: start, rangeEnd: end));
    expect(buildCount, 1);
    expect(receivedStart, start);
    expect(receivedEnd, end);
    expect(
        find.byKey(const ValueKey('customer-activity-query')), findsOneWidget);

    // This is the state produced by selecting "Show all time".
    await tester.pumpWidget(frameRange());
    expect(buildCount, 1);
    expect(find.byKey(const ValueKey('customer-activity-query')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'customer paging preserves all totals and resets only on changed data',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    List<CustomerActivityEntry> entries({double lastAmount = 1}) =>
        List.generate(
            63,
            (index) => CustomerActivityEntry(
                id: 'entry-$index',
                customerId: 'customer-${index.toString().padLeft(2, '0')}',
                customerName: 'Customer $index',
                type: 'Payment',
                amount: index == 62 ? lastAmount : 1,
                when: DateTime(2026, 9, 4)));
    Widget timeline({double lastAmount = 1}) => _frame(
        CustomerActivityTimeline(
            entries: entries(lastAmount: lastAmount),
            reportedNet: 62 + lastAmount,
            onOpenCustomer: (_) {}),
        textScale: 2);
    await tester.pumpWidget(timeline());
    expect(find.text('63 entries · 63 customers'), findsOneWidget);
    expect(find.text('Showing 50 of 63 customers'), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-activity-group-customer-50')),
        findsNothing);
    await tester.ensureVisible(
        find.byKey(const ValueKey('customer-activity-show-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('customer-activity-show-more')));
    await tester.pumpAndSettle();
    expect(find.text('Showing 63 of 63 customers'), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-activity-group-customer-62')),
        findsOneWidget);
    await tester.pumpWidget(timeline());
    expect(find.text('Showing 63 of 63 customers'), findsOneWidget);
    await tester.pumpWidget(timeline(lastAmount: 3));
    expect(find.text('Showing 50 of 63 customers'), findsOneWidget);
    expect(find.textContaining('a difference of'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
