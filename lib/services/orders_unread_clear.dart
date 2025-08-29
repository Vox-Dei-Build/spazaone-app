// lib/services/orders_unread_clear.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class OrdersUnreadClearService {
  static Future<void> clearForCustomer({
    required String merchantId,
    required String customerId,
  }) async {
    try {
      final uri = Uri.parse(
        'https://us-central1-pasella-ledger.cloudfunctions.net/markCustomerOrdersAsRead',
      );
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'merchantId': merchantId, 'customerId': customerId}),
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
