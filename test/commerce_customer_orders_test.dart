import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/commerce/commerce_order.dart';
import 'package:pasella/pages/ecommerce/orders_management/data/orders_controller.dart';
import 'package:pasella/pages/ecommerce/orders_management/data/order_filters.dart';
import 'package:pasella/pages/ecommerce/orders_management/data/orders_repository.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';
import 'package:pasella/services/commerce_service.dart';

class _OrdersRepositoryStub implements OrdersRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
    expect(model.status, 'preparing');
    expect(model.paymentStatus, 'paid');
    expect(computeStatus(model), OrderStatus.preparing);
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

  test('a supplier-order stream failure never resolves to no orders', () {
    expect(
      resolveOrdersTruthSurface(
        legacyLoading: false,
        commerceLoading: false,
        legacyError: null,
        commerceError: StateError('offline'),
        hasOrders: false,
      ),
      OrdersTruthSurface.error,
    );
  });

  test('cached supplier-order snapshots remain provisional without flicker',
      () {
    const snapshot = CommerceOrdersSnapshot(orders: [], isFromCache: true);
    expect(snapshot.isAuthoritative, isFalse);

    final controller = OrdersController(
      repository: _OrdersRepositoryStub(),
      customerId: 'customer-1',
    );
    addTearDown(controller.dispose);

    controller.beginCommerceLoad();
    controller.setCommerceOrders(
      snapshot.orders,
      isFromCache: snapshot.isFromCache,
    );

    expect(controller.commerceLoading, isTrue);
    expect(controller.commerceError, isNull);
    expect(controller.truthSurface, OrdersTruthSurface.loading);

    controller.setCommerceOrders(const [], isFromCache: false);
    expect(controller.commerceLoading, isFalse);
    expect(controller.truthSurface, OrdersTruthSurface.empty);
  });

  test('an empty cached snapshot fails after bounded verification', () async {
    final controller = OrdersController(
      repository: _OrdersRepositoryStub(),
      customerId: 'customer-1',
      commerceVerificationTimeout: const Duration(milliseconds: 5),
    );
    addTearDown(controller.dispose);

    controller.beginCommerceLoad();
    controller.setCommerceOrders(const [], isFromCache: true);
    await Future<void>.delayed(const Duration(milliseconds: 15));

    expect(controller.commerceLoading, isFalse);
    expect(controller.commerceError, isA<CommerceOrdersCacheUnverified>());
    expect(controller.truthSurface, OrdersTruthSurface.error);
  });

  test('loaded orders remain visible when one source is temporarily down', () {
    expect(
      resolveOrdersTruthSurface(
        legacyLoading: false,
        commerceLoading: false,
        legacyError: StateError('callable unavailable'),
        commerceError: null,
        hasOrders: true,
      ),
      OrdersTruthSurface.content,
    );
  });
}
