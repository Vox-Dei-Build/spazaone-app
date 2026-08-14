import 'dart:convert';

import 'package:pasella/config/function_endpoints.dart';
import 'package:pasella/services/secure_function_client.dart';

class AccountPaymentLink {
  const AccountPaymentLink({
    required this.authorizationUrl,
    required this.reference,
    required this.intentId,
    required this.amountMinor,
  });

  final String authorizationUrl;
  final String reference;
  final String intentId;
  final int amountMinor;
}

class AccountPaymentService {
  AccountPaymentService({SecureFunctionClient? client})
      : _client = client ?? SecureFunctionClient();

  final SecureFunctionClient _client;

  Future<AccountPaymentLink> createLink({
    required String merchantId,
    required String customerId,
    required int amountMinor,
    required String email,
    required String channel,
    required String idempotencyKey,
    String? paymentRequestId,
  }) async {
    final response = await _client.post(
      FunctionEndpoints.https('createAccountSettlementLinkV2'),
      {
        'merchantId': merchantId,
        'customerId': customerId,
        'amountMinor': amountMinor,
        'email': email.trim(),
        'channel': channel,
        'idempotencyKey': idempotencyKey,
        if (paymentRequestId != null && paymentRequestId.isNotEmpty)
          'paymentRequestId': paymentRequestId,
      },
    );
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        body['error']?.toString() ?? 'The payment link could not be prepared.',
      );
    }
    final authorizationUrl = body['authorizationUrl']?.toString() ?? '';
    final reference = body['reference']?.toString() ?? '';
    final intentId = body['intentId']?.toString() ?? '';
    final returnedAmount = (body['amountMinor'] as num?)?.toInt() ?? 0;
    if (authorizationUrl.isEmpty ||
        reference.isEmpty ||
        intentId.isEmpty ||
        returnedAmount != amountMinor) {
      throw StateError('The payment provider returned an invalid link.');
    }
    return AccountPaymentLink(
      authorizationUrl: authorizationUrl,
      reference: reference,
      intentId: intentId,
      amountMinor: returnedAmount,
    );
  }
}
