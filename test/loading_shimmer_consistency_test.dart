import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/sales/widgets/sales_list.dart';
import 'package:pasella/pages/sales/widgets/sales_stats_card.dart';
import 'package:pasella/pages/stock/product_group_page/widgets/product_list.dart';
import 'package:pasella/pages/transactions/transactions_management/transactions_management.dart';
import 'package:pasella/shared/widgets/spaza_shimmer.dart';
import 'package:shimmer/shimmer.dart';

Widget _screen(
  Widget child, {
  double textScale = 1,
  bool disableAnimations = false,
}) =>
    MaterialApp(
      theme: kCustomThemeData,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(320, 568),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(body: child),
      ),
    );

void _useNarrowView(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('shared shimmer has one accessible loading announcement',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _screen(
        const SpazaShimmer(
          semanticsLabel: 'Loading example content',
          child: SpazaSkeletonBox(height: 40, width: 120),
        ),
      ),
    );

    expect(find.byType(Shimmer), findsOneWidget);
    expect(
      find.bySemanticsLabel('Loading example content'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('shared shimmer becomes static when animations are disabled',
      (tester) async {
    await tester.pumpWidget(
      _screen(
        const SpazaShimmer(
          semanticsLabel: 'Loading example content',
          child: SpazaSkeletonBox(height: 40, width: 120),
        ),
        disableAnimations: true,
      ),
    );

    expect(find.byType(SpazaShimmer), findsOneWidget);
    expect(find.byType(Shimmer), findsNothing);
  });

  testWidgets('recorded sales shimmer is safe at 320px and large text',
      (tester) async {
    _useNarrowView(tester);
    await tester.pumpWidget(
      _screen(
        const RecordedSalesListSkeleton(itemCount: 3),
        textScale: 2,
      ),
    );

    expect(
      find.byKey(const ValueKey('recorded-sales-loading-shimmer')),
      findsOneWidget,
    );
    expect(find.text('Entries'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recorded summary shimmers while record action stays usable',
      (tester) async {
    _useNarrowView(tester);
    var taps = 0;
    await tester.pumpWidget(
      _screen(
        SalesSummaryCard(
          sales: 0,
          stockAmount: 0,
          cost: 0,
          profit: 0,
          entryCount: 0,
          hasCurrentData: false,
          isLoading: true,
          onRecordSale: () => taps++,
        ),
        textScale: 2,
      ),
    );

    expect(
      find.byKey(const ValueKey('recorded-sales-summary-loading')),
      findsOneWidget,
    );
    expect(find.text('Total sales'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byKey(const ValueKey('record-sale-action')));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product and transaction skeletons stay safe at large text',
      (tester) async {
    _useNarrowView(tester);
    await tester.pumpWidget(
      _screen(
        const ProductCatalogueSkeleton(itemCount: 2),
        textScale: 2,
      ),
    );
    expect(
      find.byKey(const ValueKey('product-catalogue-loading-shimmer')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _screen(
        const TransactionListSkeleton(itemCount: 2),
        textScale: 2,
      ),
    );
    expect(
      find.byKey(const ValueKey('transaction-list-loading-shimmer')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared list and detail loaders are accessible on narrow screens',
      (tester) async {
    _useNarrowView(tester);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _screen(
        const SpazaListSkeleton(
          semanticsLabel: 'Loading customer records',
          itemCount: 3,
        ),
        textScale: 2,
      ),
    );

    expect(find.byKey(const ValueKey('spaza-list-loading-shimmer')),
        findsOneWidget);
    expect(find.bySemanticsLabel('Loading customer records'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _screen(
        const SpazaDetailSkeleton(
          semanticsLabel: 'Loading payment details',
        ),
        textScale: 2,
      ),
    );

    expect(find.byKey(const ValueKey('spaza-detail-loading-shimmer')),
        findsOneWidget);
    expect(find.bySemanticsLabel('Loading payment details'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
