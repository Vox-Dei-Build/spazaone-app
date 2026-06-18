import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/utils/phone_util.dart';

/// PAS-UX-22: phone-entry validator coverage.
///
/// The PhoneEntryPage form delegates validation to `isValidSAPhoneNumber`
/// and surfaces `kSAOnlyPhoneMessage` on failure. We can't easily pump the
/// full page in a widget test because `AuthViewModel` boots
/// `FirebaseAuth.instance` in its constructor, but the validator IS the
/// gate that decides whether `lookupAndRoute` is called — pinning its
/// behaviour here protects the most important pre-OTP safety check from
/// silent regression.
void main() {
  group('PhoneEntryPage validator (isValidSAPhoneNumber)', () {
    test('accepts SA local format 0XXXXXXXXX', () {
      expect(isValidSAPhoneNumber('0821234567'), isTrue);
      expect(isValidSAPhoneNumber('0721234567'), isTrue);
      expect(isValidSAPhoneNumber('0631234567'), isTrue);
      // 9-prefix range (allocated from 2024).
      expect(isValidSAPhoneNumber('0911234567'), isTrue);
    });

    test('accepts SA E.164 format +27XXXXXXXXX', () {
      expect(isValidSAPhoneNumber('+27821234567'), isTrue);
      expect(isValidSAPhoneNumber('+27721234567'), isTrue);
    });

    test('accepts SA 11-digit no-plus 27XXXXXXXXX', () {
      expect(isValidSAPhoneNumber('27821234567'), isTrue);
    });

    test('accepts whitespace inside an otherwise valid SA number', () {
      // formatPhoneNumber strips non-digits before regex.
      expect(isValidSAPhoneNumber('082 123 4567'), isTrue);
      expect(isValidSAPhoneNumber('+27 82 123 4567'), isTrue);
    });

    test('rejects empty / null', () {
      expect(isValidSAPhoneNumber(null), isFalse);
      expect(isValidSAPhoneNumber(''), isFalse);
    });

    test('rejects non-SA international numbers', () {
      // UK
      expect(isValidSAPhoneNumber('+447700900000'), isFalse);
      // US
      expect(isValidSAPhoneNumber('+12025550100'), isFalse);
      // Naked non-SA digits
      expect(isValidSAPhoneNumber('447700900000'), isFalse);
    });

    test('rejects SA-shaped but invalid prefixes', () {
      // 5-prefix is not an ICASA mobile range.
      expect(isValidSAPhoneNumber('0521234567'), isFalse);
      // Too short.
      expect(isValidSAPhoneNumber('082123'), isFalse);
      // Too long.
      expect(isValidSAPhoneNumber('082123456789'), isFalse);
    });

    test('rejects junk input', () {
      expect(isValidSAPhoneNumber('hello'), isFalse);
      expect(isValidSAPhoneNumber('+'), isFalse);
      expect(isValidSAPhoneNumber('12345'), isFalse);
    });

    test('SA-only message is surfaced as the single source of truth', () {
      // The constant is what PhoneEntryPage shows under the field on
      // validation failure. Pin its presence so a future PR that renames
      // / inlines it has to update this test deliberately.
      expect(kSAOnlyPhoneMessage, contains('SA mobile numbers'));
      expect(kSAOnlyPhoneMessage, contains('0821234567'));
      expect(kSAOnlyPhoneMessage, contains('+27821234567'));
    });
  });

  group('PhoneEntryPage routing assumptions', () {
    test('normalizePhoneNumber yields the lookup key both branches share', () {
      // The new-vs-returning lookup uses the normalized local form as the
      // primary key. Login-typed-as-+27 and registration-typed-as-0 must
      // converge to the same value so a single Firestore doc represents
      // the merchant regardless of how they wrote their number.
      expect(normalizePhoneNumber('+27821234567'), '0821234567');
      expect(normalizePhoneNumber('27821234567'), '0821234567');
      expect(normalizePhoneNumber('0821234567'), '0821234567');
      expect(normalizePhoneNumber('082 123 4567'), '0821234567');
    });

    test('formatPhoneNumber yields the E.164 form passed to Firebase OTP', () {
      // verifyPhoneNumber requires E.164; we send `formatPhoneNumber`'s
      // output. Any drift here would either reject valid SA numbers or
      // pass through unsanitised input.
      expect(formatPhoneNumber('0821234567'), '+27821234567');
      expect(formatPhoneNumber('+27821234567'), '+27821234567');
      expect(formatPhoneNumber('27821234567'), '+27821234567');
    });

    test('non-SA input returns empty from both helpers (refuses to guess)', () {
      // lookupAndRoute relies on this: if formatPhoneNumber returns ''
      // we never hit Firestore and surface the SA-only error instead.
      expect(formatPhoneNumber('+447700900000'), '');
      expect(normalizePhoneNumber('+447700900000'), '');
    });
  });
}
