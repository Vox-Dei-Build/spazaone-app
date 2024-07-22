import 'package:pasella/models/common/period_filter_model.dart';

DateTime calculateStartDate(TimePeriod period) {
  switch (period) {
    case TimePeriod.today:
      return DateTime.now().subtract(Duration(days: 1));
    case TimePeriod.weekly:
      return DateTime.now().subtract(Duration(days: 7));
    case TimePeriod.monthly:
      return DateTime.now().subtract(Duration(days: 30));
    case TimePeriod.quarter:
      return DateTime.now().subtract(Duration(days: 90));
    default:
      return DateTime(2000); // A distant past date for 'all time'
  }
}

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
