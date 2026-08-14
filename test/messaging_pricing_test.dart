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
}
