import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:pasella/models/commerce/cj_supplier_product.dart';
import 'package:pasella/models/commerce/commerce_order.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _useDropshipCatalogV2 = bool.fromEnvironment(
  'DROPSHIP_CATALOG_V2',
  defaultValue: false,
);

String dropshipCallableName(String stableName, {bool? useV2}) =>
    (useV2 ?? _useDropshipCatalogV2) ? '${stableName}V2' : stableName;

class DropshipListingResult {
  const DropshipListingResult({
    required this.listingId,
    required this.sellerProductId,
    required this.checkoutUrl,
  });

  final String listingId;
  final String sellerProductId;
  final String checkoutUrl;
}

class CommerceService {
  CommerceService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _functions = functions ?? FirebaseFunctions.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  Future<CjCatalogPage> searchCjCatalog({
    String query = '',
    int page = 1,
    String cursor = '',
  }) async {
    final result = await _functions
        .httpsCallable(dropshipCallableName('searchCjSupplierCatalog'))
        .call({
      'storeId': StoreSession.instance.storeId,
      'query': query,
      'page': page,
      if (cursor.isNotEmpty) 'cursor': cursor,
    });
    return CjCatalogPage.fromJson(
        Map<String, dynamic>.from(result.data as Map));
  }

  Future<CjProductDetails> getCjProduct(
    String productId, {
    String preferredVariantId = '',
  }) async {
    final result = await _functions
        .httpsCallable(dropshipCallableName('getCjSupplierProduct'))
        .call({
      'storeId': StoreSession.instance.storeId,
      'productId': productId,
      if (preferredVariantId.isNotEmpty)
        'preferredVariantId': preferredVariantId,
    });
    return CjProductDetails.fromJson(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  Future<DropshipListingResult> createListing({
    required String supplierProductId,
    required String supplierVariantId,
    required int markupMinor,
  }) async {
    final result = await _functions
        .httpsCallable(dropshipCallableName('createDropshipListing'))
        .call({
      'storeId': StoreSession.instance.storeId,
      'supplierProductId': supplierProductId,
      'supplierVariantId': supplierVariantId,
      'markupMinor': markupMinor,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return DropshipListingResult(
      listingId: data['listingId']?.toString() ?? '',
      sellerProductId: data['sellerProductId']?.toString() ?? '',
      checkoutUrl: data['checkoutUrl']?.toString() ?? '',
    );
  }

  Stream<List<CommerceOrder>> watchOrders({
    String? customerId,
    String? customerPhone,
  }) {
    final sellerId = StoreSession.instance.storeId;
    if (sellerId.isEmpty) return const Stream.empty();
    final wantedCustomerId = customerId?.trim() ?? '';
    final wantedPhone = normalizePhoneNumber(customerPhone);
    return _firestore
        .collection('commerceOrders')
        .where('sellerId', isEqualTo: sellerId)
        .snapshots()
        .map((snapshot) {
      final orders =
          snapshot.docs.map(CommerceOrder.fromDocument).where((order) {
        if (wantedCustomerId.isEmpty && wantedPhone.isEmpty) return true;
        if (wantedCustomerId.isNotEmpty &&
            order.customerId == wantedCustomerId) {
          return true;
        }
        return wantedPhone.isNotEmpty &&
            normalizePhoneNumber(order.buyerPhone) == wantedPhone;
      }).toList(growable: false);
      orders.sort((a, b) {
        final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });
      return orders;
    });
  }

  Future<void> updateOrder({
    required String orderId,
    required String action,
    String? trackingCarrier,
    String? trackingNumber,
    String? trackingUrl,
    String? supplierOrderId,
    String? reason,
    String? refundReference,
    String? refundNote,
    String? manualPaymentNote,
  }) async {
    await _functions.httpsCallable('updateCommerceOrder').call({
      'orderId': orderId,
      'action': action,
      if (trackingCarrier != null) 'trackingCarrier': trackingCarrier,
      if (trackingNumber != null) 'trackingNumber': trackingNumber,
      if (trackingUrl != null) 'trackingUrl': trackingUrl,
      if (supplierOrderId != null) 'supplierOrderId': supplierOrderId,
      if (reason != null) 'reason': reason,
      if (refundReference != null) 'refundReference': refundReference,
      if (refundNote != null) 'refundNote': refundNote,
      if (manualPaymentNote != null) 'manualPaymentNote': manualPaymentNote,
    });
  }

  static int estimatedFeeMinor(int sellPriceMinor) =>
      ((sellPriceMinor * 0.029 + 100) * 1.15).round();

  static String shareMessage({
    required String title,
    required String orderingUrl,
  }) =>
      'Order $title from Spaza One on WhatsApp:\n$orderingUrl';

  static String buildProductOrderingUrl({
    required Uri baseUrl,
    required String code,
    required String title,
  }) =>
      baseUrl.replace(
        queryParameters: {
          ...baseUrl.queryParameters,
          'text': 'shop $code order 1 $title',
        },
      ).toString();

  static Future<void> shareToWhatsApp({
    required String title,
  }) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('getMerchantOrderingLink')
        .call({'action': 'get', 'storeId': StoreSession.instance.storeId});
    final data = Map<String, dynamic>.from(result.data as Map);
    final code = data['code']?.toString().trim() ?? '';
    final baseUrl = Uri.tryParse(data['orderingUrl']?.toString() ?? '');
    if (code.isEmpty ||
        baseUrl == null ||
        !{'https', 'http'}.contains(baseUrl.scheme)) {
      throw StateError('Spaza One WhatsApp ordering is not configured.');
    }
    final orderingUrl = buildProductOrderingUrl(
      baseUrl: baseUrl,
      code: code,
      title: title,
    );
    final message = shareMessage(title: title, orderingUrl: orderingUrl);
    final whatsapp = Uri.parse(
      'whatsapp://send?text=${Uri.encodeComponent(message)}',
    );
    if (await canLaunchUrl(whatsapp)) {
      await launchUrl(whatsapp);
      return;
    }
    await Share.share(message);
  }
}

String commerceErrorMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    return friendlyCommerceErrorMessage(error.message);
  }
  return 'Spaza One could not complete that action. Please try again.';
}

String friendlyCommerceErrorMessage(String? providerMessage) {
  final message = providerMessage?.trim() ?? '';
  if (message.isEmpty) {
    return 'Spaza One could not complete that action. Please try again.';
  }
  final lower = message.toLowerCase();
  const providerTerms = <String>[
    'cj ',
    'cjdropshipping',
    'cj dropshipping',
    'network',
    'connection',
    'could not be reached',
    'failed host lookup',
    'socketexception',
  ];
  if (providerTerms.any(lower.contains)) {
    return 'Spaza One could not refresh supplier availability right now. Please try again in a moment.';
  }
  return message;
}

void showCommerceError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(commerceErrorMessage(error))),
  );
}
