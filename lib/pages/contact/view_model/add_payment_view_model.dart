import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:pasella/utils/balance_check_util.dart';
import 'package:pasella/utils/show_toast.dart';

class AddPaymentViewModel extends TransactionViewModel {
  final String customerName;
  final String customerId;
  final String? mobileNumber;
  late final DynamicPricingService pricingService;

  AddPaymentViewModel({
    required this.customerName,
    required this.customerId,
    this.mobileNumber,
  }) {
    _initServices();
  }

  Future<void> _initServices() async {
    pricingService = await DynamicPricingService.initialize();
    notifyListeners();
  }

  Future<void> addPaymentTransaction(BuildContext context) async {
    if (isLoading) return;

    setLoading(true);

    bool shouldProceed = await isAnonymousGate(context);
    if (!shouldProceed) {
      setLoading(false);
      return;
    }

    final amountEntered = double.tryParse(amountController.text);
    final remarks = remarksController.text;
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (amountEntered == null || amountEntered <= 0) {
      showSnackbar(context, 'Please check the amount entered.', Colors.red);
      setLoading(false);
      return;
    }

    if (currentUserId.isEmpty) {
      showSnackbar(context, 'No user is logged in!', Colors.red);
      setLoading(false);
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

      bool canProceed = await BalanceCheckUtil.checkBalanceAndProceed(
          context, userId, pricingService.smsPaymentTemplatePrice);

      if (canProceed) {
        await sendSMS(currentUserId, customerId, amountEntered, customerName,
            "Payment", mobileNumber);
      } else {
        SnackbarComponents.showInsufficientBalance(context);
      }

      DocumentReference customerRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .doc(customerId);

      customerRef.update({
        'lastTransaction': transactionData,
      });

      resetFormAndNavigateAway(context);
    } catch (error) {
      showSnackbar(context, 'Error adding payment. Please retry when online.',
          Colors.red);
      setLoading(false);
    }
  }
}
