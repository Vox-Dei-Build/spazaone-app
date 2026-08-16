import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/commerce/commerce_order.dart';
import 'package:pasella/pages/sales/widgets/combined_online_orders.dart';
import 'package:pasella/pages/sales/widgets/online_sales_list.dart';

Future<List<LedgerSale>> _emptyOwned({
  DateTime? selectedDay,
  DateTime? startDate,
  DateTime? endDate,
}) async =>
    const [];

Widget _subject({
  Future<List<LedgerSale>> Function({
    DateTime? selectedDay,
    DateTime? startDate,
    DateTime? endDate,
  })? ownedLoader,
  Stream<List<CommerceOrder>> Function()? supplierStream,
  bool setupRequired = false,
  double textScale = 1,
  VoidCallback? onOrderOptions,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: CombinedOnlineOrders(
          selectedDay: null,
          startDate: null,
          endDate: null,
          onDaySelect: (_) {},
          onRangeSelect: (_, __) {},
          onClearDates: () {},
          onSetup: () {},
          onShareShop: () {},
          onOrderOptions: onOrderOptions,
          setupRequired: setupRequired,
          ownedLoader: ownedLoader ?? _emptyOwned,
          supplierStream:
              supplierStream ?? () => Stream.value(const <CommerceOrder>[]),
        ),
      ),
    ),
  );
}

CommerceOrder _supplierOrder() => CommerceOrder(
      id: 'supplier-order-1',
      sellerId: 'store-1',
      customerId: 'customer-1',
      status: 'preparing',
      paymentStatus: 'paid',
      paymentMethod: 'paystack',
      buyerPaymentPreference: 'online',
      buyerName: 'Lerato',
      buyerPhone: '27820000000',
      productTitle: 'School backpack',
      image: '',
      amountDueMinor: 25900,
      baseCostMinor: 20000,
      feeMinor: 900,
      marginMinor: 5000,
      deliveryAddress: const {},
      createdAt: DateTime(2026, 8, 14, 7, 30),
      supplierId: 'cj',
      supplierProductId: 'product-1',
      supplierVariantId: 'variant-1',
      supplierSku: 'SKU-1',
      supplierProductCostMinor: 17000,
      supplierShippingCostMinor: 3000,
      logisticName: 'Courier',
      logisticAging: '3-5 days',
      supplierOrderId: 'CJ-1',
    );

void main() {
  testWidgets('order options is a compact header action', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _subject(onOrderOptions: () => taps++),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('online-orders-order-options')),
      findsOneWidget,
    );
    expect(find.text('Order options'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('online-orders-order-options')),
    );
    expect(taps, 1);
  });

  testWidgets('shows shimmer until both empty order sources resolve',
      (tester) async {
    final owned = Completer<List<LedgerSale>>();
    final supplier = StreamController<List<CommerceOrder>>();
    addTearDown(supplier.close);

    await tester.pumpWidget(
      _subject(
        ownedLoader: ({selectedDay, startDate, endDate}) => owned.future,
        supplierStream: () => supplier.stream,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('online-orders-loading-shimmer')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    owned.complete(const <LedgerSale>[]);
    supplier.add(const <CommerceOrder>[]);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('online-orders-loading-shimmer')),
      findsNothing,
    );
    expect(find.text('No online orders yet'), findsOneWidget);
  });

  testWidgets('online empty state is compact and overflow-safe',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_subject(textScale: 1.8));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Online orders'), findsOneWidget);
    expect(
      find.text('Your stock and supplier-delivered orders'),
      findsOneWidget,
    );
    expect(find.text('No online orders yet'), findsOneWidget);
    expect(find.text('Share shop link'), findsOneWidget);
    expect(find.text('Online commerce'), findsNothing);
    expect(find.text('Supplier-delivered products'), findsNothing);
    expect(find.text('Owned orders'), findsNothing);
    expect(find.text('Supplier orders'), findsNothing);
  });

  testWidgets('shows a pending owned online order at its order total',
      (tester) async {
    Future<List<LedgerSale>> owned({
      DateTime? selectedDay,
      DateTime? startDate,
      DateTime? endDate,
    }) async =>
        [
          LedgerSale.fromMap({
            'id': 'owned-pending-1',
            'reference': 'OWN-PENDING-1',
            'status': 'pending_payment',
            'paymentStatus': 'pending',
            'itemsCount': 1,
            'orderTotal': 140.0,
            'amountPaid': 0.0,
            'createdAt': '2026-08-15T01:37:00Z',
          }),
        ];

    await tester.pumpWidget(_subject(ownedLoader: owned));
    await tester.pumpAndSettle();

    expect(find.text('Your stock'), findsOneWidget);
    expect(find.text('Awaiting payment'), findsAtLeastNWidgets(1));
    expect(find.text('R140,00'), findsOneWidget);
  });

  testWidgets('combines owned and supplier orders with quiet source labels',
      (tester) async {
    Future<List<LedgerSale>> owned({
      DateTime? selectedDay,
      DateTime? startDate,
      DateTime? endDate,
    }) async =>
        [
          LedgerSale.fromMap({
            'id': 'owned-order-1',
            'reference': 'OWN-1',
            'status': 'paid',
            'itemsCount': 2,
            'amountPaid': 150.0,
            'createdAt': '2026-08-14T06:00:00Z',
          }),
        ];

    await tester.pumpWidget(
      _subject(
        ownedLoader: owned,
        supplierStream: () => Stream.value([_supplierOrder()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Your stock'), findsOneWidget);
    expect(find.textContaining('Supplier product'), findsOneWidget);
    expect(find.text('School backpack'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('status is visible while source and date use one sheet',
      (tester) async {
    await tester.pumpWidget(_subject());
    await tester.pumpAndSettle();

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Awaiting payment'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('online-order-status-filters')),
      findsOneWidget,
    );

    await tester.tap(find.text('Source and date'));
    await tester.pumpAndSettle();

    expect(find.text('More order filters'), findsOneWidget);
    expect(find.text('Order source'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Supplier products'), findsOneWidget);
    expect(find.text('Show orders'), findsOneWidget);
  });

  testWidgets('blocked empty state has one setup action', (tester) async {
    await tester.pumpWidget(_subject(setupRequired: true));
    await tester.pumpAndSettle();

    expect(find.text('Finish setup'), findsOneWidget);
    expect(find.text('Finish setting up online selling'), findsNothing);
  });
}
