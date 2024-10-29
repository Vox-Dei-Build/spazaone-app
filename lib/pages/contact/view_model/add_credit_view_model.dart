import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:pasella/utils/show_toast.dart';

class AddCreditViewModel extends TransactionViewModel {
  final String customerName;
  final String customerId;
  final String? mobileNumber;
  DateTime repaymentDate = DateTime.now().add(const Duration(days: 30));

  AddCreditViewModel({
    required this.customerName,
    required this.customerId,
    this.mobileNumber,
  }) {
    loadProducts();
  }

  Future<void> addCreditTransaction(BuildContext context) async {
    setLoading(true);

    if (!await isAnonymousGate(context)) {
      setLoading(false);
      return;
    }

    try {
      final amountEntered = double.tryParse(amountController.text);
      if (amountEntered == null || amountEntered <= 0) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          showSnackbar(context, 'Please check the amount entered.', Colors.red);
        });
        setLoading(false);
        return;
      }

      final transactionData = {
        'type': 'Credit',
        'amount': amountEntered,
        'date': selectedDate,
        'repaymentDate': repaymentDate,
        'remarks': remarksController.text,
        'status': 'DUE',
        'products': selectedProducts,
      };

      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          showSnackbar(
              context,
              'You\'re offline. Action queued and will complete when back online.',
              Colors.orange);
        });
      }

      await firestore
          .collection('users')
          .doc(userId)
          .collection('customers')
          .doc(customerId)
          .collection('transactions')
          .add(transactionData);

      for (var productId in selectedProducts.keys) {
        Product? product = products.firstWhere((p) => p.id == productId,
            orElse: () => Product());
        if (product.quantity != null) {
          await firestore
              .collection('users')
              .doc(userId)
              .collection('products')
              .doc(productId)
              .update({
            'quantity': product.quantity! - selectedProducts[productId]!
          });
        }
      }

      await sendSMS(userId, customerId, amountEntered, customerName, "Credit",
          mobileNumber);

      DocumentReference customerRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('customers')
          .doc(customerId);

      customerRef.update({
        'lastTransaction': transactionData,
      });

      SchedulerBinding.instance.addPostFrameCallback((_) {
        resetFormAndNavigateAway(context);
      });
    } catch (error) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        showErrorSnackBar(
          context,
          "Error adding credit. Please retry. :(",
        );
      });
    } finally {
      setLoading(false);
    }
  }
}
