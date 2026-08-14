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
    expect(find.text('No online orders yet'), findsOneWidget);
    expect(find.text('Share shop link'), findsOneWidget);
    expect(find.text('Online commerce'), findsNothing);
    expect(find.text('Supplier-delivered products'), findsNothing);
    expect(find.text('Owned orders'), findsNothing);
    expect(find.text('Supplier orders'), findsNothing);
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

  testWidgets('all filters live in one bottom sheet', (tester) async {
    await tester.pumpWidget(_subject());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();

    expect(find.text('Filter online orders'), findsOneWidget);
    expect(find.text('Order source'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
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
