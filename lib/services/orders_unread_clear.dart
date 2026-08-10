// lib/services/orders_unread_clear.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_app_badger_plus/flutter_app_badger_plus.dart';
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
      } else {
        final data = jsonDecode(resp.body);
        final total = data is Map
            ? int.tryParse(data['unreadTotalCount']?.toString() ?? '')
            : null;
        if (total != null) {
          await FlutterAppBadgerPlus.updateBadgeCount(total);
        }
      }
    } catch (e) {
      debugPrint('Failed to clear per-customer orders unread: $e');
    }
  }
}
