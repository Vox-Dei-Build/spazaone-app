import 'dart:convert';

import 'package:pasella/config/function_endpoints.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/secure_function_client.dart';

typedef CustomerPaymentRequestEndpointBuilder = Uri Function(
  String functionName,
);

class CustomerPaymentRequestException implements Exception {
  const CustomerPaymentRequestException(this.code, this.message);

  final String code;
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
        'invalid-response',
        'Payment request details are temporarily unavailable.',
      );
    }
    final canRequest = data['canRequest'] == true;
    final messageCostMinor = _optionalMinor(data['messageCostMinor']);
    final fallbackMessageCostMinor =
        _optionalMinor(data['fallbackMessageCostMinor']);
    final fallbackPriceProvided = data['fallbackMessageCostMinor'] != null;
    final quoteKey =
        data['quoteKey'] is String ? (data['quoteKey'] as String).trim() : '';
    final pricingVersion = data['pricingVersion'] is String
        ? (data['pricingVersion'] as String).trim()
        : '';
    final reason = data['reason']?.toString() ?? 'temporarily_unavailable';
    final expectedChannel = data['expectedChannel']?.toString() ?? '';
    if (canRequest &&
        (messageCostMinor == null ||
            messageCostMinor <= 0 ||
            (fallbackPriceProvided && fallbackMessageCostMinor == null) ||
            (fallbackMessageCostMinor != null &&
                fallbackMessageCostMinor <= 0) ||
            quoteKey.isEmpty ||
            pricingVersion.isEmpty ||
            reason != 'ready' ||
            !{'sms', 'whatsapp'}.contains(expectedChannel))) {
      throw const CustomerPaymentRequestException(
        'invalid-pricing-response',
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
      expectedChannel: expectedChannel.isEmpty ? 'sms' : expectedChannel,
      messageCostMinor: messageCostMinor ?? 0,
      fallbackMessageCostMinor: fallbackMessageCostMinor,
      walletBalanceMinor: (data['walletBalanceMinor'] as num?)?.toInt() ?? 0,
      walletBalanceAfterMinor:
          (data['walletBalanceAfterMinor'] as num?)?.toInt() ?? 0,
      onlinePaymentsReady: data['onlinePaymentsReady'] == true,
      messagePreview: data['messagePreview']?.toString() ?? '',
      quoteKey: quoteKey,
      pricingVersion: pricingVersion,
      canRequest: canRequest,
      reason: reason,
      cooldownEndsAtMs: (data['cooldownEndsAtMs'] as num?)?.toInt() ?? 0,
      lastRequest: last is Map
          ? CustomerPaymentRequestLastStatus.fromMap(
              Map<String, dynamic>.from(last),
            )
          : null,
    );
  }

  static int? _optionalMinor(Object? value) {
    if (value == null) return null;
    if (value is! num || !value.isFinite || value.toInt() != value) {
      return null;
    }
    return value.toInt();
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
  CustomerPaymentRequestService({
    SecureFunctionClient? client,
    CustomerPaymentRequestEndpointBuilder? endpointBuilder,
  })  : _client = client ?? SecureFunctionClient(),
        _endpointBuilder = endpointBuilder ?? FunctionEndpoints.https;

  final SecureFunctionClient _client;
  final CustomerPaymentRequestEndpointBuilder _endpointBuilder;

  @override
  Future<CustomerPaymentRequestOverview> getOverview({
    required String merchantId,
    required String customerId,
  }) async {
    final body = await _post(
      'getCustomerPaymentRequestOverviewV1',
      {'merchantId': merchantId, 'customerId': customerId},
    );
    try {
      final overview = CustomerPaymentRequestOverview.fromMap(body);
      if (overview.reason == 'pricing_unavailable') {
        await CrashService.instance.log(
          'customer payment request pricing unavailable',
          context: const {
            'diagnostic_surface': 'payment_request_pricing',
            'diagnostic_stage': 'server_pricing',
            'diagnostic_code': 'PRICING_UNAVAILABLE',
            'diagnostic_retry_outcome': 'exhausted',
          },
        );
      }
      return overview;
    } on CustomerPaymentRequestException catch (error, stack) {
      await _recordDiagnostic(
        'getCustomerPaymentRequestOverviewV1',
        error,
        stack,
        stage: 'response',
        retryOutcome: 'not_applicable',
      );
      rethrow;
    }
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
    final SecureFunctionResult request;
    try {
      request = await _client.postWithDiagnostics(
        _endpointBuilder(functionName),
        payload,
      );
    } on SecureFunctionClientException catch (error, stack) {
      final exception = CustomerPaymentRequestException(
        error.code,
        'Payment requests are temporarily unavailable.',
      );
      await _recordDiagnostic(
        functionName,
        exception,
        stack,
        stage: 'credentials',
        retryOutcome: error.retryOutcome,
      );
      throw exception;
    } catch (error, stack) {
      const exception = CustomerPaymentRequestException(
        'transport-unavailable',
        'Payment requests are temporarily unavailable.',
      );
      await _recordDiagnostic(
        functionName,
        exception,
        stack,
        stage: 'transport',
        retryOutcome: 'not_attempted',
      );
      throw exception;
    }

    final response = request.response;
    late final Map<String, dynamic> body;
    try {
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      body = Map<String, dynamic>.from(decoded);
    } catch (_, stack) {
      const exception = CustomerPaymentRequestException(
        'invalid-response',
        'Payment requests are temporarily unavailable.',
      );
      await _recordDiagnostic(
        functionName,
        exception,
        stack,
        stage: 'response',
        retryOutcome: request.retryOutcome,
      );
      throw exception;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final exception = CustomerPaymentRequestException(
        body['code']?.toString() ?? _codeForStatus(response.statusCode),
        body['error']?.toString() ??
            'Payment requests are temporarily unavailable.',
      );
      await _recordDiagnostic(
        functionName,
        exception,
        StackTrace.current,
        stage: 'server',
        retryOutcome: request.retryOutcome,
      );
      throw exception;
    }
    if (request.retryOutcome != 'not_needed') {
      await CrashService.instance.log(
        'customer payment request recovered',
        context: {
          'diagnostic_surface': _surface(functionName),
          'diagnostic_stage': 'credentials',
          'diagnostic_code': 'request_recovered',
          'diagnostic_retry_outcome': request.retryOutcome,
        },
      );
    }
    return body;
  }

  Future<void> _recordDiagnostic(
    String functionName,
    CustomerPaymentRequestException error,
    StackTrace stack, {
    required String stage,
    required String retryOutcome,
  }) {
    return CrashService.instance.recordNonFatal(
      error,
      stack,
      reason: 'customer payment request unavailable',
      context: {
        'diagnostic_surface': _surface(functionName),
        'diagnostic_stage': stage,
        'diagnostic_code': error.code,
        'diagnostic_retry_outcome': retryOutcome,
      },
    );
  }

  String _surface(String functionName) => switch (functionName) {
        'getCustomerPaymentRequestOverviewV1' => 'payment_request_pricing',
        'sendCustomerPaymentRequestV1' => 'payment_request_send',
        _ => 'payment_request_status',
      };

  String _codeForStatus(int statusCode) => switch (statusCode) {
        401 => 'authentication-required',
        403 => 'access-denied',
        409 => 'request-conflict',
        _ => 'unavailable',
      };
}
