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
