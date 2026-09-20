import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';

void main() {
  const valid = <String, dynamic>{
    'schemaVersion': 1,
    'currency': 'ZAR',
    'smsCustomerMinor': 174,
    'smsPaymentMinor': 174,
    'whatsappUtilityMinor': 20,
    'whatsappPromotionMinor': 100,
  };

  test('parses exact integer-cent messaging pricing', () {
    final pricing = MessagingPricingSnapshotV1.fromMap(valid);
    expect(pricing.smsCustomerMinor, 174);
    expect(pricing.smsPaymentMinor, 174);
    expect(pricing.whatsappUtilityMinor, 20);
    expect(pricing.whatsappPromotionMinor, 100);
  });

  for (final key in const [
    'smsCustomerMinor',
    'smsPaymentMinor',
    'whatsappUtilityMinor',
    'whatsappPromotionMinor',
  ]) {
    test('fails closed when $key is missing or zero', () {
      final missing = Map<String, dynamic>.from(valid)..remove(key);
      final zero = Map<String, dynamic>.from(valid)..[key] = 0;
      expect(
        () => MessagingPricingSnapshotV1.fromMap(missing),
        throwsA(isA<MessagingPricingUnavailable>()),
      );
      expect(
        () => MessagingPricingSnapshotV1.fromMap(zero),
        throwsA(isA<MessagingPricingUnavailable>()),
      );
    });
  }

  test('rejects an unexpected schema or currency', () {
    expect(
      () => MessagingPricingSnapshotV1.fromMap({
        ...valid,
        'schemaVersion': 2,
      }),
      throwsA(isA<MessagingPricingUnavailable>()),
    );
    expect(
      () => MessagingPricingSnapshotV1.fromMap({
        ...valid,
        'currency': 'USD',
      }),
      throwsA(isA<MessagingPricingUnavailable>()),
    );
  });

  test('does not round invalid or non-finite monetary values into a price', () {
    for (final invalid in [174.9, double.nan, double.infinity, -1]) {
      expect(
        () => MessagingPricingSnapshotV1.fromMap({
          ...valid,
          'smsCustomerMinor': invalid,
        }),
        throwsA(isA<MessagingPricingUnavailable>()),
      );
    }
  });

  test(
      'pricing request uses the selected shop and preserves safe App Check reason',
      () async {
    String? requestedShop;
    var attempts = 0;
    await expectLater(
      DynamicPricingService.loadSnapshot(
        storeId: 'test-shop',
        refreshCredentials: () async {},
        retryDelay: (_) async {},
        loader: (shop) async {
          attempts++;
          requestedShop = shop;
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'App verification is required.',
            details: const {'private': 'must never be exposed'},
          );
        },
      ),
      throwsA(isA<MessagingPricingUnavailable>()
          .having((error) => error.code, 'code', 'app-check-required')
          .having((error) => error.toString(), 'safe message',
              isNot(contains('must never be exposed')))),
    );
    expect(requestedShop, 'test-shop');
    expect(attempts, 2);
  });

  test('transient pricing failure refreshes credentials and retries once',
      () async {
    var attempts = 0;
    var refreshes = 0;
    var delays = 0;
    Future<Map<String, dynamic>> load(String _) async {
      attempts++;
      if (attempts == 1) {
        throw FirebaseFunctionsException(
            code: 'unavailable', message: 'Connection unavailable');
      }
      return valid;
    }

    final snapshot = await DynamicPricingService.loadSnapshot(
      loader: load,
      storeId: 'demo',
      refreshCredentials: () async => refreshes++,
      retryDelay: (_) async => delays++,
    );
    expect(snapshot.smsCustomerMinor, valid['smsCustomerMinor']);
    expect(attempts, 2);
    expect(refreshes, 1);
    expect(delays, 1);
  });

  test('invalid pricing fails closed without retry or credential refresh',
      () async {
    var attempts = 0;
    var refreshes = 0;
    await expectLater(
      DynamicPricingService.loadSnapshot(
        storeId: 'demo',
        loader: (_) async {
          attempts++;
          return {...valid, 'smsPaymentMinor': 0};
        },
        refreshCredentials: () async => refreshes++,
        retryDelay: (_) async {},
      ),
      throwsA(
        isA<MessagingPricingUnavailable>().having(
          (error) => error.code,
          'code',
          'invalid-pricing-response',
        ),
      ),
    );
    expect(attempts, 1);
    expect(refreshes, 0);
  });
}
