/// SMS segment + cost calculation aligned with GSM 03.38 / 3GPP TS 23.038
/// and Twilio's billing rules.
///
/// **Why this isn't just `text.length`:**
/// SMS carriers bill per *segment*, not per character. A segment is either
/// 160 septets (GSM-7) or 70 UCS-2 code units (Unicode), and concatenated
/// multipart messages reserve a 6-septet User Data Header (UDH) on every
/// part, shrinking each part to 153 septets / 67 UCS-2 code units. A single
/// non-GSM-7 character anywhere in the body flips the entire message to
/// UCS-2, more than halving the per-segment capacity.
///
/// **History (see `docs/openclaw/pas-sms-01-template-segment-audit.md`):**
/// The previous implementation classified anything with a code unit > 127 as
/// Unicode. This was wrong in both directions and silently mis-quoted SMS
/// cost in the merchant-facing preview:
///
///   * `£`, `É`, `ñ`, `à`, `Ä` and other GSM-7 default-alphabet chars were
///     flagged as Unicode → preview *overcharged*.
///   * `€`, `{`, `}`, `[`, `]`, `~`, `|`, `^`, `\` and `\f` are in the GSM-7
///     extension table and consume 2 septets each. The old code counted
///     them as 1 → preview *undercharged*.
///
/// The current implementation models the GSM 03.38 default + extension
/// tables explicitly and accounts for UDH overhead on multipart messages.
class SMSPricingUtil {
  /// GSM 03.38 default alphabet (7-bit). Each member encodes as exactly
  /// 1 septet on the wire.
  static const String _gsm7Default =
      '@£\$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞ\u001bÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?'
      '¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà';

  /// GSM 03.38 extension table. Each member encodes as 2 septets on the
  /// wire (one ESC followed by the extension code).
  static const String _gsm7Extension = '\u000c^{}\\[~]|€';

  /// Detection result for an SMS body. Public so the UI can surface
  /// *why* a message is multipart (e.g. "contains a non-breaking space").
  static SmsEncodingInfo classify(String text) {
    if (text.isEmpty) {
      return const SmsEncodingInfo(
        encoding: SmsEncoding.gsm7,
        septetLength: 0,
        offendingCharacters: <String>{},
      );
    }

    final offenders = <String>{};
    int septets = 0;
    bool unicodeRequired = false;

    for (final rune in text.runes) {
      // Non-BMP code points (e.g. emoji) require UTF-16 surrogate pairs in
      // UCS-2 → always Unicode.
      if (rune > 0xFFFF) {
        offenders.add(String.fromCharCode(rune));
        unicodeRequired = true;
        continue;
      }
      final char = String.fromCharCode(rune);
      if (_gsm7Default.contains(char)) {
        septets += 1;
      } else if (_gsm7Extension.contains(char)) {
        septets += 2;
      } else {
        offenders.add(char);
        unicodeRequired = true;
      }
    }

    if (unicodeRequired) {
      // For UCS-2 we count UTF-16 code units (matches how carriers
      // measure the wire payload).
      final ucs2Units = text.codeUnits.length;
      return SmsEncodingInfo(
        encoding: SmsEncoding.ucs2,
        septetLength: ucs2Units, // reused field: "code units consumed"
        offendingCharacters: offenders,
      );
    }

    return SmsEncodingInfo(
      encoding: SmsEncoding.gsm7,
      septetLength: septets,
      offendingCharacters: const <String>{},
    );
  }

  static int calculateSegments(String text) {
    final info = classify(text.trim());
    if (info.septetLength == 0) return 1;

    if (info.encoding == SmsEncoding.gsm7) {
      if (info.septetLength <= 160) return 1;
      // Multipart: UDH costs 6 septets per segment → 153 usable.
      return (info.septetLength / 153).ceil();
    }

    if (info.septetLength <= 70) return 1;
    // UCS-2 multipart: UDH costs 1 UCS-2 code unit (= 6 septets) → 67 usable.
    return (info.septetLength / 67).ceil();
  }

  static double calculateCost({
    required String text,
    required double unitCost,
  }) {
    final total = unitCost * calculateSegments(text);
    return double.parse(total.toStringAsFixed(2));
  }
}

/// The encoding scheme the SMS provider will use on the wire.
enum SmsEncoding { gsm7, ucs2 }

/// Structural description of an SMS body's segmentation profile. Returned
/// by [SMSPricingUtil.classify] so UI surfaces (cost confirmation sheet,
/// template editor) can explain *why* a body is multipart instead of just
/// quoting the segment count.
class SmsEncodingInfo {
  /// Which encoding will be used on the wire. UCS-2 has 70-char single
  /// segments vs 160 for GSM-7 — a single non-GSM-7 character anywhere in
  /// the body causes a UCS-2 flip.
  final SmsEncoding encoding;

  /// For GSM-7: total septet count (extension chars cost 2 each).
  /// For UCS-2: total UTF-16 code unit count.
  final int septetLength;

  /// Distinct characters in the body that *forced* the UCS-2 flip. Empty
  /// when [encoding] is [SmsEncoding.gsm7]. Use this to drive a human
  /// explanation, e.g. "Contains a non-breaking space (\u00A0) — message
  /// will cost 2 segments instead of 1".
  final Set<String> offendingCharacters;

  const SmsEncodingInfo({
    required this.encoding,
    required this.septetLength,
    required this.offendingCharacters,
  });

  /// True when the body contains a character that is invisible or near-
  /// invisible on most handsets but forces UCS-2. The two we have seen in
  /// production are U+00A0 NO-BREAK SPACE (from `NumberFormat('en_ZA')`
  /// thousands separator) and U+2013 EN DASH (from typographic-quote copy
  /// in Remote Config / Twilio templates).
  bool get hasInvisibleUnicodeOffender =>
      offendingCharacters.contains('\u00A0') ||
      offendingCharacters.contains('\u2013') ||
      offendingCharacters.contains('\u2014') ||
      offendingCharacters.contains('\u2018') ||
      offendingCharacters.contains('\u2019') ||
      offendingCharacters.contains('\u201C') ||
      offendingCharacters.contains('\u201D');

  /// Human-readable label for the first offending character, suitable for
  /// a one-line warning in the cost preview. Returns `null` for GSM-7
  /// bodies and a generic label if the offender has no friendly name.
  String? get offenderLabel {
    if (encoding == SmsEncoding.gsm7 || offendingCharacters.isEmpty) {
      return null;
    }
    final c = offendingCharacters.first;
    const named = <String, String>{
      '\u00A0': 'non-breaking space (often from currency formatting)',
      '\u2013': 'en-dash (–)',
      '\u2014': 'em-dash (—)',
      '\u2018': 'curly apostrophe (\u2018)',
      '\u2019': 'curly apostrophe (\u2019)',
      '\u201C': 'curly quote (\u201C)',
      '\u201D': 'curly quote (\u201D)',
      '·': 'middle dot (·)',
    };
    if (named.containsKey(c)) return named[c];
    final rune = c.runes.first;
    if (rune > 0xFFFF || (rune >= 0x1F300 && rune <= 0x1FAFF)) {
      return 'an emoji';
    }
    return 'a special character ($c)';
  }
}
