import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/models/wallet/wallet_model.dart';

Future<bool> checkIfBankingDetailsExist(String userId) async {
  var docRef = FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('bankingDetails');
  var snapshot = await docRef.get();
  if (snapshot.docs.isNotEmpty) {
    return true;
  }

  return false;
}

Future<BankingDetails?> fetchBankingDetails(String docId, String userId) async {
  try {
    var docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('bankingDetails')
        .doc(docId);
    var snapshot = await docRef.get();
    if (snapshot.exists) {
      // Converts Firestore data directly into BankingDetails instance
      return BankingDetails.fromFirestore(
          snapshot.data() as Map<String, dynamic>);
    }
    return null; // Return null if document doesn't exist or has no data
  } catch (e) {
    print("Error fetching document: $e");
    return null; // Return null if document doesn't exist or has no data
  }
}

String generateUniqueReference(String merchantId, String customerId) {
  // Simple hashing for demonstration. In practice, consider a more robust approach.
  final rand = Random();
  final timePart =
      DateTime.now().millisecondsSinceEpoch.toString().substring(10);
  final randomPart =
      rand.nextInt(9999).toString().padLeft(4, '0'); // Ensure 4 digits
  return timePart + randomPart; // Combine parts to form reference
}

Future<void> savePaymentReference(
    String merchantId, String customerId, String referenceCode) async {
  var collectionRef =
      FirebaseFirestore.instance.collection('paymentReferences');
  try {
    // Save the new reference code along with merchant and customer IDs
    await collectionRef.add({
      'merchantId': merchantId,
      'customerId': customerId,
      'referenceCode': referenceCode,
    });
  } catch (e) {
    print("Error saving payment reference: $e");
  }
}

Future<String> fetchOrCreatePaymentReference(
    String merchantId, String customerId) async {
  var collectionRef =
      FirebaseFirestore.instance.collection('paymentReferences');
  try {
    var querySnapshot = await collectionRef
        .where('merchantId', isEqualTo: merchantId)
        .where('customerId', isEqualTo: customerId)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      // A reference already exists
      return querySnapshot.docs.first.get('referenceCode') ?? '';
    } else {
      // No reference found, generate and save a new one
      String newReferenceCode = generateUniqueReference(merchantId, customerId);
      await savePaymentReference(merchantId, customerId, newReferenceCode);
      return newReferenceCode;
    }
  } catch (e) {
    print("Error fetching or creating payment reference: $e");
    return '';
  }
}
