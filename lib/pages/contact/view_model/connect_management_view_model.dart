import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:pasella/templates/sms_message.dart';

class ConnectManagementViewModel {
  final String customerId;
  final ValueNotifier<bool> loadingNotifier = ValueNotifier(false);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';

  ConnectManagementViewModel(this.customerId);

  Stream<List<Map<String, dynamic>>> streamMessages(String customerId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('customers')
        .doc(customerId) // Only get messages for this customer
        .collection('reminders')
        .orderBy('dateSent', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        String messageText = doc['message'] ?? 'No message';

        // Determine if the message was sent by the merchant
        bool isMerchantMessage = _isMerchantMessage(messageText);

        return {
          'message': messageText,
          'dateSent': doc['dateSent']?.toDate() ?? DateTime.now(),
          'isMerchant': isMerchantMessage,
        };
      }).toList();
    });
  }

  // Check if the message matches one of the known merchant templates
  bool _isMerchantMessage(String message) {
    List<String> merchantTemplates = [
      SMSMessages.creditConfirmationSMS,
      SMSMessages.paymentConfirmationSMS,
      SMSMessages.onboardingSMS,
      SMSMessages.reminderSMS,
    ];

    return merchantTemplates
        .any((template) => message.contains(_extractTemplatePrefix(template)));
  }

  // Extracts a small portion of the template for comparison
  String _extractTemplatePrefix(String template) {
    return template.split(" ")[0]; // Get first word as a comparison sample
  }

  void dispose() {
    loadingNotifier.dispose();
  }
}
