import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/dashboard/dashboard.dart';

void main() {
  group('shouldShowSpazaOneRebrandNotice', () {
    final now = DateTime.utc(2026, 7, 14, 12);

    test('shows for an existing Pasella account', () {
      expect(
        shouldShowSpazaOneRebrandNotice(
          accountCreatedAt: now.subtract(const Duration(days: 30)),
          now: now,
        ),
        isTrue,
      );
    });

    test('skips a newly created SpazaOne account', () {
      expect(
        shouldShowSpazaOneRebrandNotice(
          accountCreatedAt: now.subtract(const Duration(minutes: 10)),
          now: now,
        ),
        isFalse,
      );
    });

    test('shows when the account creation date is unavailable', () {
      expect(
        shouldShowSpazaOneRebrandNotice(
          accountCreatedAt: null,
          now: now,
        ),
        isTrue,
      );
    });
  });
}
