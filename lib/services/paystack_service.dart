import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pasella/services/secure_function_client.dart';
import 'package:pasella/config/function_endpoints.dart';

class PaystackInitResult {
  final String authorizationUrl;
  final String reference;
  final String? intentId;
  final CampaignTopupQuote? quote;
  const PaystackInitResult(
      {required this.authorizationUrl,
      required this.reference,
      this.intentId,
      this.quote});
}

enum CampaignTopupChannel { eft, capitecPay, qr }

extension CampaignTopupChannelWire on CampaignTopupChannel {
  String get wireName => switch (this) {
        CampaignTopupChannel.eft => 'eft',
        CampaignTopupChannel.capitecPay => 'capitec_pay',
        CampaignTopupChannel.qr => 'qr',
      };

  String get label => switch (this) {
        CampaignTopupChannel.eft => 'Ozow (Instant EFT)',
        CampaignTopupChannel.capitecPay => 'Capitec Pay',
        CampaignTopupChannel.qr => 'Scan to Pay QR',
      };
}

class CampaignTopupQuote {
  const CampaignTopupQuote({
    required this.channel,
    required this.creditAmountMinor,
    required this.providerFeeMinor,
    required this.totalChargeMinor,
  });

  final CampaignTopupChannel channel;
  final int creditAmountMinor;
  final int providerFeeMinor;
  final int totalChargeMinor;

  double get creditAmount => creditAmountMinor / 100;
  double get providerFee => providerFeeMinor / 100;
  double get totalCharge => totalChargeMinor / 100;
}

enum CampaignTopupStatus {
  checking,
  paid,
  failed,
  expired,
  refundPending,
  refunded,
  needsReview,
}

class CampaignTopupStatusResult {
  const CampaignTopupStatusResult({
    required this.status,
    required this.creditAmountMinor,
    required this.totalChargeMinor,
    required this.updatedAtMs,
  });

  final CampaignTopupStatus status;
  final int creditAmountMinor;
  final int totalChargeMinor;
  final int updatedAtMs;

  bool get isTerminal => status != CampaignTopupStatus.checking;
}

class CampaignTopupException implements Exception {
  const CampaignTopupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PaystackService {
  static int minorUnitsFromRandText(String input) {
    final normalized = input.trim().replaceAll(',', '.');
    final match = RegExp(r'^(\d{1,7})(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) {
      throw const CampaignTopupException(
        'Enter a valid amount with no more than two decimal places.',
      );
    }
    final rands = int.parse(match.group(1)!);
    final decimal = (match.group(2) ?? '').padRight(2, '0');
    final cents = decimal.isEmpty ? 0 : int.parse(decimal);
    final result = rands * 100 + cents;
    if (result <= 0 || result > 10000000) {
      throw const CampaignTopupException(
        'Enter an amount between R0.01 and R100,000.',
      );
    }
    return result;
  }

  static CampaignTopupChannel _channelFromWire(String value) {
    return switch (value) {
      'eft' => CampaignTopupChannel.eft,
      'capitec_pay' => CampaignTopupChannel.capitecPay,
      'qr' => CampaignTopupChannel.qr,
      _ => throw const CampaignTopupException(
          'The payment method returned by the server is not supported.',
        ),
    };
  }

  static CampaignTopupQuote _campaignQuote(Map<String, dynamic> map) {
    final credit = map['creditAmountMinor'];
    final fee = map['providerFeeMinor'];
    final total = map['totalChargeMinor'];
    if (credit is! int ||
        fee is! int ||
        total is! int ||
        total != credit + fee) {
      throw const CampaignTopupException(
        'The payment quote could not be verified. Please try again.',
      );
    }
    return CampaignTopupQuote(
      channel: _channelFromWire(map['channel']?.toString() ?? ''),
      creditAmountMinor: credit,
      providerFeeMinor: fee,
      totalChargeMinor: total,
    );
  }

  static Future<Map<String, dynamic>> _postV2(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    final response = await SecureFunctionClient().post(
      FunctionEndpoints.https(functionName),
      body,
    );
    Map<String, dynamic> payload = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // The public error below intentionally avoids exposing provider output.
    }
    if (response.statusCode != 200) {
      throw CampaignTopupException(
        payload['error']?.toString() ??
            'Adding money is temporarily unavailable. Please try again.',
      );
    }
    return payload;
  }

  static Future<CampaignTopupQuote> quoteCampaignCreditV2({
    required String merchantId,
    required int creditAmountMinor,
    required CampaignTopupChannel channel,
  }) async {
    final payload = await _postV2('getCampaignTopupQuoteV2', {
      'merchantId': merchantId,
      'creditAmountMinor': creditAmountMinor,
      'channel': channel.wireName,
    });
    return _campaignQuote(payload);
  }

  static Future<PaystackInitResult> initializeCampaignCreditV2({
    required String merchantId,
    required int creditAmountMinor,
    required String email,
    required CampaignTopupChannel channel,
    required String idempotencyKey,
  }) async {
    final payload = await _postV2('createCampaignTopupV2', {
      'merchantId': merchantId,
      'creditAmountMinor': creditAmountMinor,
      'email': email,
      'channel': channel.wireName,
      'idempotencyKey': idempotencyKey,
    });
    final url = payload['authorizationUrl']?.toString() ?? '';
    final reference = payload['reference']?.toString() ?? '';
    final intentId = payload['intentId']?.toString() ?? '';
    final rawQuote = payload['quote'];
    if (url.isEmpty ||
        reference.isEmpty ||
        intentId.isEmpty ||
        rawQuote is! Map) {
      throw const CampaignTopupException(
        'Paystack did not return a complete checkout. Please try again.',
      );
    }
    final quote = _campaignQuote(Map<String, dynamic>.from(rawQuote));
    if (quote.creditAmountMinor != creditAmountMinor ||
        quote.channel != channel) {
      throw const CampaignTopupException(
        'The payment quote changed. No payment was opened.',
      );
    }
    return PaystackInitResult(
      authorizationUrl: url,
      reference: reference,
      intentId: intentId,
      quote: quote,
    );
  }

  static Future<CampaignTopupStatusResult> campaignTopupStatusV2({
    required String merchantId,
    required String intentId,
  }) async {
    final payload = await _postV2('getCampaignTopupStatusV2', {
      'merchantId': merchantId,
      'intentId': intentId,
    });
    final status = switch (payload['status']?.toString()) {
      'checking' => CampaignTopupStatus.checking,
      'paid' => CampaignTopupStatus.paid,
      'failed' => CampaignTopupStatus.failed,
      'expired' => CampaignTopupStatus.expired,
      'refund_pending' => CampaignTopupStatus.refundPending,
      'refunded' => CampaignTopupStatus.refunded,
      'needs_review' => CampaignTopupStatus.needsReview,
      _ => throw const CampaignTopupException(
          'Payment status could not be verified. Please try again.',
        ),
    };
    return CampaignTopupStatusResult(
      status: status,
      creditAmountMinor: (payload['creditAmountMinor'] as num? ?? 0).toInt(),
      totalChargeMinor: (payload['totalChargeMinor'] as num? ?? 0).toInt(),
      updatedAtMs: (payload['updatedAtMs'] as num? ?? 0).toInt(),
    );
  }

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
        FunctionEndpoints.https('createPaystackTransaction'),
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
