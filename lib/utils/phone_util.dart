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

String formatPhoneNumber(String? phoneNumber) {
  if (phoneNumber == null || phoneNumber.isEmpty) return '';

  phoneNumber = cleanPhoneNumber(phoneNumber);

  // Convert the number to SA format if it starts with '0'
  if (phoneNumber.length == 10 && phoneNumber.startsWith('0')) {
    return '+27' + phoneNumber.substring(1);
  } else if (phoneNumber.startsWith('27') && phoneNumber.length == 11) {
    return '+' + phoneNumber;
  }

  return phoneNumber;
}

String formatPhoneNumberForWhatsapp(String? phoneNumber) {
  if (phoneNumber == null || phoneNumber.isEmpty) return '';

  phoneNumber = cleanPhoneNumber(phoneNumber);

  // Convert the number to SA format if it starts with '0'
  if (phoneNumber.length == 10 && phoneNumber.startsWith('0')) {
    return '27' + phoneNumber.substring(1);
  } else if (phoneNumber.startsWith('27') && phoneNumber.length == 11) {
    return phoneNumber;
  }

  return phoneNumber;
}

bool isValidSAPhoneNumber(String? phoneNumber) {
  if (phoneNumber == null || phoneNumber.isEmpty) return false;

  phoneNumber = formatPhoneNumber(phoneNumber);

  final RegExp regex = RegExp(r'^(?:\+27)[6-8][0-9]{8}$');
  return regex.hasMatch(phoneNumber);
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
  return dataMap?['shopName'] as String?;
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
