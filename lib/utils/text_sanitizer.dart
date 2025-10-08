String sanitizeMalformedUtf16(String? input) {
  if (input == null || input.isEmpty) {
    return input ?? '';
  }

  final codes = input.codeUnits;
  final buffer = <int>[];

  for (var i = 0; i < codes.length; i++) {
    final codeUnit = codes[i];

    if (_isHighSurrogate(codeUnit)) {
      if (i + 1 < codes.length) {
        final next = codes[i + 1];
        if (_isLowSurrogate(next)) {
          buffer..add(codeUnit)..add(next);
          i++; // Skip the low surrogate we just consumed.
          continue;
        }
      }
      buffer.add(_replacementChar);
      continue;
    }

    if (_isLowSurrogate(codeUnit)) {
      buffer.add(_replacementChar);
      continue;
    }

    buffer.add(codeUnit);
  }

  return String.fromCharCodes(buffer);
}

extension Utf16Sanitizer on String? {
  String sanitized() => sanitizeMalformedUtf16(this);
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

const int _replacementChar = 0xFFFD;
