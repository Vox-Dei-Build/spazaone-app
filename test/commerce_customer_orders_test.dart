import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/commerce/commerce_order.dart';
import 'package:pasella/pages/ecommerce/orders_management/data/orders_controller.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';

void main() {
  test('dropship order is normalized into the customer Orders list', () {
    final order = CommerceOrder(
      id: 'order-1',
      sellerId: 'seller-1',
      customerId: 'customer-1',
      status: 'submitted_for_fulfilment',
      paymentStatus: 'paid',
      paymentMethod: 'manual',
      buyerPaymentPreference: 'transfer',
      buyerName: 'Buyer',
      buyerPhone: '0820000000',
      productTitle: 'Lamp',
      image: '',
      amountDueMinor: 12345,
      baseCostMinor: 10000,
      feeMinor: 0,
      marginMinor: 2345,
      deliveryAddress: const {},
      createdAt: DateTime(2026, 8, 4),
      supplierId: 'cj_dropshipping',
      supplierProductId: 'product-1',
      supplierVariantId: 'variant-1',
      supplierSku: 'SKU-1',
      supplierProductCostMinor: 5000,
      supplierShippingCostMinor: 5000,
      logisticName: 'Supplier delivery',
      logisticAging: '12-20',
      supplierOrderId: '',
    );

    final model = commerceOrderListModel(order);

    expect(model.source, 'commerce');
    expect(model.total, 123.45);
    expect(model.status, 'submitted_for_fulfilment');
    expect(model.paymentStatus, 'paid');
  });

  test('refund and cancellation override an older paid snapshot', () {
    expect(
      resolveOrderStatus(
        status: 'refunded',
        isPaid: true,
        paymentStatus: 'paid',
      ),
      OrderStatus.refunded,
    );
    expect(
      resolveOrderStatus(
        status: 'cancelled',
        isPaid: true,
        paymentStatus: 'paid',
      ),
      OrderStatus.cancelled,
    );
  });
}
