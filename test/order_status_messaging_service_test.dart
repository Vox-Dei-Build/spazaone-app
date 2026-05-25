import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/order_status_messaging_service.dart';

void main() {
  group('OrderStatusMessagingService variables', () {
    test('accept order maps total due to amount, not fulfillment copy', () {
      final vars = OrderStatusMessagingService.variablesForActionForTest(
        action: 'ACCEPT_ORDER',
        customerName: 'Tsepo Number',
        merchantDisplayName: 'Koekie Food Security',
        orderId: 'order-123',
        amount: 'R15 000,00',
        pickupLocation: 'Collection',
      );

      expect(vars['1'], 'Koekie Food Security');
      expect(vars['2'], 'order-123');
      expect(vars['3'], 'R15 000,00');
      expect(vars['4'], 'Collection');
      expect(vars['pickupLocation'], 'Collection');
    });

    test('assign driver maps greeting, driver, order and phone correctly', () {
      final vars = OrderStatusMessagingService.variablesForActionForTest(
        action: 'ASSIGN_DRIVER',
        customerName: 'Tsepo Number',
        merchantDisplayName: 'Koekie Food Security',
        orderId: 'PeFVtG5A39vRj3z8q0wz',
        driverName: 'TestDriver',
        driverPhone: '0821234567',
      );

      expect(vars['1'], 'Tsepo Number');
      expect(vars['2'], 'PeFVtG5A39vRj3z8q0wz');
      expect(vars['3'], 'Koekie Food Security');
      expect(vars['4'], 'TestDriver');
      expect(vars['5'], '0821234567');
    });

    test('out for delivery maps customer, order, shop, driver and phone', () {
      final vars = OrderStatusMessagingService.variablesForActionForTest(
        action: 'MARK_OUT_FOR_DELIVERY',
        customerName: 'Tsepo Number',
        merchantDisplayName: 'Koekie Food Security',
        orderId: 'PeFVtG5A39vRj3z8q0wz',
        driverName: 'TestDriver',
        driverPhone: '0821234567',
      );

      expect(vars['1'], 'Tsepo Number');
      expect(vars['2'], 'PeFVtG5A39vRj3z8q0wz');
      expect(vars['3'], 'Koekie Food Security');
      expect(vars['4'], 'TestDriver');
      expect(vars['5'], '0821234567');
    });

    test('delivered maps customer, order and shop', () {
      final vars = OrderStatusMessagingService.variablesForActionForTest(
        action: 'MARK_DELIVERED',
        customerName: 'Tsepo Number',
        merchantDisplayName: 'Koekie Food Security',
        orderId: 'PeFVtG5A39vRj3z8q0wz',
      );

      expect(vars['1'], 'Tsepo Number');
      expect(vars['2'], 'PeFVtG5A39vRj3z8q0wz');
      expect(vars['3'], 'Koekie Food Security');
    });

    test('reject order maps customer, shop, order and reason in slot order', () {
      // Twilio template body:
      //   Hi {{1}}, {{2}} could not accept order {{3}}. Reason: {{4}}...
      final vars = OrderStatusMessagingService.variablesForActionForTest(
        action: 'REJECT_ORDER',
        customerName: 'Tsepo Number',
        merchantDisplayName: 'Koekie Food Security',
        orderId: 'ORD-143',
        rejectionReason: 'Out of stock',
      );

      expect(vars['1'], 'Tsepo Number');
      expect(vars['2'], 'Koekie Food Security');
      expect(vars['3'], 'ORD-143');
      expect(vars['4'], 'Out of stock');
    });

    test('reject order falls back to generic reason when none supplied', () {
      final vars = OrderStatusMessagingService.variablesForActionForTest(
        action: 'REJECT_ORDER',
        customerName: 'Tsepo Number',
        merchantDisplayName: 'Koekie Food Security',
        orderId: 'ORD-143',
      );

      expect(vars['4'], 'Unavailable right now');
    });

    test('reject order uses defaults when customer or shop name missing', () {
      final vars = OrderStatusMessagingService.variablesForActionForTest(
        action: 'REJECT_ORDER',
        customerName: '',
        merchantDisplayName: '',
        orderId: 'ORD-143',
        rejectionReason: 'Closed today',
      );

      expect(vars['1'], 'customer');
      expect(vars['2'], 'the shop');
      expect(vars['3'], 'ORD-143');
      expect(vars['4'], 'Closed today');
    });
  });
}
