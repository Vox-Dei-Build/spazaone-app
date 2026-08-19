import 'dart:convert';

import 'package:pasella/config/function_endpoints.dart';
import 'package:pasella/services/secure_function_client.dart';

class RepaymentPlanException implements Exception {
  const RepaymentPlanException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RepaymentPlanCreateResult {
  const RepaymentPlanCreateResult({
    required this.planId,
    required this.totalAmountMinor,
    required this.installmentAmountMinor,
    required this.cadence,
    required this.deduped,
  });

  final String planId;
  final int totalAmountMinor;
  final int installmentAmountMinor;
  final String cadence;
  final bool deduped;
}

abstract interface class RepaymentPlanGateway {
  Future<RepaymentPlanCreateResult> create({
    required String merchantId,
    required String customerId,
    required int totalAmountMinor,
    required int installmentAmountMinor,
    required String cadence,
    required int startAtMs,
    required String idempotencyKey,
  });
}

class RepaymentPlanService implements RepaymentPlanGateway {
  RepaymentPlanService({SecureFunctionClient? client})
      : _client = client ?? SecureFunctionClient();

  final SecureFunctionClient _client;

  @override
  Future<RepaymentPlanCreateResult> create({
    required String merchantId,
    required String customerId,
    required int totalAmountMinor,
    required int installmentAmountMinor,
    required String cadence,
    required int startAtMs,
    required String idempotencyKey,
  }) async {
    final response = await _client.post(
      FunctionEndpoints.https('createRepaymentPlanV2'),
      {
        'merchantId': merchantId,
        'customerId': customerId,
        'totalAmountMinor': totalAmountMinor,
        'installmentAmountMinor': installmentAmountMinor,
        'cadence': cadence,
        'startAtMs': startAtMs,
        'idempotencyKey': idempotencyKey,
      },
    );
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RepaymentPlanException(
        body['error']?.toString() ?? 'The repayment plan could not be created.',
      );
    }
    final planId = body['planId']?.toString() ?? '';
    final total = (body['totalAmountMinor'] as num?)?.toInt() ?? 0;
    final installment = (body['installmentAmountMinor'] as num?)?.toInt() ?? 0;
    if (planId.isEmpty || total <= 0 || installment <= 0) {
      throw const RepaymentPlanException(
        'The repayment plan response was incomplete.',
      );
    }
    return RepaymentPlanCreateResult(
      planId: planId,
      totalAmountMinor: total,
      installmentAmountMinor: installment,
      cadence: body['cadence']?.toString() ?? cadence,
      deduped: body['deduped'] == true,
    );
  }
}
