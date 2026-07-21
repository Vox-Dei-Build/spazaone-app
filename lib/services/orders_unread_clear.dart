// lib/services/orders_unread_clear.dart
import 'package:flutter/foundation.dart';
import 'package:pasella/services/secure_function_client.dart';
import 'package:pasella/config/function_endpoints.dart';

class OrdersUnreadClearService {
  static Future<void> clearForCustomer({
    required String merchantId,
    required String customerId,
  }) async {
    try {
      final uri = FunctionEndpoints.https('markCustomerOrdersAsRead');
      final resp = await SecureFunctionClient().post(
        uri,
        {'merchantId': merchantId, 'customerId': customerId},
      );
      if (resp.statusCode != 200) {
        debugPrint(
            'markCustomerOrdersAsRead failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      debugPrint('Failed to clear per-customer orders unread: $e');
    }
  }
}
