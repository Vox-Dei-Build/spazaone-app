import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

void main() {
  group('CurrencyUtil.formatForSms', () {
    test('renders small amount with comma decimal and no thousands sep', () {
      expect(CurrencyUtil.formatForSms(150.00), 'R150,00');
    });

    test('renders amount >= R1 000 without U+00A0 thousands separator', () {
      final result = CurrencyUtil.formatForSms(1250.00);
      expect(result, 'R1250,00');
      expect(result.contains('\u00A0'), isFalse,
          reason: 'NBSP would force the SMS body into UCS-2 segmentation');
    });

    test('renders large amount as plain ASCII', () {
      expect(CurrencyUtil.formatForSms(12500.00), 'R12500,00');
    });

    test('renders zero correctly', () {
      expect(CurrencyUtil.formatForSms(0.00), 'R0,00');
    });

    test('renders negative amount with leading minus', () {
      expect(CurrencyUtil.formatForSms(-150.00), '-R150,00');
    });

    test('handles cents-rounding edge case (0.999 -> R1,00)', () {
      expect(CurrencyUtil.formatForSms(0.999), 'R1,00');
    });

    test('output is GSM-7-safe (every char in ASCII range 0x20-0x7E)', () {
      const samples = [0.0, 0.99, 150.0, 999.99, 1000.0, 12500.0, 1234567.89];
      for (final v in samples) {
        final s = CurrencyUtil.formatForSms(v);
        for (final code in s.codeUnits) {
          expect(code, lessThanOrEqualTo(0x7E),
              reason: 'formatForSms($v) returned non-ASCII char: $s');
          expect(code, greaterThanOrEqualTo(0x20),
              reason: 'formatForSms($v) returned control char: $s');
        }
      }
    });

    test('substituting into SMS template stays in single GSM-7 segment', () {
      // Skeleton matches the post-QW-0 SMS_REMINDER_SHORT shape, with the
      // U+2013 EN DASH replaced by an ASCII hyphen.
      const tpl = 'Hi {customerName}, your balance of {balance} at {shopName} '
          'is due. Please pay to keep your account in good standing. - {shopName}';
      final rendered = tpl
          .replaceAll('{customerName}', 'Sibongile')
          .replaceAll('{balance}', CurrencyUtil.formatForSms(12500.00))
          .replaceAll('{shopName}', 'The Corner Shop');
      expect(SMSPricingUtil.calculateSegments(rendered), 1,
          reason:
              'After QW-0 + QW-1 a realistic reminder must fit in 1 GSM-7 segment');
    });
  });
}
