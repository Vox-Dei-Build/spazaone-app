import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/customer_payment_request_service.dart';
import 'package:pasella/services/secure_function_client.dart';

void main() {
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
    final service = CustomerPaymentRequestService(client: client);

    await expectLater(
      service.getOverview(merchantId: 'store-a', customerId: 'customer-a'),
      throwsA(
        isA<CustomerPaymentRequestException>().having(
          (error) => error.toString(),
          'message',
          'Payment requests are temporarily unavailable.',
        ),
      ),
    );
  });
}
