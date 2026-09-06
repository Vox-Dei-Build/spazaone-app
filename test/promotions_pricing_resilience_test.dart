import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';

void main() {
  test('marketing initial load absorbs unavailable messaging pricing',
      () async {
    final results = await Future.wait([
      resolvePromotionsPricing(
        () async => throw const MessagingPricingUnavailable(),
      ),
    ]);

    expect(results.single.isAvailable, isFalse);
    expect(results.single.whatsappPrice, isNull);
    expect(results.single.smsPricePerSegment, isNull);
    expect(
      results.single.error?.message,
      'Messaging pricing is temporarily unavailable.',
    );
  });

  test('marketing pricing converts unexpected dependency errors to safe state',
      () async {
    final result = await resolvePromotionsPricing(
      () async => throw Exception('sensitive upstream detail'),
    );

    expect(result.isAvailable, isFalse);
    expect(result.error, isA<MessagingPricingUnavailable>());
    expect(
        result.error.toString(), isNot(contains('sensitive upstream detail')));
  });

  test('marketing pricing accepts positive finite server prices', () async {
    final result = await resolvePromotionsPricing(
      () async => (whatsappPrice: 1.0, smsPricePerSegment: 1.74),
    );

    expect(result.isAvailable, isTrue);
    expect(result.whatsappPrice, 1.0);
    expect(result.smsPricePerSegment, 1.74);
    expect(result.error, isNull);
  });
}
