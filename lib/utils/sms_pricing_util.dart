class SMSPricingUtil {
  static int calculateSegments(String text) {
    final content = text.trim();
    if (content.isEmpty) return 1;

    final isUnicode = content.runes.any((r) => r > 127);
    final singleSegmentLength = isUnicode ? 70 : 160;
    final multipartSegmentLength = isUnicode ? 67 : 153;

    if (content.length <= singleSegmentLength) {
      return 1;
    }

    return (content.length / multipartSegmentLength).ceil();
  }

  static double calculateCost({
    required String text,
    required double unitCost,
  }) {
    final total = unitCost * calculateSegments(text);
    return double.parse(total.toStringAsFixed(2));
  }
}
