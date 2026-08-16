import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/paystack_service.dart';

void main() {
  test('campaign top-up parses rands into exact minor units', () {
    expect(PaystackService.minorUnitsFromRandText('75'), 7500);
    expect(PaystackService.minorUnitsFromRandText('75.5'), 7550);
    expect(PaystackService.minorUnitsFromRandText('75,05'), 7505);
    expect(PaystackService.minorUnitsFromRandText('0.01'), 1);
  });

  test('campaign top-up rejects ambiguous or excessive amounts', () {
    expect(
      () => PaystackService.minorUnitsFromRandText('75.001'),
      throwsA(isA<CampaignTopupException>()),
    );
    expect(
      () => PaystackService.minorUnitsFromRandText('-1'),
      throwsA(isA<CampaignTopupException>()),
    );
    expect(
      () => PaystackService.minorUnitsFromRandText('100000.01'),
      throwsA(isA<CampaignTopupException>()),
    );
  });
}
