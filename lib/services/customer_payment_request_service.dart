import 'dart:convert';

import 'package:pasella/config/function_endpoints.dart';
import 'package:pasella/services/secure_function_client.dart';

class CustomerPaymentRequestException implements Exception {
  const CustomerPaymentRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CustomerPaymentRequestLastStatus {
  const CustomerPaymentRequestLastStatus({
    required this.requestId,
    required this.status,
    required this.sentAtMs,
    required this.cooldownEndsAtMs,
  });

  final String requestId;
  final String status;
  final int sentAtMs;
  final int cooldownEndsAtMs;

  factory CustomerPaymentRequestLastStatus.fromMap(Map<String, dynamic> data) {
    return CustomerPaymentRequestLastStatus(
      requestId: data['requestId']?.toString() ?? '',
      status: data['status']?.toString() ?? 'failed',
      sentAtMs: (data['sentAtMs'] as num?)?.toInt() ?? 0,
      cooldownEndsAtMs: (data['cooldownEndsAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class CustomerPaymentRequestOverview {
  const CustomerPaymentRequestOverview({
    required this.merchantId,
    required this.customerId,
    required this.outstandingAmountMinor,
    required this.mode,
    required this.expectedChannel,
    required this.messageCostMinor,
    required this.fallbackMessageCostMinor,
    required this.walletBalanceMinor,
    required this.walletBalanceAfterMinor,
    required this.onlinePaymentsReady,
    required this.messagePreview,
    required this.quoteKey,
    required this.pricingVersion,
    required this.canRequest,
    required this.reason,
    required this.cooldownEndsAtMs,
    required this.lastRequest,
  });

  final String merchantId;
  final String customerId;
  final int outstandingAmountMinor;
  final String mode;
  final String expectedChannel;
  final int messageCostMinor;
  final int? fallbackMessageCostMinor;
  final int walletBalanceMinor;
  final int walletBalanceAfterMinor;
  final bool onlinePaymentsReady;
  final String messagePreview;
  final String quoteKey;
  final String pricingVersion;
  final bool canRequest;
  final String reason;
  final int cooldownEndsAtMs;
  final CustomerPaymentRequestLastStatus? lastRequest;

  factory CustomerPaymentRequestOverview.fromMap(Map<String, dynamic> data) {
    if (data['schemaVersion'] != 1) {
      throw const CustomerPaymentRequestException(
        'Payment request details are temporarily unavailable.',
      );
    }
    final last = data['lastRequest'];
    return CustomerPaymentRequestOverview(
      merchantId: data['merchantId']?.toString() ?? '',
      customerId: data['customerId']?.toString() ?? '',
      outstandingAmountMinor:
          (data['outstandingAmountMinor'] as num?)?.toInt() ?? 0,
      mode: data['mode']?.toString() ?? 'sms_reminder',
      expectedChannel: data['expectedChannel']?.toString() ?? 'sms',
      messageCostMinor: (data['messageCostMinor'] as num?)?.toInt() ?? 0,
      fallbackMessageCostMinor:
          (data['fallbackMessageCostMinor'] as num?)?.toInt(),
      walletBalanceMinor: (data['walletBalanceMinor'] as num?)?.toInt() ?? 0,
      walletBalanceAfterMinor:
          (data['walletBalanceAfterMinor'] as num?)?.toInt() ?? 0,
      onlinePaymentsReady: data['onlinePaymentsReady'] == true,
      messagePreview: data['messagePreview']?.toString() ?? '',
      quoteKey: data['quoteKey']?.toString() ?? '',
      pricingVersion: data['pricingVersion']?.toString() ?? '',
      canRequest: data['canRequest'] == true,
      reason: data['reason']?.toString() ?? 'temporarily_unavailable',
      cooldownEndsAtMs: (data['cooldownEndsAtMs'] as num?)?.toInt() ?? 0,
      lastRequest: last is Map
          ? CustomerPaymentRequestLastStatus.fromMap(
              Map<String, dynamic>.from(last),
            )
          : null,
    );
  }
}

class CustomerPaymentRequestSendResult {
  const CustomerPaymentRequestSendResult({
    required this.requestId,
    required this.status,
  });

  final String requestId;
  final String status;
}

class CustomerPaymentRequestStatus {
  const CustomerPaymentRequestStatus({
    required this.requestId,
    required this.status,
    required this.sentAtMs,
    required this.cooldownEndsAtMs,
  });

  final String requestId;
  final String status;
  final int sentAtMs;
  final int cooldownEndsAtMs;
}

abstract interface class CustomerPaymentRequestGateway {
  Future<CustomerPaymentRequestOverview> getOverview({
    required String merchantId,
    required String customerId,
  });

  Future<CustomerPaymentRequestSendResult> send({
    required String merchantId,
    required String customerId,
    required String quoteKey,
    required String pricingVersion,
    required String idempotencyKey,
  });

  Future<CustomerPaymentRequestStatus> getStatus({required String requestId});
}

class CustomerPaymentRequestService implements CustomerPaymentRequestGateway {
  CustomerPaymentRequestService({SecureFunctionClient? client})
      : _client = client ?? SecureFunctionClient();

  final SecureFunctionClient _client;

  @override
  Future<CustomerPaymentRequestOverview> getOverview({
    required String merchantId,
    required String customerId,
  }) async {
    final body = await _post(
      'getCustomerPaymentRequestOverviewV1',
      {'merchantId': merchantId, 'customerId': customerId},
    );
    return CustomerPaymentRequestOverview.fromMap(body);
  }

  @override
  Future<CustomerPaymentRequestSendResult> send({
    required String merchantId,
    required String customerId,
    required String quoteKey,
    required String pricingVersion,
    required String idempotencyKey,
  }) async {
    final body = await _post(
      'sendCustomerPaymentRequestV1',
      {
        'merchantId': merchantId,
        'customerId': customerId,
        'quoteKey': quoteKey,
        'pricingVersion': pricingVersion,
        'idempotencyKey': idempotencyKey,
      },
    );
    return CustomerPaymentRequestSendResult(
      requestId: body['requestId']?.toString() ?? '',
      status: body['status']?.toString() ?? 'queued',
    );
  }

  @override
  Future<CustomerPaymentRequestStatus> getStatus({
    required String requestId,
  }) async {
    final body = await _post(
      'getCustomerPaymentRequestStatusV1',
      {'requestId': requestId},
    );
    return CustomerPaymentRequestStatus(
      requestId: body['requestId']?.toString() ?? requestId,
      status: body['status']?.toString() ?? 'failed',
      sentAtMs: (body['sentAtMs'] as num?)?.toInt() ?? 0,
      cooldownEndsAtMs: (body['cooldownEndsAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Map<String, dynamic>> _post(
    String functionName,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.post(
      FunctionEndpoints.https(functionName),
      payload,
    );
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CustomerPaymentRequestException(
        body['error']?.toString() ??
            'Payment requests are temporarily unavailable.',
      );
    }
    return body;
  }
}
