import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pasella/services/secure_function_client.dart';

class PaystackInitResult {
  final String authorizationUrl;
  final String reference;
  const PaystackInitResult(
      {required this.authorizationUrl, required this.reference});
}

class PaystackService {
  // Keep your deployed region/project here:
  static const String _initUrl =
      "https://us-central1-pasella-ledger.cloudfunctions.net/createPaystackTransaction";

  /// Core initializer. `purpose` must be 'topup' or 'sale'.
  static Future<PaystackInitResult?> _initialize({
    required String merchantId,
    required double amountRands,
    required String email,
    required String purpose, // 'topup' | 'sale'
    String method = 'local_card',
    String? saleId, // required when purpose == 'sale'
  }) async {
    try {
      if (purpose == 'sale' && (saleId == null || saleId.isEmpty)) {
        throw ArgumentError('saleId is required for purpose "sale".');
      }

      final int amountMinor = (amountRands).round(); // cents

      // Body supports both merchantId (new) and userId (legacy) for safety
      final body = <String, dynamic>{
        "merchantId": merchantId,
        "userId": merchantId, // legacy compatibility
        "email": email,
        "amount": amountMinor,
        "purpose": purpose,
        "method": method,
        if (saleId != null) "saleId": saleId,
      };

      final response = await SecureFunctionClient().post(
        Uri.parse(_initUrl),
        body,
      );

      if (response.statusCode != 200) {
        // Surface server error for debugging
        throw Exception("Init failed ${response.statusCode}: ${response.body}");
      }

      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final url = (map["authorizationUrl"] ?? "").toString();
      final ref = (map["reference"] ?? "").toString();
      if (url.isEmpty || ref.isEmpty) {
        throw Exception("Invalid initializer response: $map");
      }
      return PaystackInitResult(authorizationUrl: url, reference: ref);
    } catch (e) {
      // Keep your existing logging behavior
      debugPrint("Error initializing Paystack transaction: $e");
      return null;
    }
  }

  /// Initialize a **Top-up** transaction (credits virtualBalance via webhook)
  static Future<PaystackInitResult?> initializeTopUp({
    required String userId,
    required double amount, // rands
    required String email,
    String method = 'local_card',
  }) {
    return _initialize(
      merchantId: userId,
      amountRands: amount,
      email: email,
      purpose: 'topup',
      method: method,
    );
  }

  /// Initialize a **Sale** checkout (marks sale paid + credits salesVirtualBalance via webhook)
  static Future<PaystackInitResult?> initializeSale({
    required String userId,
    required String saleId,
    required double amount, // rands
    required String email,
    String method = 'local_card',
  }) {
    return _initialize(
      merchantId: userId,
      amountRands: amount,
      email: email,
      purpose: 'sale',
      method: method,
      saleId: saleId,
    );
  }
}
