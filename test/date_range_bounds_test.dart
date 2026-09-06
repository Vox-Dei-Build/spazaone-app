import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/utils/date_util.dart';

void main() {
  test('inclusive activity range includes the entire selected final day', () {
    final end = endOfCalendarDay(DateTime(2026, 9, 4));
    expect(DateTime(2026, 9, 4, 23, 59, 59, 999, 999).isAfter(end), isFalse);
    expect(DateTime(2026, 9, 5).isAfter(end), isTrue);
  });
  test('calendar day end handles month and year boundaries', () {
    expect(endOfCalendarDay(DateTime(2026, 12, 31)),
        DateTime(2027).subtract(const Duration(microseconds: 1)));
    expect(endOfCalendarDay(DateTime(2024, 2, 29)),
        DateTime(2024, 3, 1).subtract(const Duration(microseconds: 1)));
  });
}
