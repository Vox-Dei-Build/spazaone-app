import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/pages/sales/view_model/recorded_sales_reader.dart';
import 'package:pasella/pages/sales/widgets/sales_list.dart';
import 'package:pasella/pages/sales/widgets/sales_stats_card.dart';
import 'package:pasella/utils/currency_util.dart';

Sale sale(String id, double amount) => Sale(
      id: id,
      amount: amount,
      stockAmount: 400,
      type: 'Cash',
      products: const {},
      dateAdded: DateTime(2026, 9, 5),
    );

void main() {
  test(
      'a failed first read never emits a false empty result; retry keeps bounds',
      () async {
    final ranges = <(DateTime, DateTime)>[];
    final emitted = <List<Sale>>[];
    final start = DateTime(2026, 9, 1);
    final end = DateTime(2026, 9, 6);
    final reader = RecordedSalesReader(
      query: (start, end) async {
        ranges.add((start, end));
        if (ranges.length == 1) throw StateError('offline');
        return [sale('recovered', 1200)];
      },
      onLoaded: emitted.add,
    );
    addTearDown(reader.dispose);

    await reader.load(start, end);
    expect(reader.hasError, isTrue);
    expect(reader.isLoading, isFalse);
    expect(reader.hasCurrentData, isFalse);
    expect(emitted, isEmpty);

    await reader.retry();
    expect(ranges, [(start, end), (start, end)]);
    expect(reader.hasError, isFalse);
    expect(reader.hasCurrentData, isTrue);
    expect(reader.sales.single.amount, 1200);
    expect(emitted, hasLength(1));
  });

  test('refresh failure retains amounts only for the matching selected period',
      () async {
    var fail = false;
    var updates = 0;
    var total = 0.0;
    final start = DateTime(2026, 9, 5);
    final end = DateTime(2026, 9, 6);
    final reader = RecordedSalesReader(
      query: (_, __) async {
        if (fail) throw StateError('offline');
        return [sale('saved', 1200)];
      },
      onLoaded: (sales) {
        updates++;
        total = SalesStockTotals.fromSales(sales).salesAmount;
      },
    );
    addTearDown(reader.dispose);
    await reader.load(start, end);
    fail = true;
    await reader.retry();
    expect(reader.hasError, isTrue);
    expect(reader.hasCurrentData, isTrue);
    expect(total, 1200);
    expect(updates, 1);

    await reader.load(DateTime(2026, 8, 1), DateTime(2026, 9, 1));
    expect(reader.hasError, isTrue);
    expect(reader.hasCurrentData, isFalse);
    expect(reader.sales.single.id, 'saved');
    expect(total, 1200);
    expect(updates, 1);
  });

  test('an older failed request cannot replace a newer successful period',
      () async {
    final first = Completer<List<Sale>>();
    final second = Completer<List<Sale>>();
    var calls = 0;
    final emitted = <String>[];
    final reader = RecordedSalesReader(
      query: (_, __) => ++calls == 1 ? first.future : second.future,
      onLoaded: (sales) => emitted.add(sales.single.id),
    );
    addTearDown(reader.dispose);
    final older = reader.load(DateTime(2026, 8, 1), DateTime(2026, 9, 1));
    final newer = reader.load(DateTime(2026, 9, 1), DateTime(2026, 9, 6));
    second.complete([sale('newer', 600)]);
    await newer;
    first.completeError(StateError('old request failed'));
    await older;
    expect(reader.hasCurrentData, isTrue);
    expect(reader.hasError, isFalse);
    expect(reader.sales.single.id, 'newer');
    expect(emitted, ['newer']);
  });

  test(
      'a verified empty response replaces old data; disposal ignores late reads',
      () async {
    final pending = Completer<List<Sale>>();
    var calls = 0;
    var updates = 0;
    final reader = RecordedSalesReader(
      query: (_, __) {
        calls++;
        if (calls == 1) return Future.value([sale('saved', 400)]);
        if (calls == 2) return Future.value(const []);
        return pending.future;
      },
      onLoaded: (_) => updates++,
    );
    await reader.load(DateTime(2026, 9, 5), DateTime(2026, 9, 6));
    await reader.retry();
    expect(reader.hasCurrentData, isTrue);
    expect(reader.hasError, isFalse);
    expect(reader.sales, isEmpty);
    final lateRead = reader.retry();
    reader.dispose();
    pending.complete([sale('late', 800)]);
    await lateRead;
    expect(updates, 2);
  });

  testWidgets('unavailable sales summary keeps recording without false zero',
      (tester) async {
    var recordings = 0;
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: Scaffold(
        body: SalesSummaryCard(
          sales: 0,
          stockAmount: 0,
          cost: 0,
          profit: 0,
          entryCount: 0,
          hasCurrentData: false,
          onRecordSale: () => recordings++,
        ),
      ),
    ));
    expect(find.text(CurrencyUtil.format(0)), findsNothing);
    expect(find.text('0 entries'), findsNothing);
    expect(find.text('Details'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('record-sale-action')));
    expect(recordings, 1);
  });

  testWidgets('read error retry works at 320px and 200% text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var attempts = 0;
    final reader = RecordedSalesReader(
      query: (_, __) async {
        if (++attempts == 1) throw StateError('offline');
        return [sale('recovered', 600)];
      },
    );
    addTearDown(reader.dispose);
    await reader.load(DateTime(2026, 9, 1), DateTime(2026, 9, 6));
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: RecordedSalesReadError(onRetry: reader.retry),
        ),
      ),
    ));
    expect(find.text('Could not load sales for these dates.'), findsOneWidget);
    expect(find.text('No recorded sales yet'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('recorded-sales-retry')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(reader.hasCurrentData, isTrue);
    expect(tester.takeException(), isNull);
  });
}
