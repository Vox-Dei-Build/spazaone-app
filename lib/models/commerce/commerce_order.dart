import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/models/orders/canonical_order_status.dart';

class CommerceOrder {
  const CommerceOrder({
    required this.id,
    required this.sellerId,
    required this.customerId,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.buyerPaymentPreference,
    required this.buyerName,
    required this.buyerPhone,
    required this.productTitle,
    required this.image,
    required this.amountDueMinor,
    required this.baseCostMinor,
    required this.feeMinor,
    required this.marginMinor,
    required this.deliveryAddress,
    required this.createdAt,
    required this.supplierId,
    required this.supplierProductId,
    required this.supplierVariantId,
    required this.supplierSku,
    required this.supplierProductCostMinor,
    required this.supplierShippingCostMinor,
    required this.logisticName,
    required this.logisticAging,
    required this.supplierOrderId,
    this.quantity = 1,
    this.paymentChannel = '',
    this.trackingCarrier,
    this.trackingNumber,
    this.trackingUrl,
  });

  final String id;
  final String sellerId;
  final String customerId;
  final String status;
  final String paymentStatus;
  final String paymentMethod;
  final String buyerPaymentPreference;
  final String buyerName;
  final String buyerPhone;
  final String productTitle;
  final String image;
  final int amountDueMinor;
  final int baseCostMinor;
  final int feeMinor;
  final int marginMinor;
  final Map<String, dynamic> deliveryAddress;
  final DateTime? createdAt;
  final String supplierId;
  final String supplierProductId;
  final String supplierVariantId;
  final String supplierSku;
  final int supplierProductCostMinor;
  final int supplierShippingCostMinor;
  final String logisticName;
  final String logisticAging;
  final String supplierOrderId;
  final int quantity;
  final String paymentChannel;
  final String? trackingCarrier;
  final String? trackingNumber;
  final String? trackingUrl;

  CanonicalOrderStatus get canonicalStatus =>
      canonicalOrderStatus(status, paymentStatus: paymentStatus);

  static int _minor(Object? value) => value is num ? value.toInt() : 0;

  factory CommerceOrder.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final buyer = Map<String, dynamic>.from(data['buyer'] as Map? ?? const {});
    final items = data['lineItems'] as List? ?? const [];
    final item = items.isNotEmpty
        ? Map<String, dynamic>.from(items.first as Map)
        : const <String, dynamic>{};
    final tracking = Map<String, dynamic>.from(
      data['tracking'] as Map? ?? const {},
    );
    final supplierOrder = Map<String, dynamic>.from(
      data['supplierOrder'] as Map? ?? const {},
    );
    return CommerceOrder(
      id: document.id,
      sellerId: data['sellerId']?.toString() ?? '',
      customerId: data['customerId']?.toString() ?? '',
      status: data['status']?.toString() ?? 'pending_payment',
      paymentStatus: data['paymentStatus']?.toString() ?? 'pending',
      paymentMethod: data['paymentMethod']?.toString() ?? 'paystack',
      buyerPaymentPreference: data['buyerPaymentPreference']?.toString() ?? '',
      buyerName: buyer['name']?.toString() ?? 'Customer',
      buyerPhone: buyer['phone']?.toString() ?? '',
      productTitle: item['title']?.toString() ?? 'Product',
      image: item['image']?.toString() ?? '',
      amountDueMinor: _minor(data['amountDueMinor']),
      baseCostMinor: _minor(data['baseCostMinor']),
      feeMinor: _minor(data['feeMinor']),
      marginMinor: _minor(data['marginMinor']),
      deliveryAddress: Map<String, dynamic>.from(
        data['deliveryAddress'] as Map? ?? const {},
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      supplierId: data['supplierId']?.toString() ?? '',
      supplierProductId: item['supplierProductId']?.toString() ?? '',
      supplierVariantId: item['supplierVariantId']?.toString() ?? '',
      supplierSku: item['supplierSku']?.toString() ?? '',
      supplierProductCostMinor: _minor(item['supplierProductCostMinor']),
      supplierShippingCostMinor: _minor(item['supplierShippingCostMinor']),
      logisticName: item['logisticName']?.toString() ?? '',
      logisticAging: item['logisticAging']?.toString() ?? '',
      supplierOrderId: supplierOrder['orderId']?.toString() ?? '',
      quantity:
          _minor(data['quantity'] ?? item['quantity']).clamp(1, 20).toInt(),
      paymentChannel: data['requestedPaymentChannel']?.toString() ??
          (data['payment'] as Map?)?['channel']?.toString() ??
          '',
      trackingCarrier: tracking['carrier']?.toString(),
      trackingNumber:
          tracking['number']?.toString() ?? data['trackingNumber']?.toString(),
      trackingUrl:
          tracking['url']?.toString() ?? data['trackingUrl']?.toString(),
    );
  }
}
