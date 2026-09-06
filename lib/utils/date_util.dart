/// Inclusive end for Firestore range queries using less-than-or-equal.
DateTime endOfCalendarDay(DateTime day) =>
    DateTime(day.year, day.month, day.day + 1)
        .subtract(const Duration(microseconds: 1));

DateTime? convertMapToDateTime(timestampMap) {
  if (timestampMap.containsKey('_seconds')) {
    // Extract seconds and nanoseconds (if necessary)
    int seconds = timestampMap['_seconds'];
    // int nanoseconds = timestampMap['_nanoseconds']; // Uncomment if nanosecond precision is needed
    // Convert to DateTime
    return DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000); // + nanoseconds ~/ 1000000
  }
  return null;
}
