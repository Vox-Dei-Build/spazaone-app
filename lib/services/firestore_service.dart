import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/templates/sms_message.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String get userId => StoreSession.instance.storeId;

  // Returns the current user's ID. If the user isn't logged in, it'll return an empty string.
  String get currentUserId => StoreSession.instance.storeId;

  // Fetches the stream of customer data
  Stream<QuerySnapshot> getCustomersStream({required String category}) {
    if (currentUserId.isEmpty) {
      return const Stream.empty();
    }

    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('customers')
        .where("category", isEqualTo: category)
        .orderBy("lastTransaction.date", descending: true)
        .snapshots();
  }

  Future<List<Map<String, dynamic>>> fetchMessages(String customerId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('customers')
        .doc(customerId)
        .collection('reminders')
        .orderBy('dateSent', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      return {
        'message': doc['message'] ?? 'No message',
        'dateSent': doc['dateSent']?.toDate() ?? DateTime.now(),
        'isMerchant': _isMerchantMessage(doc['message']),
      };
    }).toList();
  }

  // Check if the message matches one of the known merchant templates
  bool _isMerchantMessage(String message) {
    List<String> merchantTemplates = [
      SMSMessages.creditConfirmationShort,
      SMSMessages.paymentConfirmationShort,
      SMSMessages.onboardingShort,
      SMSMessages.reminderShort,
    ];

    return merchantTemplates
        .any((template) => message.contains(_extractTemplatePrefix(template)));
  }

  // Extracts a small portion of the template for comparison
  String _extractTemplatePrefix(String template) {
    return template.split(" ")[0]; // Get first word as a comparison sample
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
