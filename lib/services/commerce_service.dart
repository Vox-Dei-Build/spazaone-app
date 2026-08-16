import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/models/commerce/cj_supplier_product.dart';
import 'package:pasella/models/commerce/commerce_order.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/utils/phone_util.dart';

/// New app builds always use the internally consistent catalogue contract.
///
/// [useV2] remains injectable only so compatibility tests can name the legacy
/// endpoint explicitly. A missing build-time flag must never silently route a
/// physical test build to the old production catalogue again.
String dropshipCallableName(String stableName, {bool useV2 = true}) =>
    useV2 ? '${stableName}V2' : stableName;

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

class DropshipListingUpdateResult {
  const DropshipListingUpdateResult({
    required this.state,
    required this.markupMinor,
    required this.sellPriceMinor,
  });

  final String state;
  final int markupMinor;
  final int sellPriceMinor;
}

sealed class DropshipListingFailure implements Exception {
  const DropshipListingFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class DropshipListingQuoteChanged extends DropshipListingFailure {
  const DropshipListingQuoteChanged({
    required this.product,
    required String message,
  }) : super(message);

  final CjCatalogProduct product;
}

class DropshipListingRefreshing extends DropshipListingFailure {
  const DropshipListingRefreshing(super.message);
}

class DropshipListingUnavailable extends DropshipListingFailure {
  const DropshipListingUnavailable(super.message);
}

class CommerceOrdersSnapshot {
  const CommerceOrdersSnapshot({
    required this.orders,
    required this.isFromCache,
  });

  final List<CommerceOrder> orders;
  final bool isFromCache;
  bool get isAuthoritative => !isFromCache;
}

class CommerceOrderUpdateResult {
  const CommerceOrderUpdateResult({
    required this.orderId,
    required this.status,
    required this.customerNotification,
  });

  final String orderId;
  final String status;

  /// sent | queued | not_deliverable | skipped | failed | unknown
  final String customerNotification;

  factory CommerceOrderUpdateResult.fromJson(Map<String, dynamic> data) {
    final notification = Map<String, dynamic>.from(
      data['notification'] is Map
          ? data['notification'] as Map
          : const <String, dynamic>{},
    );
    const knownStates = {
      'sent',
      'queued',
      'not_deliverable',
      'skipped',
      'failed',
    };
    final rawState = notification['customer']?.toString() ?? '';
    return CommerceOrderUpdateResult(
      orderId: data['orderId']?.toString() ?? '',
      status: data['status']?.toString() ?? '',
      customerNotification:
          knownStates.contains(rawState) ? rawState : 'unknown',
    );
  }
}

class CommerceService {
  CommerceService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  })  : _functions = functions ?? FirebaseFunctions.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  static const _localBoxName = 'appBox';

  String _savedProductsKey(String storeId) =>
      'dropship_saved_products_v1:$storeId';
  String _savedCapabilityKey(String storeId) =>
      'dropship_saved_server_available_v1:$storeId';

  List<CjCatalogProduct> _readLocalSavedProducts(String storeId) {
    if (!Hive.isBoxOpen(_localBoxName)) return const [];
    final value = Hive.box(_localBoxName).get(_savedProductsKey(storeId));
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => CjCatalogProduct.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((product) => product.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _writeLocalSavedProducts(
    String storeId,
    Iterable<CjCatalogProduct> products,
  ) async {
    if (!Hive.isBoxOpen(_localBoxName)) return;
    await Hive.box(_localBoxName).put(
      _savedProductsKey(storeId),
      products.map((product) => product.toJson()).toList(growable: false),
    );
  }

  bool _savedServerWasAvailable(String storeId) =>
      Hive.isBoxOpen(_localBoxName) &&
      Hive.box(_localBoxName).get(_savedCapabilityKey(storeId)) == true;

  Future<void> _setSavedServerAvailability(
    String storeId,
    bool available,
  ) async {
    if (!Hive.isBoxOpen(_localBoxName)) return;
    await Hive.box(_localBoxName).put(
      _savedCapabilityKey(storeId),
      available,
    );
  }

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

  Future<List<CjCatalogProduct>> listSavedSupplierProducts() async {
    final storeId = StoreSession.instance.storeId;
    final localProducts = _readLocalSavedProducts(storeId);
    final serverWasAvailable = _savedServerWasAvailable(storeId);
    try {
      final result = await _functions
          .httpsCallable(dropshipCallableName('listSavedSupplierProducts'))
          .call({'storeId': storeId});
      final data = Map<String, dynamic>.from(result.data as Map);
      final serverProducts = (data['products'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => CjCatalogProduct.fromJson(
                Map<String, dynamic>.from(value),
              ))
          .where((product) => product.id.isNotEmpty)
          .toList(growable: false);

      // Migrate bookmarks captured locally while the Saved callable was not
      // yet deployed. This runs only on the first successful server read.
      if (!serverWasAvailable && localProducts.isNotEmpty) {
        final merged = <String, CjCatalogProduct>{
          for (final product in serverProducts) product.id: product,
          for (final product in localProducts) product.id: product,
        };
        final serverIds = serverProducts.map((product) => product.id).toSet();
        for (final product in localProducts) {
          if (serverIds.contains(product.id)) continue;
          await _callSetSupplierProductSaved(
            storeId: storeId,
            product: product,
            saved: true,
          );
        }
        final migrated = merged.values.toList(growable: false);
        await _setSavedServerAvailability(storeId, true);
        await _writeLocalSavedProducts(storeId, migrated);
        return migrated;
      }

      await _setSavedServerAvailability(storeId, true);
      await _writeLocalSavedProducts(storeId, serverProducts);
      return serverProducts;
    } catch (error) {
      if (!isMissingSavedCatalogCapability(error)) rethrow;
      await _setSavedServerAvailability(storeId, false);
      return localProducts;
    }
  }

  Future<void> setSupplierProductSaved(
    CjCatalogProduct product, {
    required bool saved,
  }) async {
    final storeId = StoreSession.instance.storeId;
    try {
      await _callSetSupplierProductSaved(
        storeId: storeId,
        product: product,
        saved: saved,
      );
      await _setSavedServerAvailability(storeId, true);
    } catch (error) {
      if (!isMissingSavedCatalogCapability(error)) rethrow;
      await _setSavedServerAvailability(storeId, false);
    }

    final local = <String, CjCatalogProduct>{
      for (final item in _readLocalSavedProducts(storeId)) item.id: item,
    };
    if (saved) {
      local[product.id] = product;
    } else {
      local.remove(product.id);
    }
    await _writeLocalSavedProducts(storeId, local.values);
  }

  Future<void> _callSetSupplierProductSaved({
    required String storeId,
    required CjCatalogProduct product,
    required bool saved,
  }) async {
    await _functions
        .httpsCallable(dropshipCallableName('setSavedSupplierProduct'))
        .call({
      'storeId': storeId,
      'productId': product.id,
      'saved': saved,
      if (saved) 'snapshot': product.toJson(),
    });
  }

  Future<DropshipListingResult> createListing({
    required String supplierProductId,
    required String supplierVariantId,
    required String catalogQuoteVersion,
    required int markupMinor,
  }) async {
    late final HttpsCallableResult<dynamic> result;
    try {
      result = await _functions
          .httpsCallable(dropshipCallableName('createDropshipListing'))
          .call({
        'storeId': StoreSession.instance.storeId,
        'supplierProductId': supplierProductId,
        'supplierVariantId': supplierVariantId,
        'catalogQuoteVersion': catalogQuoteVersion,
        'markupMinor': markupMinor,
      });
    } catch (error) {
      throw mapDropshipListingFailure(error);
    }
    final data = Map<String, dynamic>.from(result.data as Map);
    return DropshipListingResult(
      listingId: data['listingId']?.toString() ?? '',
      sellerProductId: data['sellerProductId']?.toString() ?? '',
      checkoutUrl: data['checkoutUrl']?.toString() ?? '',
    );
  }

  Future<DropshipListingUpdateResult> updateDropshipListing({
    required String sellerProductId,
    required String listingId,
    required int markupMinor,
    required String state,
  }) async {
    final result = await _functions
        .httpsCallable(dropshipCallableName('updateDropshipListing'))
        .call({
      'storeId': StoreSession.instance.storeId,
      'sellerProductId': sellerProductId,
      'listingId': listingId,
      'markupMinor': markupMinor,
      'state': state,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return DropshipListingUpdateResult(
      state: data['state']?.toString() ?? state,
      markupMinor: (data['markupMinor'] as num?)?.toInt() ?? markupMinor,
      sellPriceMinor: (data['sellPriceMinor'] as num?)?.toInt() ?? 0,
    );
  }

  Stream<List<CommerceOrder>> watchOrders({
    String? customerId,
    String? customerPhone,
  }) =>
      watchOrdersState(
        customerId: customerId,
        customerPhone: customerPhone,
      ).map((snapshot) => snapshot.orders);

  Stream<CommerceOrdersSnapshot> watchOrdersState({
    String? customerId,
    String? customerPhone,
  }) {
    final sellerId = StoreSession.instance.storeId;
    if (sellerId.isEmpty) {
      return Stream.value(
        const CommerceOrdersSnapshot(orders: [], isFromCache: false),
      );
    }
    final wantedCustomerId = customerId?.trim() ?? '';
    final wantedPhone = normalizePhoneNumber(customerPhone);
    return _firestore
        .collection('commerceOrders')
        .where('sellerId', isEqualTo: sellerId)
        .snapshots(includeMetadataChanges: true)
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
      return CommerceOrdersSnapshot(
        orders: orders,
        isFromCache: snapshot.metadata.isFromCache,
      );
    });
  }

  Future<CommerceOrderUpdateResult> updateOrder({
    required String orderId,
    required String action,
    String? trackingNumber,
    String? trackingUrl,
    String? supplierOrderId,
    String? reason,
    String? refundReference,
    String? refundNote,
    String? manualPaymentNote,
  }) async {
    final result = await _functions.httpsCallable('updateCommerceOrder').call({
      'orderId': orderId,
      'action': action,
      if (trackingNumber != null) 'trackingNumber': trackingNumber,
      if (trackingUrl != null) 'trackingUrl': trackingUrl,
      if (supplierOrderId != null) 'supplierOrderId': supplierOrderId,
      if (reason != null) 'reason': reason,
      if (refundReference != null) 'refundReference': refundReference,
      if (refundNote != null) 'refundNote': refundNote,
      if (manualPaymentNote != null) 'manualPaymentNote': manualPaymentNote,
    });
    return CommerceOrderUpdateResult.fromJson(
      Map<String, dynamic>.from(result.data as Map? ?? const {}),
    );
  }

  static int estimatedFeeMinor(int sellPriceMinor) =>
      ((sellPriceMinor * 0.029 + 100) * 1.15).round();
}

String commerceErrorMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    return friendlyCommerceErrorMessage(error.message);
  }
  return 'Spaza One could not complete that action. Please try again.';
}

/// Saved was added after the original catalogue endpoints. During a rolling
/// release, an older backend reports the missing callable as not-found.
bool isMissingSavedCatalogCapability(Object error) =>
    error is FirebaseFunctionsException &&
    const {'not-found', 'unimplemented'}.contains(error.code);

Object mapDropshipListingFailure(Object error) {
  if (error is! FirebaseFunctionsException || error.details is! Map) {
    return error;
  }
  final details = Map<String, dynamic>.from(error.details as Map);
  final reason = details['reason']?.toString() ?? '';
  final message = error.message?.trim();
  switch (reason) {
    case 'CATALOG_QUOTE_CHANGED':
      if (details['product'] is Map) {
        final product = CjCatalogProduct.fromJson(
          Map<String, dynamic>.from(details['product'] as Map),
        );
        if (product.id.isNotEmpty) {
          return DropshipListingQuoteChanged(
            product: product,
            message: message?.isNotEmpty == true
                ? message!
                : 'Price or delivery changed. Review the updated costs.',
          );
        }
      }
      return error;
    case 'CATALOG_REFRESHING':
      return DropshipListingRefreshing(
        message?.isNotEmpty == true
            ? message!
            : 'Updating price and delivery. Try again shortly.',
      );
    case 'CATALOG_UNAVAILABLE':
      return DropshipListingUnavailable(
        message?.isNotEmpty == true
            ? message!
            : 'This product is no longer available.',
      );
    default:
      return error;
  }
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
