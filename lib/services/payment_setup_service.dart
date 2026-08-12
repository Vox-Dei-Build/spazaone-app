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
  });

  final String orderId;
  final String status;
  final int grossAmountMinor;
  final int platformFeeMinor;
  final int providerFeeMinor;
  final int merchantNetProceedsMinor;
}

class MerchantPaymentOverview {
  const MerchantPaymentOverview({
    required this.enabled,
    required this.reason,
    required this.profile,
    required this.settlements,
  });

  final bool enabled;
  final String reason;
  final SettlementProfileSummary profile;
  final List<MerchantSettlement> settlements;
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
  }) async {
    final response = await SecureFunctionClient().post(
      FunctionEndpoints.https('prepareMerchantSettlementProfileV2'),
      {
        'merchantId': merchantId,
        'bankingDetailsId': bankingDetailsId,
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
    final readiness =
        Map<String, dynamic>.from(data['readiness'] as Map? ?? {});
    final profile = Map<String, dynamic>.from(data['profile'] as Map? ?? {});
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
          ),
        )
        .toList();
    return MerchantPaymentOverview(
      enabled: readiness['enabled'] == true,
      reason: readiness['reason']?.toString() ?? 'not_ready',
      profile: SettlementProfileSummary(
        status: profile['status']?.toString() ?? 'not_started',
        bankVerificationStatus:
            profile['bankVerificationStatus']?.toString() ?? 'not_started',
        bankName: profile['bankName']?.toString() ?? '',
        resolvedAccountName: profile['resolvedAccountName']?.toString() ?? '',
        maskedAccount: profile['maskedAccount']?.toString() ?? '',
      ),
      settlements: settlements,
    );
  }
}
