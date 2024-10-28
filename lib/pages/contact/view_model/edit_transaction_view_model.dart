import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/utils/show_toast.dart';

class EditTransactionViewModel extends TransactionViewModel {
  final String customerName;
  final String customerId;
  final Map<String, dynamic> transaction;
  final String transactionId;
  final String transactionType; // Either 'Credit' or 'Payment'
  final String? mobileNumber;
  DateTime repaymentDate = DateTime.now().add(const Duration(days: 30));
  bool _isLoading = false;
  bool _isProductsLoading = false;

  @override
  bool get isLoading => _isLoading;
  bool get isProductsLoading => _isProductsLoading;

  EditTransactionViewModel({
    required this.customerName,
    required this.customerId,
    required this.transaction,
    required this.transactionId,
    required this.transactionType,
    this.mobileNumber,
  }) {
    loadTransactionDetails();
  }

  Future<void> loadTransactionDetails() async {
    try {
      _isProductsLoading = true;
      // Load existing transaction details and populate the fields
      var transactionDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .collection('customers')
          .doc(customerId)
          .collection('transactions')
          .doc(transactionId)
          .get();

      if (transactionDoc.exists) {
        var data = transactionDoc.data()!;
        amountController.text = data['amount'].toString();
        remarksController.text = data['remarks'] ?? '';
        selectedDate = (data['date'] as Timestamp).toDate();
        if (transactionType == 'Credit') {
          repaymentDate = (data['repaymentDate'] as Timestamp).toDate();

          // Load the product IDs and quantities from the transaction
          if (data.containsKey('products') &&
              data['products'] is Map<String, dynamic>) {
            Map<String, dynamic> productsInTransaction = data['products'];

            // Fetch each product detail by productId
            for (var productId in productsInTransaction.keys) {
              var productSnapshot = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser?.uid)
                  .collection('products')
                  .doc(productId)
                  .get();
              if (productSnapshot.exists) {
                Product product =
                    Product.fromMap(productSnapshot.data()!, productId);
                products.add(product); // Store the fetched product
                selectedProducts[productId] = productsInTransaction[
                    productId]; // Map productId to quantity
              }
            }
          }
        }
        notifyListeners();
      }
    } catch (err) {
      print(err);
    } finally {
      _isProductsLoading = false;
    }
  }

  Future<void> updateTransaction(BuildContext context) async {
    if (_isLoading) return;
    _setLoading(true);

    final amountEntered = double.tryParse(amountController.text);
    final remarks = remarksController.text;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

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

    var transactionData = {
      'amount': amountEntered,
      'date': selectedDate,
      'remarks': remarks,
    };

    if (transactionType == 'Credit') {
      transactionData['repaymentDate'] = repaymentDate;
      transactionData['type'] = 'Credit';
      transactionData['products'] = selectedProducts;
    } else {
      transactionData['type'] = 'Payment';
      transactionData['status'] = 'PAID';
    }

    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        showSnackbar(
            context,
            'You\'re offline. Action queued and will complete when back online.',
            Colors.orange);
      });
    }

    try {
      // Fetch the original transaction data
      final originalTransaction = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .doc(customerId)
          .collection('transactions')
          .doc(transactionId)
          .get();

      final originalProducts = originalTransaction.data()?['products'] ?? {};

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .doc(customerId)
          .collection('transactions')
          .doc(transactionId)
          .update(transactionData);

      if (transactionType == 'Credit') {
        // Calculate quantity changes and update stock levels
        // Combine all product IDs from original and selected products
        final allProductIds = {
          ...originalProducts.keys,
          ...selectedProducts.keys
        };

        for (var productId in allProductIds) {
          final originalQuantity = originalProducts[productId] ?? 0;
          final updatedQuantity = selectedProducts[productId] ?? 0;
          final quantityChange = updatedQuantity - originalQuantity;

          if (quantityChange != 0) {
            Product? product = products.firstWhere((p) => p.id == productId,
                orElse: () => Product());
            if (product.quantity != null) {
              await firestore
                  .collection('users')
                  .doc(userId)
                  .collection('products')
                  .doc(productId)
                  .update({
                'quantity': product.quantity! - quantityChange,
              });
            }
          }
        }
      }

      await _sendSMS(
          currentUserId, customerId, amountEntered, customerName, mobileNumber);
      showSnackbar(context, 'Transaction updated successfully!', Colors.green);

      DocumentReference customerRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .doc(customerId);

      customerRef.update({
        'lastTransaction': transactionData,
      });

      SchedulerBinding.instance.addPostFrameCallback((_) {
        _resetFormAndNavigateAway(context);
      });
    } catch (error) {
      showSnackbar(
          context, 'Error updating transaction. Please retry.', Colors.red);
      _setLoading(false);
    }
  }

  Future<void> _sendSMS(String currentUserId, String customerId,
      double amountEntered, String customerName, String? mobileNumber) async {
    try {
      MessagingNotificationService notificationService =
          MessagingNotificationService();
      await notificationService.sendConfirmationMessage(
        currentUserId,
        customerId,
        transactionType,
        amountEntered,
        customerName,
        mobileNumber,
      );
    } catch (e) {
      print(e);
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
}
