import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pasella/services/customer_payment_request_service.dart';
import 'package:pasella/services/secure_function_client.dart';

void main() {
  Uri endpoint(String functionName) => Uri.parse(
        'https://example.test/$functionName',
      );

  test('App Check failures stay calm and retryable in the customer account',
      () async {
    final client = SecureFunctionClient(
      idTokenProvider: () async => 'id-token',
      refreshedIdTokenProvider: () async => 'fresh-id-token',
      appCheckTokenProvider: () => throw StateError('provider detail'),
      refreshedAppCheckTokenProvider: () => throw StateError('provider detail'),
      retryDelay: (_) async {},
      storeIdProvider: () => 'store-a',
    );
    final service = CustomerPaymentRequestService(
      client: client,
      endpointBuilder: endpoint,
    );

    await expectLater(
      service.getOverview(merchantId: 'store-a', customerId: 'customer-a'),
      throwsA(
        isA<CustomerPaymentRequestException>()
            .having(
              (error) => error.code,
              'code',
              'app-check-unavailable',
            )
            .having(
              (error) => error.toString(),
              'message',
              'Payment requests are temporarily unavailable.',
            ),
      ),
    );
  });

  test('server pricing failures expose a safe machine-readable code', () async {
    final client = SecureFunctionClient(
      idTokenProvider: () async => 'id-token',
      appCheckTokenProvider: () async => 'app-check-token',
      httpClient: MockClient((_) async => http.Response(
            jsonEncode({
              'error': 'Payment requests are temporarily unavailable.',
              'code': 'PRICING_UNAVAILABLE',
            }),
            503,
          )),
      storeIdProvider: () => 'store-a',
    );
    final service = CustomerPaymentRequestService(
      client: client,
      endpointBuilder: endpoint,
    );

    await expectLater(
      service.getOverview(merchantId: 'store-a', customerId: 'customer-a'),
      throwsA(
        isA<CustomerPaymentRequestException>().having(
          (error) => error.code,
          'code',
          'PRICING_UNAVAILABLE',
        ),
      ),
    );
  });

  test('credential retry preserves the payment-send idempotency key', () async {
    final requests = <http.Request>[];
    final client = SecureFunctionClient(
      idTokenProvider: () async => 'cached-id-token',
      appCheckTokenProvider: () async => 'cached-app-check-token',
      refreshedIdTokenProvider: () async => 'fresh-id-token',
      refreshedAppCheckTokenProvider: () async => 'fresh-app-check-token',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) {
          return http.Response('{"error":"App verification failed."}', 401);
        }
        return http.Response(
          '{"schemaVersion":1,"requestId":"request-1","status":"queued"}',
          202,
        );
      }),
      storeIdProvider: () => 'store-a',
    );
    final service = CustomerPaymentRequestService(
      client: client,
      endpointBuilder: endpoint,
    );

    final result = await service.send(
      merchantId: 'store-a',
      customerId: 'customer-a',
      quoteKey: 'quote-1',
      pricingVersion: 'pricing-v1',
      idempotencyKey: 'attempt-1',
    );

    expect(result.requestId, 'request-1');
    expect(requests, hasLength(2));
    final firstBody = jsonDecode(requests.first.body) as Map<String, dynamic>;
    final secondBody = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(firstBody['idempotencyKey'], 'attempt-1');
    expect(secondBody['idempotencyKey'], 'attempt-1');
    expect(secondBody, firstBody);
  });

  test('a send-capable overview fails closed without a valid server price', () {
    for (final invalidFields in [
      {'messageCostMinor': 0},
      {'messageCostMinor': 85, 'fallbackMessageCostMinor': 'free'},
      {'messageCostMinor': 85, 'quoteKey': 42},
    ]) {
      expect(
        () => CustomerPaymentRequestOverview.fromMap({
          'schemaVersion': 1,
          'canRequest': true,
          'messageCostMinor': 85,
          'quoteKey': 'quote-1',
          'pricingVersion': 'pricing-v1',
          'reason': 'ready',
          'expectedChannel': 'whatsapp',
          ...invalidFields,
        }),
        throwsA(
          isA<CustomerPaymentRequestException>().having(
            (error) => error.code,
            'code',
            'invalid-pricing-response',
          ),
        ),
      );
    }
  });

  test('a valid send-capable overview preserves its server pricing fields', () {
    final overview = CustomerPaymentRequestOverview.fromMap(const {
      'schemaVersion': 1,
      'canRequest': true,
      'messageCostMinor': 85,
      'fallbackMessageCostMinor': 120,
      'quoteKey': 'quote-1',
      'pricingVersion': 'pricing-v1',
      'reason': 'ready',
      'expectedChannel': 'whatsapp',
    });

    expect(overview.canRequest, isTrue);
    expect(overview.messageCostMinor, 85);
    expect(overview.fallbackMessageCostMinor, 120);
    expect(overview.quoteKey, 'quote-1');
  });
}
