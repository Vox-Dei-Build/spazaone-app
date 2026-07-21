import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pasella/services/store_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/shared/billing/cost_breakdown.dart';
import 'package:pasella/shared/billing/cost_confirmation_sheet.dart';
import 'package:pasella/shared/billing/cost_sheet_outcome.dart';
import 'package:pasella/templates/sms_message.dart';
import 'package:pasella/utils/balance_check_util.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

class EditTransactionViewModel extends TransactionViewModel {
  final String customerName;
  final String customerId;
  final Map<String, dynamic> transaction;
  final String transactionId;
  final String transactionType; // Either 'Credit' or 'Payment'
  final String? mobileNumber;
  DateTime repaymentDate = DateTime.now().add(const Duration(days: 30));
  bool _isProductsLoading = false;
  bool get isProductsLoading => _isProductsLoading;
  String get transactionLabel =>
      transactionType == 'Credit' ? 'Transaction' : transactionType;
  late final DynamicPricingService pricingService;

  EditTransactionViewModel({
    required this.customerName,
    required this.customerId,
    required this.transaction,
    required this.transactionId,
    required this.transactionType,
    this.mobileNumber,
  }) {
    loadTransactionDetails();
    _initServices();
  }

  /// Updates the credit's repayment date and notifies listeners.
  void setRepaymentDate(DateTime value) {
    repaymentDate = value;
    notifyListeners();
  }

  Future<void> _initServices() async {
    pricingService = await DynamicPricingService.initialize();
    notifyListeners();
  }

  Future<void> loadTransactionDetails() async {
    try {
      _isProductsLoading = true;
      // Load existing transaction details and populate the fields
      var transactionDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(StoreSession.instance.storeId)
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
                  .doc(StoreSession.instance.storeId)
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
      // Reset the dirty-tracking baseline now that the edit screen has
      // populated the fields with the existing record. Without this the
      // unsaved-changes guard would fire on every Edit because the
      // controllers went from empty to "loaded" after construction.
      markPristine(force: true);
      notifyListeners();
    }
  }

  Future<void> updateTransaction(BuildContext context) async {
    if (isLoading) return;
    setLoading(true);

    final amountEntered = double.tryParse(amountController.text);
    final remarks = remarksController.text;
    final currentUserId = StoreSession.instance.storeId;

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

      final smsCost = SMSPricingUtil.calculateCost(
        text: transactionType == "Credit"
            ? SMSMessages.creditConfirmationShort
            : SMSMessages.paymentConfirmationShort,
        unitCost: transactionType == "Credit"
            ? pricingService.smsReminderTemplatePrice
            : pricingService.smsPaymentTemplatePrice,
      );
      final whatsappCost = pricingService.whatsappUtilityPrice;

      // Pre-flight cost confirmation. Tri-state outcome — explicit
      // skip is now a first-class action, no more silent "cancel == no
      // message". Show both channel prices and bias the highlighted
      // total to whichever channel the dispatcher will most likely
      // use, so the user isn't quoted SMS when they'll actually be
      // charged WhatsApp (or vice versa).
      CostSheetOutcome outcome = CostSheetOutcome.skip;
      double quotedTotal = smsCost;
      if (mobileNumber != null && mobileNumber!.isNotEmpty) {
        final expectedChannel =
            await MessagingNotificationService.resolveExpectedChannel(
                mobileNumber!);
        final breakdown = CostBreakdown.singleMessageMultiChannel(
          title: 'Send updated $transactionLabel notification?',
          subtitle: 'Message to $customerName',
          whatsappCost: whatsappCost,
          smsCost: smsCost,
          expected: expectedChannel,
        );
        quotedTotal = breakdown.total;
        outcome = await CostConfirmationSheet.showOutcome(
          context,
          breakdown: breakdown,
          confirmLabel: 'Send',
        );
      }

      // Safety net for race conditions. Affordability gate uses the
      // primary channel cost the user just confirmed.
      final canProceed = outcome.shouldSend &&
          await BalanceCheckUtil.checkBalanceAndProceed(
              context, currentUserId, quotedTotal);

      if (canProceed) {
        await sendSMS(currentUserId, customerId, amountEntered, customerName,
            transactionType, mobileNumber);
      } else if (outcome.isSilent &&
          mobileNumber != null &&
          mobileNumber!.isNotEmpty) {
        showSnackbar(
          context,
          'Transaction updated. No message sent.',
          Colors.blueGrey,
        );
      }

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
        resetFormAndNavigateAway(context);
      });
    } catch (error) {
      showSnackbar(
          context, 'Error updating transaction. Please retry.', Colors.red);
      setLoading(false);
    }
  }

  /// Deletes the transaction and, for credit transactions, returns the
  /// reserved stock back to inventory. Caller (the form scaffold) is
  /// responsible for the destructive confirmation prompt before invoking
  /// this method.
  Future<void> deleteTransaction(BuildContext context) async {
    if (isLoading) return;
    setLoading(true);
    final currentUserId = StoreSession.instance.storeId;
    if (currentUserId.isEmpty) {
      showSnackbar(context, 'No user is logged in!', Colors.red);
      setLoading(false);
      return;
    }
    try {
      final transactionRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .doc(customerId)
          .collection('transactions')
          .doc(transactionId);

      // For credit transactions, return reserved stock to inventory
      // before deleting the record so the rollback survives even if the
      // delete write fails afterwards.
      if (transactionType == 'Credit') {
        final snapshot = await transactionRef.get();
        final originalProducts =
            (snapshot.data()?['products'] ?? const {}) as Map;
        for (final entry in originalProducts.entries) {
          final productId = entry.key.toString();
          final qty = (entry.value as num?)?.toInt() ?? 0;
          if (qty <= 0) continue;
          final product = products.firstWhere((p) => p.id == productId,
              orElse: () => Product());
          if (product.quantity != null) {
            await firestore
                .collection('users')
                .doc(currentUserId)
                .collection('products')
                .doc(productId)
                .update({'quantity': product.quantity! + qty});
          }
        }
      }

      await transactionRef.delete();

      if (context.mounted) {
        showSnackbar(context, '$transactionLabel deleted.', Colors.green);
        SchedulerBinding.instance.addPostFrameCallback((_) {
          // Pop twice: first close the edit screen, then pop the now-stale
          // transaction detail screen so the user lands back on the
          // ledger/transactions list.
          Navigator.of(context).pop(true);
        });
      }
    } catch (error) {
      if (context.mounted) {
        showSnackbar(context, 'Error deleting $transactionLabel. Please retry.',
            Colors.red);
      }
    } finally {
      setLoading(false);
    }
  }
}
