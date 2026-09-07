import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/pages/sales/widgets/sales_list.dart';
import 'package:pasella/pages/sales/widgets/sales_stats_card.dart';
import 'package:pasella/utils/currency_util.dart';

Widget _screen(Widget child,
        {double textScale = 1,
        double bottomSafeArea = 0,
        double keyboardInset = 0}) =>
    MaterialApp(
      theme: kCustomThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          padding:
              EdgeInsets.only(bottom: keyboardInset == 0 ? bottomSafeArea : 0),
          viewPadding: EdgeInsets.only(bottom: bottomSafeArea),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: child!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  setUpAll(() async {
    final fonts = FontLoader('SpazaSans')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await fonts.load();
  });

  testWidgets('sales from older years show a year and all dates announce it',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final currentYear = DateTime.now().year;
    await tester.pumpWidget(_screen(Column(
      children: [
        for (final year in [currentYear, currentYear - 1])
          RecordedSaleTile(
            sale: Sale(
              id: 'sale-$year',
              amount: 100,
              type: 'Cash',
              products: const {},
              dateAdded: DateTime(year, 9, 4, 15, 30),
            ),
            onTap: () {},
          ),
      ],
    )));
    expect(find.textContaining('${currentYear - 1}'), findsOneWidget);
    expect(find.textContaining('$currentYear'), findsNothing);
    expect(
        find.bySemanticsLabel(RegExp('$currentYear at 15:30')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('${currentYear - 1} at 15:30')),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets('record action stays visible while extra figures open in details',
      (tester) async {
    var recordings = 0;
    await tester.pumpWidget(_screen(SalesSummaryCard(
      sales: 3800,
      stockAmount: 1200,
      cost: 1900,
      profit: 1900,
      entryCount: 4,
      selectedDay: DateTime(2026, 9, 4),
      onRecordSale: () => recordings++,
    )));

    expect(find.text(CurrencyUtil.format(3800)), findsOneWidget);
    expect(find.text('4 entries'), findsOneWidget);
    expect(find.text('Difference'), findsNothing);
    expect(find.text('Itemized product profit'), findsNothing);

    await tester.tap(find.text('Record sale'));
    expect(recordings, 1);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(find.text('Sales details'), findsOneWidget);
    expect(find.text('Sep 4, 2026'), findsOneWidget);
    expect(find.text(CurrencyUtil.format(2600)), findsOneWidget);
    expect(find.textContaining('It is not profit'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Profit margin'),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('sales-details-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('50.0%'), findsOneWidget);
    await tester.tap(find.byTooltip('Close sales details'));
    await tester.pumpAndSettle();
    expect(find.text('Sales details'), findsNothing);
  });

  testWidgets('all detail figures remain reachable at 320px with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_screen(
      SalesSummaryCard(
        sales: 3800,
        stockAmount: 1200,
        cost: 1900,
        profit: 1900,
        entryCount: 4,
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 9, 4),
        onRecordSale: () {},
      ),
      textScale: 2,
    ));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Details'));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Number of entries'),
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('sales-details-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Number of entries').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close sales details'));
    await tester.pumpAndSettle();
    expect(find.text('Sales details'), findsNothing);
  });

  testWidgets('zero sales never renders a non-finite margin', (tester) async {
    await tester.pumpWidget(_screen(const SalesSummaryCard(
      sales: 0,
      stockAmount: 300,
      cost: 0,
      profit: 0,
      entryCount: 1,
    )));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Profit margin'), findsNothing);
    expect(find.text('NaN%'), findsNothing);
    expect(find.text(CurrencyUtil.format(-300)), findsOneWidget);
    expect(find.text('All dates'), findsOneWidget);
  });

  for (final keyboardInset in [0.0, 240.0]) {
    testWidgets(
        'sales drawer last value clears system navigation and keyboard ($keyboardInset)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const bottomSafeArea = 48.0;
      await tester.pumpWidget(_screen(
        SalesSummaryCard(
          sales: 3800,
          stockAmount: 1200,
          cost: 1900,
          profit: 1900,
          entryCount: 4,
          startDate: DateTime(2025, 8, 1),
          endDate: DateTime(2026, 9, 4),
        ),
        textScale: 2,
        bottomSafeArea: bottomSafeArea,
        keyboardInset: keyboardInset,
      ));
      await tester.ensureVisible(find.text('Details'));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final drawer = find.byKey(const ValueKey('sales-details-scroll'));
      final scrollable = find.descendant(
        of: drawer,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(find.text('4'), 160,
          scrollable: scrollable);
      await tester.drag(drawer, const Offset(0, -600));
      await tester.pumpAndSettle();
      final visibleBottom =
          568 - (keyboardInset == 0 ? bottomSafeArea : keyboardInset);
      expect(tester.getBottomRight(find.text('4')).dy,
          lessThanOrEqualTo(visibleBottom));
      expect(
          tester.getBottomRight(drawer).dy, lessThanOrEqualTo(visibleBottom));
      expect(find.text('4').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close sales details'));
      await tester.pumpAndSettle();
      expect(find.text('Sales details'), findsNothing);
    });
  }

  testWidgets(
      'sales actions and all details remain reachable in short landscape',
      (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var recordings = 0;
    await tester.pumpWidget(_screen(
      SalesSummaryCard(
        sales: 3800,
        stockAmount: 4600,
        cost: 1900,
        profit: 1900,
        entryCount: 4,
        startDate: DateTime(2025, 8, 1),
        endDate: DateTime(2026, 9, 4),
        onRecordSale: () => recordings++,
      ),
      textScale: 2,
    ));
    await tester.ensureVisible(find.text('Record sale'));
    await tester.tap(find.text('Record sale'));
    expect(recordings, 1);
    await tester.ensureVisible(find.text('Details'));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(CurrencyUtil.format(-800)), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Number of entries'),
      100,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('sales-details-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Number of entries').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Close sales details'));
    await tester.pumpAndSettle();
    expect(find.text('Sales details'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large sales amounts stay fully within a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const amount = 123456789.99;
    await tester.pumpWidget(_screen(
      Column(
        children: [
          const SalesSummaryCard(
            sales: amount,
            stockAmount: 0,
            cost: 0,
            profit: 0,
            entryCount: 1,
          ),
          RecordedSaleTile(
            sale: Sale(
              id: 'large-sale',
              amount: amount,
              type: 'Cash',
              products: const {},
              dateAdded: DateTime(2026, 9, 4),
            ),
            onTap: () {},
          ),
        ],
      ),
      textScale: 2,
    ));
    final values = find.text(CurrencyUtil.format(amount));
    expect(values, findsNWidgets(2));
    for (final element in values.evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('sale entry exposes both amounts and opens at large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    var openings = 0;
    final sale = Sale(
      id: 'sale-preview',
      amount: 2450,
      stockAmount: 870,
      type: 'Cash',
      products: const {},
      dateAdded: DateTime(2026, 9, 4, 15, 30),
    );
    await tester.pumpWidget(_screen(
      RecordedSaleTile(sale: sale, onTap: () => openings++),
      textScale: 2,
    ));
    expect(find.text('Fri, 4 Sep'), findsOneWidget);
    expect(find.text('15:30'), findsOneWidget);
    expect(find.text(CurrencyUtil.format(2450)), findsOneWidget);
    expect(
        find.text('Stock bought ${CurrencyUtil.format(870)}'), findsOneWidget);
    expect(
        find.bySemanticsLabel(RegExp('Sales .*Stock bought')), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel(RegExp('Sales .*Stock bought')))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(CurrencyUtil.format(2450)));
    expect(openings, 1);
    semantics.dispose();
  });

  testWidgets('sale entry values and chevrons hold a consistent right column',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final year = DateTime.now().year;
    final sales = [
      Sale(
        id: 'short-value',
        amount: 1,
        stockAmount: 0,
        type: 'Cash',
        products: const {},
        dateAdded: DateTime(year, 9, 4, 12, 15),
      ),
      Sale(
        id: 'long-value',
        amount: 10000,
        stockAmount: 1,
        type: 'Cash',
        products: const {},
        dateAdded: DateTime(year, 9, 5, 10, 52),
      ),
    ];

    await tester.pumpWidget(_screen(Column(
      children: [
        for (final sale in sales) RecordedSaleTile(sale: sale, onTap: () {}),
      ],
    )));

    double paintedRightEdge(String text) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      final localRight = boxes
          .map((box) => box.right)
          .reduce((left, right) => left > right ? left : right);
      return paragraph.localToGlobal(Offset(localRight, 0)).dx;
    }

    final amountEdges = sales
        .map((sale) => paintedRightEdge(CurrencyUtil.format(sale.amount)))
        .toList();
    final stockEdges = sales
        .map((sale) => paintedRightEdge(
              'Stock bought ${CurrencyUtil.format(sale.stockAmount)}',
            ))
        .toList();
    final chevrons = find.byIcon(Icons.chevron_right_rounded);
    final chevronEdges = [
      for (var index = 0; index < sales.length; index++)
        tester.getTopLeft(chevrons.at(index)).dx,
    ];
    double baselineOf(String text) {
      final paragraph = tester.renderObject<RenderBox>(find.text(text));
      final localBaseline = paragraph.getDryBaseline(
          paragraph.constraints, TextBaseline.alphabetic)!;
      return paragraph.localToGlobal(Offset(0, localBaseline)).dy;
    }

    expect(amountEdges[0], closeTo(amountEdges[1], .01));
    expect(stockEdges[0], closeTo(stockEdges[1], .01));
    expect(chevronEdges[0], closeTo(chevronEdges[1], .01));
    for (var index = 0; index < sales.length; index++) {
      // Different font sizes can leave a fractional-pixel difference in their
      // final glyph side bearings even when both paragraphs are right-aligned.
      expect(amountEdges[index], closeTo(stockEdges[index], .5));
      expect(
        baselineOf(DateFormat('EEE, d MMM').format(sales[index].dateAdded)),
        closeTo(baselineOf(CurrencyUtil.format(sales[index].amount)), .01),
      );
      expect(
        baselineOf(DateFormat('HH:mm').format(sales[index].dateAdded)),
        closeTo(
          baselineOf(
            'Stock bought ${CurrencyUtil.format(sales[index].stockAmount)}',
          ),
          .01,
        ),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('sale entry stacks before a financial value would be truncated',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sale = Sale(
      id: 'very-large-values',
      amount: 123456789012.99,
      stockAmount: 9876543210.87,
      type: 'Cash',
      products: const {},
      dateAdded: DateTime(DateTime.now().year, 9, 4, 12, 15),
    );
    final amount = CurrencyUtil.format(sale.amount);
    final stock = 'Stock bought ${CurrencyUtil.format(sale.stockAmount)}';

    await tester.pumpWidget(_screen(
      RecordedSaleTile(sale: sale, onTap: () {}),
    ));

    expect(find.text(amount), findsOneWidget);
    expect(find.text(stock), findsOneWidget);
    expect(tester.widget<Text>(find.text(amount)).overflow,
        isNot(TextOverflow.ellipsis));
    expect(tester.widget<Text>(find.text(stock)).overflow,
        isNot(TextOverflow.ellipsis));
    expect(
      tester.getTopLeft(find.text(amount)).dy,
      greaterThan(tester.getBottomLeft(find.text('12:15')).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
