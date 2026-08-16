import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:pasella/config/function_endpoints.dart';
import 'package:pasella/services/secure_function_client.dart';

class SettlementProfileSummary {
  const SettlementProfileSummary({
    required this.status,
    required this.bankVerificationStatus,
    required this.bankName,
    required this.resolvedAccountName,
    required this.maskedAccount,
  });

  final String status;
  final String bankVerificationStatus;
  final String bankName;
  final String resolvedAccountName;
  final String maskedAccount;
}

class MerchantSettlement {
  const MerchantSettlement({
    required this.orderId,
    required this.status,
    required this.grossAmountMinor,
    required this.platformFeeMinor,
    required this.providerFeeMinor,
    required this.merchantNetProceedsMinor,
    this.currency = 'ZAR',
    this.testOnly = false,
    this.providerSettlementAtMs = 0,
    this.expectedSettlementAtMs = 0,
  });

  final String orderId;
  final String status;
  final int grossAmountMinor;
  final int platformFeeMinor;
  final int providerFeeMinor;
  final int merchantNetProceedsMinor;
  final String currency;
  final bool testOnly;
  final int providerSettlementAtMs;
  final int expectedSettlementAtMs;
}

class MerchantPaymentCapability {
  const MerchantPaymentCapability({
    required this.ready,
    required this.reason,
    required this.channels,
  });

  final bool ready;
  final String reason;
  final List<String> channels;

  static const unavailable = MerchantPaymentCapability(
    ready: false,
    reason: 'unavailable',
    channels: <String>[],
  );

  factory MerchantPaymentCapability.fromMap(Map<String, dynamic> data) {
    return MerchantPaymentCapability(
      ready: data['ready'] == true,
      reason: data['reason']?.toString() ?? 'unavailable',
      channels: List<String>.unmodifiable(
        (data['channels'] as List? ?? const <dynamic>[])
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty),
      ),
    );
  }
}

class MerchantPaymentsV2 {
  const MerchantPaymentsV2({
    required this.schemaVersion,
    required this.campaignCredits,
    required this.ownedOrders,
    required this.accountPayments,
    required this.supplierOrders,
  });

  final int schemaVersion;
  final MerchantPaymentCapability campaignCredits;
  final MerchantPaymentCapability ownedOrders;
  final MerchantPaymentCapability accountPayments;
  final MerchantPaymentCapability supplierOrders;

  factory MerchantPaymentsV2.fromMap(
    Map<String, dynamic> data, {
    required Map<String, dynamic> legacyReadiness,
  }) {
    MerchantPaymentCapability capability(String key) {
      return MerchantPaymentCapability.fromMap(
        Map<String, dynamic>.from(data[key] as Map? ?? const {}),
      );
    }

    final owned = data['ownedOrders'] is Map
        ? capability('ownedOrders')
        : MerchantPaymentCapability(
            ready: legacyReadiness['enabled'] == true,
            reason: legacyReadiness['reason']?.toString() ?? 'unavailable',
            channels: const <String>[],
          );
    return MerchantPaymentsV2(
      schemaVersion: (data['schemaVersion'] as num? ?? 1).toInt(),
      campaignCredits: data['campaignCredits'] is Map
          ? capability('campaignCredits')
          : MerchantPaymentCapability.unavailable,
      ownedOrders: owned,
      accountPayments: data['accountPayments'] is Map
          ? capability('accountPayments')
          : MerchantPaymentCapability.unavailable,
      supplierOrders: data['supplierOrders'] is Map
          ? capability('supplierOrders')
          : MerchantPaymentCapability.unavailable,
    );
  }
}

class MerchantPaymentOverview {
  const MerchantPaymentOverview({
    required this.paymentsV2,
    required this.profile,
    required this.settlements,
    this.settlementCurrency = 'ZAR',
    this.outstandingSettlementMinor = 0,
    this.testOnlySettlementMinor = 0,
  });

  final MerchantPaymentsV2 paymentsV2;
  final SettlementProfileSummary profile;
  final List<MerchantSettlement> settlements;
  final String settlementCurrency;
  final int outstandingSettlementMinor;
  final int testOnlySettlementMinor;

  /// Backward-compatible owned-order readiness alias for 4.8.0 consumers.
  bool get enabled => paymentsV2.ownedOrders.ready;
  String get reason => paymentsV2.ownedOrders.reason;

  factory MerchantPaymentOverview.fromMap(Map<String, dynamic> data) {
    final readiness =
        Map<String, dynamic>.from(data['readiness'] as Map? ?? {});
    final paymentsData =
        Map<String, dynamic>.from(data['paymentsV2'] as Map? ?? {});
    final profile = Map<String, dynamic>.from(data['profile'] as Map? ?? {});
    final totals = Map<String, dynamic>.from(data['totals'] as Map? ?? {});
    final settlements = (data['settlements'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .map(
          (value) => MerchantSettlement(
            orderId: value['orderId']?.toString() ?? '',
            status: value['status']?.toString() ?? 'pending',
            grossAmountMinor: (value['grossAmountMinor'] as num? ?? 0).toInt(),
            platformFeeMinor: (value['platformFeeMinor'] as num? ?? 0).toInt(),
            providerFeeMinor: (value['providerFeeMinor'] as num? ?? 0).toInt(),
            merchantNetProceedsMinor:
                (value['merchantNetProceedsMinor'] as num? ?? 0).toInt(),
            currency: value['currency']?.toString() ?? 'ZAR',
            testOnly: value['testOnly'] == true,
            providerSettlementAtMs:
                (value['providerSettlementAtMs'] as num? ?? 0).toInt(),
            expectedSettlementAtMs:
                (value['expectedSettlementAtMs'] as num? ?? 0).toInt(),
          ),
        )
        .toList();
    return MerchantPaymentOverview(
      paymentsV2: MerchantPaymentsV2.fromMap(
        paymentsData,
        legacyReadiness: readiness,
      ),
      profile: SettlementProfileSummary(
        status: profile['status']?.toString() ?? 'not_started',
        bankVerificationStatus:
            profile['bankVerificationStatus']?.toString() ?? 'not_started',
        bankName: profile['bankName']?.toString() ?? '',
        resolvedAccountName: profile['resolvedAccountName']?.toString() ?? '',
        maskedAccount: profile['maskedAccount']?.toString() ?? '',
      ),
      settlements: settlements,
      settlementCurrency: totals['currency']?.toString() ?? 'ZAR',
      outstandingSettlementMinor:
          (totals['outstandingMinor'] as num? ?? 0).toInt(),
      testOnlySettlementMinor: (totals['testOnlyMinor'] as num? ?? 0).toInt(),
    );
  }
}

class PaymentSetupException implements Exception {
  const PaymentSetupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PaymentSetupService {
  const PaymentSetupService._();

  static Future<Map<String, dynamic>> prepareSettlementProfile({
    required String merchantId,
    required String bankingDetailsId,
    required String accountType,
    required String documentType,
    required String documentNumber,
  }) async {
    final response = await SecureFunctionClient().post(
      FunctionEndpoints.https('prepareMerchantSettlementProfileV2'),
      {
        'merchantId': merchantId,
        'bankingDetailsId': bankingDetailsId,
        'accountType': accountType,
        'documentType': documentType,
        'documentNumber': documentNumber,
      },
    );
    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Public error below deliberately avoids provider response details.
    }
    if (response.statusCode != 200) {
      throw PaymentSetupException(
        body['error']?.toString() ??
            'Bank verification is temporarily unavailable.',
      );
    }
    return body;
  }

  static Future<MerchantPaymentOverview> overview(String merchantId) async {
    final response = await FirebaseFunctions.instance
        .httpsCallable('getMerchantPaymentOverviewV2')
        .call({'merchantId': merchantId});
    final data = Map<String, dynamic>.from(response.data as Map);
    return MerchantPaymentOverview.fromMap(data);
  }
}
