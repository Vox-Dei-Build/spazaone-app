import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Returns the current user's ID. If the user isn't logged in, it'll return an empty string.
  String get currentUserId => _auth.currentUser?.uid ?? '';

  // Fetches the stream of customer data
  Stream<QuerySnapshot> getCustomersStream({required String category}) {
    if (currentUserId.isEmpty) {
      return Stream.empty();
    }

    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('customers')
        .where("category", isEqualTo: category)
        .orderBy("lastTransaction.date", descending: true)
        .snapshots();
  }

  Future<void> triggerBalanceCalculation() async {
    final HttpsCallable callable = FirebaseFunctions.instance
        .httpsCallable('updateBalancesOnTransactionAdded');

    try {
      final HttpsCallableResult result = await callable.call();
      print(result
          .data); // This will print the returned data from the Cloud Function
      return result.data;
    } catch (e) {
      print('Error calling cloud function: $e');
    }
  }

  // Add more methods as required for other Firestore operations.
}
