import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/models/common/sms_event.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:pasella/utils/show_toast.dart';

class AddPaymentViewModel extends ChangeNotifier {
  final String customerName;
  final String customerId;
  final String? mobileNumber;
  final TextEditingController amountController = TextEditingController();
  final TextEditingController remarksController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  AddPaymentViewModel({
    required this.customerName,
    required this.customerId,
    this.mobileNumber,
  });

  Future<void> addPaymentTransaction(BuildContext context) async {
    if (_isLoading) return;

    _setLoading(true);

    bool shouldProceed = await isAnonymousGate(context);
    if (!shouldProceed) {
      _setLoading(false);
      return;
    }

    final amountEntered = double.tryParse(amountController.text);
    final remarks = remarksController.text;
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (amountEntered == null || amountEntered <= 0) {
      showSnackbar(context, 'Please check the amount entered.', Colors.red);
      _setLoading(false);
      return;
    }

    if (currentUserId.isEmpty) {
      showSnackbar(context, 'No user is logged in!', Colors.red);
      _setLoading(false);
      return;
    }

    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      showSnackbar(
          context,
          'You\'re offline. Action queued and will complete when back online.',
          Colors.orange);
    }

    var transactionData = {
      'type': 'Payment',
      'amount': amountEntered,
      'date': selectedDate,
      'status': 'PAID',
      'remarks': remarks,
    };

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .doc(customerId)
          .collection('transactions')
          .add(transactionData);

      await _sendSMS(
          currentUserId, customerId, amountEntered, customerName, mobileNumber);

      DocumentReference customerRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .doc(customerId);

      customerRef.update({
        'lastTransaction': transactionData,
      });

      _resetFormAndNavigateAway(context);
    } catch (error) {
      showSnackbar(context, 'Error adding payment. Please retry when online.',
          Colors.red);
      _setLoading(false);
    }
  }

  Future<void> _sendSMS(String currentUserId, String customerId,
      double amountEntered, String customerName, String? mobileNumber) async {
    try {
      MessagingNotificationService smsService = MessagingNotificationService();
      await smsService.sendConfirmationMessage(
        currentUserId,
        customerId,
        "Payment",
        amountEntered,
        customerName,
        mobileNumber,
      );
      eventBus.fire(
          SMSEvent("Payment notification sent successfully :)", success: true));
    } catch (e) {
      // Handle error
    }
  }

  void _resetFormAndNavigateAway(BuildContext context) {
    amountController.clear();
    remarksController.clear();
    _setLoading(false);
    Navigator.of(context).pop();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    amountController.dispose();
    remarksController.dispose();
    super.dispose();
  }
}
