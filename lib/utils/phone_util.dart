import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<T?> firestoreExceptionHandler<T>(
    Future<T?> Function() action, String errorMessage) async {
  try {
    return await action();
  } catch (e) {
    print('$errorMessage: $e');
    return null;
  }
}

/// Strict SA mobile number detection.
///
/// All conversions in this file are SA-only and never silently mangle
/// non-SA input. If the input cannot be confidently identified as a SA
/// mobile number, an empty string is returned and downstream validators
/// will reject it via [isValidSAPhoneNumber].
///
/// Accepted SA mobile prefixes: 6, 7, 8, 9 (per ICASA, including the
/// 9-prefix range allocated from 2024 onwards).

/// Shared validator copy. Surfaced verbatim wherever a non-SA number
/// would otherwise be silently rejected — the audit (PAS-UX-08) flagged
/// silent rejection as the #2 friction moment in the merchant flow.
/// Keep this honest: until international support ships, the user has
/// to know SA-only is a real product constraint, not a bug.
const String kSAOnlyPhoneMessage =
    'Pasella currently supports SA mobile numbers only (e.g. 0821234567 or +27821234567).';

// Local 10-digit SA mobile, e.g. 0821234567
final RegExp _saLocalRegex = RegExp(r'^0[6-9][0-9]{8}$');
// E.164 SA mobile, e.g. +27821234567
final RegExp _saE164Regex = RegExp(r'^\+27[6-9][0-9]{8}$');
// 11-digit SA mobile without +, e.g. 27821234567
final RegExp _saCcDigitsRegex = RegExp(r'^27[6-9][0-9]{8}$');

/// Returns the number in E.164 format (`+27XXXXXXXXX`) if it is a valid
/// SA mobile, otherwise an empty string. Never blindly prepends `+27`.
String formatPhoneNumber(String? phoneNumber) {
  if (phoneNumber == null || phoneNumber.isEmpty) return '';

  // Preserve the original prefix to distinguish "+27..." from raw digits.
  final String trimmed = phoneNumber.trim();
  final bool hasPlusPrefix = trimmed.startsWith('+');
  final String digits = cleanPhoneNumber(trimmed);

  if (_saLocalRegex.hasMatch(digits)) {
    return '+27${digits.substring(1)}';
  }
  if (_saCcDigitsRegex.hasMatch(digits)) {
    // Accept "27821234567" or "+27821234567" — both safe.
    return '+$digits';
  }
  if (hasPlusPrefix && _saE164Regex.hasMatch('+$digits')) {
    return '+$digits';
  }
  // Anything else (international, malformed, junk) — refuse to guess.
  return '';
}

/// Formats a customer number for Twilio. Returns empty string for
/// non-SA / invalid numbers — callers MUST guard against this.
String formatForTwilio(String customerNumber, bool isWhatsApp) {
  final String e164 = formatPhoneNumber(customerNumber);
  if (e164.isEmpty) return '';
  return isWhatsApp ? 'whatsapp:$e164' : e164;
}

/// Normalizes to local SA form (`0XXXXXXXXX`). Returns empty string
/// if the number is not a valid SA mobile, rather than silently
/// fabricating a number from the last 9 digits of arbitrary input.
String normalizePhoneNumber(String? rawNumber) {
  if (rawNumber == null || rawNumber.isEmpty) return '';

  final String e164 = formatPhoneNumber(rawNumber);
  if (e164.isEmpty) return '';
  // e164 is "+27XXXXXXXXX"; local form is "0XXXXXXXXX".
  return '0${e164.substring(3)}';
}

/// Returns the WhatsApp-style `27XXXXXXXXX` (no `+`) if SA-valid,
/// otherwise empty string.
String formatPhoneNumberForWhatsapp(String? phoneNumber) {
  if (phoneNumber == null || phoneNumber.isEmpty) return '';

  final String e164 = formatPhoneNumber(phoneNumber);
  if (e164.isEmpty) return '';
  return e164.substring(1); // drop leading '+'
}

bool isValidSAPhoneNumber(String? phoneNumber) {
  if (phoneNumber == null || phoneNumber.isEmpty) return false;
  return formatPhoneNumber(phoneNumber).isNotEmpty;
}

Future<String?> fetchAndFormatPhoneNumber(
    String currentUserId, String customerId) async {
  return await firestoreExceptionHandler<String>(() async {
    String? phoneNumber =
        await getCustomerPhoneNumber(currentUserId, customerId);
    return formatPhoneNumber(phoneNumber);
  }, 'Error occurred while fetching and formatting phone number');
}

Future<String?> fetchAndFormatPhoneNumberForWhatsApp(
    String currentUserId, String customerId) async {
  return await firestoreExceptionHandler<String>(() async {
    String? phoneNumber =
        await getCustomerPhoneNumber(currentUserId, customerId);
    return formatPhoneNumberForWhatsapp(phoneNumber);
  }, 'Error occurred while fetching and formatting phone number');
}

Future<String> fetchShopName() async {
  if (FirebaseAuth.instance.currentUser != null) {
    return (await fetchShopNameForUser(
            FirebaseAuth.instance.currentUser!.uid)) ??
        "";
  }
  return "";
}

String cleanPhoneNumber(String phoneNumber) {
  return phoneNumber.replaceAll(
      RegExp(r'\D'), ''); // Removes non-numeric characters
}

Future<String?> getCustomerPhoneNumber(
    String currentUserId, String customerId) async {
  DocumentSnapshot doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(currentUserId)
      .collection('customers')
      .doc(customerId)
      .get();
  Map<String, dynamic>? dataMap = doc.data() as Map<String, dynamic>?;
  return dataMap?['number'] as String?;
}

Future<String?> fetchShopNameForUser(String currentUserId) async {
  DocumentSnapshot snapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(currentUserId)
      .get();
  Map<String, dynamic>? dataMap = snapshot.data() as Map<String, dynamic>?;
  // PAS-UX-09 follow-up: shopName is optional. Some legacy merchants have
  // an empty string stored from when it was a blank required field; treat
  // empty/whitespace as missing so callers' `?? fallback` chains fire.
  final raw = dataMap?['shopName'];
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Future<String?> fetchNameForUser(String currentUserId) async {
  DocumentSnapshot snapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(currentUserId)
      .get();
  Map<String, dynamic>? dataMap = snapshot.data() as Map<String, dynamic>?;
  return dataMap?['name'] as String?;
}

Future<String?> fetchNumberForUser(String currentUserId) async {
  DocumentSnapshot snapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(currentUserId)
      .get();
  Map<String, dynamic>? dataMap = snapshot.data() as Map<String, dynamic>?;
  return dataMap?['mobileNumber'] as String?;
}
