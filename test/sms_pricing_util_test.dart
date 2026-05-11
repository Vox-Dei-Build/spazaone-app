import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

void main() {
  group('SMSPricingUtil.classify', () {
    test('empty body is GSM-7 with zero septets', () {
      final info = SMSPricingUtil.classify('');
      expect(info.encoding, SmsEncoding.gsm7);
      expect(info.septetLength, 0);
      expect(info.offendingCharacters, isEmpty);
    });

    test('plain ASCII is GSM-7', () {
      final info = SMSPricingUtil.classify('Hello world');
      expect(info.encoding, SmsEncoding.gsm7);
      expect(info.septetLength, 11);
    });

    test('GSM-7 default-alphabet non-ASCII chars stay GSM-7', () {
      // £ É ñ à Ä Ö are all in the GSM-7 default alphabet — must NOT
      // flip the message to UCS-2 (this was the bug in the old `r > 127`
      // classifier).
      final info = SMSPricingUtil.classify('£É ñà ÄÖ');
      expect(info.encoding, SmsEncoding.gsm7,
          reason: 'GSM-7 default-alphabet chars must not trigger UCS-2');
      // 6 letters + 2 spaces = 8 septets.
      expect(info.septetLength, 8);
    });

    test('GSM-7 extension chars cost 2 septets each', () {
      // € { } [ ] ~ | ^ \ are all in the extension table (ESC + char).
      final info = SMSPricingUtil.classify('€{}[]~|^\\');
      expect(info.encoding, SmsEncoding.gsm7);
      // 9 extension chars × 2 = 18 septets.
      expect(info.septetLength, 18);
    });

    test('U+2013 EN DASH forces UCS-2', () {
      final info = SMSPricingUtil.classify('Thanks – ShopName');
      expect(info.encoding, SmsEncoding.ucs2);
      expect(info.offendingCharacters, contains('\u2013'));
    });

    test('U+00A0 NO-BREAK SPACE forces UCS-2', () {
      final info = SMSPricingUtil.classify('Balance: R1\u00A0250,00');
      expect(info.encoding, SmsEncoding.ucs2);
      expect(info.offendingCharacters, contains('\u00A0'));
    });

    test('emoji forces UCS-2 and is reported as offender', () {
      final info = SMSPricingUtil.classify('Order shipped 📦');
      expect(info.encoding, SmsEncoding.ucs2);
      expect(info.offendingCharacters, isNotEmpty);
    });

    test('hasInvisibleUnicodeOffender detects production traps', () {
      expect(SMSPricingUtil.classify('Hi – there').hasInvisibleUnicodeOffender,
          isTrue);
      expect(
          SMSPricingUtil.classify('R1\u00A0250,00').hasInvisibleUnicodeOffender,
          isTrue);
      expect(SMSPricingUtil.classify('plain ASCII').hasInvisibleUnicodeOffender,
          isFalse);
    });

    test('offenderLabel names the production offenders for the cost sheet',
        () {
      expect(SMSPricingUtil.classify('Hi – there').offenderLabel,
          'en-dash (–)');
      expect(SMSPricingUtil.classify('R1\u00A0250,00').offenderLabel,
          'non-breaking space (often from currency formatting)');
      expect(SMSPricingUtil.classify('plain ASCII').offenderLabel, isNull);
    });
  });

  group('SMSPricingUtil.calculateSegments', () {
    test('empty body bills as 1 segment', () {
      expect(SMSPricingUtil.calculateSegments(''), 1);
    });

    test('160-char GSM-7 body is 1 segment', () {
      final body = 'a' * 160;
      expect(SMSPricingUtil.calculateSegments(body), 1);
    });

    test('161-char GSM-7 body is 2 segments (153-septet multipart parts)', () {
      final body = 'a' * 161;
      expect(SMSPricingUtil.calculateSegments(body), 2);
    });

    test('307-char GSM-7 body is 3 segments (boundary at 306 = 2×153)', () {
      // 306 = 2 × 153 exactly → 2 segments. 307 should tip into 3.
      expect(SMSPricingUtil.calculateSegments('a' * 306), 2);
      expect(SMSPricingUtil.calculateSegments('a' * 307), 3);
    });

    test('GSM-7 body with extension chars consumes 2 septets per char', () {
      // 80 € chars = 160 septets → 1 segment. 81 → 162 septets → 2.
      expect(SMSPricingUtil.calculateSegments('€' * 80), 1);
      expect(SMSPricingUtil.calculateSegments('€' * 81), 2);
    });

    test('70-char UCS-2 body is 1 segment, 71 is 2 (67-unit parts)', () {
      // Wrap in ASCII so `text.trim()` doesn't strip Unicode whitespace
      // (U+00A0 is whitespace under Dart's Unicode-aware trim).
      final body70 = 'a${'\u00A0' * 68}b';
      final body71 = 'a${'\u00A0' * 69}b';
      expect(SMSPricingUtil.calculateSegments(body70), 1,
          reason: '70 UCS-2 code units = 1 segment');
      expect(SMSPricingUtil.calculateSegments(body71), 2,
          reason: '71 UCS-2 code units = 2 segments (67-unit multipart parts)');
    });

    test('en-dash in short body costs 1 UCS-2 segment, not 2 GSM-7', () {
      // 50 chars with one en-dash → 50 UCS-2 code units → 1 segment.
      final body = 'a' * 49 + '\u2013';
      expect(SMSPricingUtil.calculateSegments(body), 1);
    });
  });

  group('SMSPricingUtil.calculateCost', () {
    test('cost scales linearly with segment count at live unit price', () {
      const unit = 1.7407; // R1.7407 per segment at live RC values
      expect(SMSPricingUtil.calculateCost(text: 'short', unitCost: unit),
          closeTo(1.74, 0.005));
      expect(
          SMSPricingUtil.calculateCost(text: 'a' * 161, unitCost: unit),
          closeTo(3.48, 0.005));
      expect(
          SMSPricingUtil.calculateCost(text: 'a' * 307, unitCost: unit),
          closeTo(5.22, 0.005));
    });
  });
}
