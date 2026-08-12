import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/commerce/commerce_order.dart';
import 'package:pasella/pages/stock/dropship/commerce_orders_page.dart';
import 'package:pasella/services/commerce_service.dart';

CommerceOrder _order(
  String status, {
  String? paymentStatus,
  String? supplierOrderId,
}) =>
    CommerceOrder(
      id: 'order-12345678',
      sellerId: 'seller-1',
      customerId: 'customer-1',
      status: status,
      paymentStatus:
          paymentStatus ?? (status == 'pending_payment' ? 'pending' : 'paid'),
      paymentMethod: 'manual',
      buyerPaymentPreference: 'eft',
      buyerName: 'Naledi',
      buyerPhone: '0820000000',
      productTitle: 'Solar lamp',
      image: '',
      amountDueMinor: 25000,
      baseCostMinor: 18000,
      feeMinor: 0,
      marginMinor: 7000,
      deliveryAddress: const {
        'line1': 'Stand 12',
        'suburb': 'Ga-Molepo',
        'city': 'Polokwane',
        'province': 'Limpopo',
        'postalCode': '0727',
        'plusCode': '5G7C7H2Q+4V',
      },
      createdAt: DateTime(2026, 8, 9),
      supplierId: 'cj_dropshipping',
      supplierProductId: 'product-1',
      supplierVariantId: 'variant-1',
      supplierSku: 'SKU-1',
      supplierProductCostMinor: 12000,
      supplierShippingCostMinor: 6000,
      logisticName: 'Internal carrier',
      logisticAging: '8-14',
      supplierOrderId: supplierOrderId ??
          (status == 'submitted_for_fulfilment' ? 'CJ-123' : ''),
    );

Future<void> _open(
  WidgetTester tester,
  String status, {
  String? paymentStatus,
  String? supplierOrderId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showCommerceOrderDetails(
              context,
              _order(
                status,
                paymentStatus: paymentStatus,
                supplierOrderId: supplierOrderId,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unpaid order shows one explicit payment action', (tester) async {
    await _open(tester, 'pending_payment');

    expect(
      find.text('Confirm payment received & notify customer'),
      findsOneWidget,
    );
    expect(find.text('Place delivery order'), findsNothing);
    expect(find.textContaining('CJdropshipping'), findsNothing);
    expect(find.textContaining('SKU:'), findsNothing);
    expect(find.text('More order actions'), findsOneWidget);

    await tester.tap(find.text('More order actions'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel order'), findsOneWidget);
  });

  testWidgets('partner details appear only when the paid order can be placed',
      (tester) async {
    await _open(tester, 'paid');

    expect(find.text('Place delivery order'), findsOneWidget);
    await tester.ensureVisible(find.text('Fulfilment operations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fulfilment operations'));
    await tester.pumpAndSettle();
    expect(find.text('Place delivery order'), findsNWidgets(2));
    expect(find.text('Fulfilment partner: CJdropshipping'), findsOneWidget);
    expect(find.text('Copy all order details'), findsOneWidget);
    expect(
        find.text('Confirm payment received & notify customer'), findsNothing);

    await tester.ensureVisible(find.text('More order actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More order actions'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel and start refund'), findsOneWidget);
  });

  testWidgets('submitted order has neutral record instead of placement panel',
      (tester) async {
    await _open(tester, 'submitted_for_fulfilment');

    expect(find.text('Place delivery order'), findsNothing);
    await tester.ensureVisible(find.text('Fulfilment operations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fulfilment operations'));
    await tester.pumpAndSettle();
    expect(find.text('Fulfilment partner: CJdropshipping'), findsNothing);
    expect(find.text('Delivery order record'), findsOneWidget);
    expect(find.text('Delivery order: CJ-123'), findsOneWidget);
    expect(find.text('Add tracking'), findsOneWidget);

    await tester.ensureVisible(find.text('More order actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More order actions'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel and start refund'), findsOneWidget);
  });

  testWidgets('refund completion remains available as an overflow action',
      (tester) async {
    await _open(
      tester,
      'cancelled',
      paymentStatus: 'refund_pending',
      supplierOrderId: 'CJ-123',
    );

    expect(find.text('Place delivery order'), findsNothing);
    await tester.ensureVisible(find.text('Fulfilment operations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fulfilment operations'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery order record'), findsOneWidget);
    await tester.tap(find.text('More order actions'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm manual refund completed'), findsOneWidget);
  });

  testWidgets('tracking asks only for number and optional link',
      (tester) async {
    await _open(tester, 'submitted_for_fulfilment');
    await tester.ensureVisible(find.text('Add tracking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add tracking'));
    await tester.pumpAndSettle();

    expect(find.text('Tracking number *'), findsOneWidget);
    expect(find.text('Tracking link (optional)'), findsOneWidget);
    expect(find.text('Carrier'), findsNothing);
    expect(find.text('Save and notify customer'), findsOneWidget);
  });

  testWidgets('tracking dialog blocks an invalid tracking link',
      (tester) async {
    await _open(tester, 'submitted_for_fulfilment');
    await tester.ensureVisible(find.text('Add tracking'));
    await tester.tap(find.text('Add tracking'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tracking number *'),
      'TRACK-123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tracking link (optional)'),
      'tracking.example/TRACK-123',
    );
    await tester.tap(find.text('Save and notify customer'));
    await tester.pump();

    expect(
        find.text('Enter a valid http:// or https:// link.'), findsOneWidget);
    expect(find.text('Add delivery tracking'), findsOneWidget);
  });

  test('tracking URL validation accepts http(s) and prefers https in UI', () {
    expect(
      isValidCommerceTrackingUrl('https://tracking.example/TRACK-123'),
      isTrue,
    );
    expect(
      isValidCommerceTrackingUrl('http://tracking.example/TRACK-123'),
      isTrue,
    );
    expect(isValidCommerceTrackingUrl('ftp://tracking.example/123'), isFalse);
    expect(isValidCommerceTrackingUrl('tracking.example/123'), isFalse);
  });

  test('queued and failed notification results are represented honestly', () {
    final queued = CommerceOrderUpdateResult.fromJson(const {
      'orderId': 'order-1',
      'status': 'shipped',
      'notification': {'customer': 'queued'},
    });
    expect(queued.customerNotification, 'queued');
    expect(
      commerceOrderUpdateMessage(
        'mark_shipped',
        queued,
      ),
      'Tracking saved. Customer update is queued and will retry.',
    );
    expect(
      commerceOrderUpdateMessage(
        'mark_shipped',
        const CommerceOrderUpdateResult(
          orderId: 'order-1',
          status: 'shipped',
          customerNotification: 'failed',
        ),
      ),
      contains('notification failed'),
    );
  });
}
