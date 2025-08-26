import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PaymentService {
  static Future<bool> updateOrderPayment({
    required BuildContext context,
    required String orderId,
    required String action,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in.')),
      );
      return false;
    }
    if (orderId.isEmpty || action.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing order or action.')),
      );
      return false;
    }

    try {
      final fn = FirebaseFunctions.instance.httpsCallable('updateOrderPayment');
      await fn.call({
        'merchantId': uid,
        'orderId': orderId,
        'paymentAction': action,
      });
      final labels = {
        'ACCEPT_BNPL': 'BNPL approved',
        'REJECT_BNPL': 'BNPL rejected',
        'MARK_CASH_RECEIVED': 'Cash received',
        'MARK_COLLECTED': 'Marked as collected',
        'SETTLE_BNPL': 'Marked as paid',
        'CANCEL_ORDER': 'Order cancelled',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(labels[action] ?? 'Updated')),
      );
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[updateOrderPayment] code=${e.code} message=${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to update order')),
      );
      return false;
    } catch (e) {
      debugPrint('[updateOrderPayment] unexpected error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unexpected error. Please try again.')),
      );
      return false;
    }
  }
}
