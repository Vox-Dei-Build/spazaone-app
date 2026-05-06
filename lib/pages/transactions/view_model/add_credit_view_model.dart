import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/templates/sms_message.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:pasella/utils/balance_check_util.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

class AddCreditViewModel extends TransactionViewModel {
  final String customerName;
  final String customerId;
  final String? mobileNumber;
  DateTime repaymentDate = DateTime.now().add(const Duration(days: 30));
  late final DynamicPricingService pricingService;

  AddCreditViewModel({
    required this.customerName,
    required this.customerId,
    this.mobileNumber,
  }) {
    loadProducts();
    _initServices();
  }

  Future<void> _initServices() async {
    pricingService = await DynamicPricingService.initialize();
    notifyListeners();
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

      final creditMessageCost = SMSPricingUtil.calculateCost(
        text: SMSMessages.creditConfirmationShort,
        unitCost: pricingService.smsReminderTemplatePrice,
      );

      bool canProceed = await BalanceCheckUtil.checkBalanceAndProceed(
          context, userId, creditMessageCost);

      if (canProceed) {
        await sendSMS(userId, customerId, amountEntered, customerName, "Credit",
            mobileNumber);
      } else {
        SnackbarComponents.showInsufficientBalance(context);
      }

      DocumentReference customerRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('customers')
          .doc(customerId);

      customerRef.update({
        'lastTransaction': transactionData,
      });

      // Credit-on-ledger sale (BNPL). The customer is bound by construction
      // (this view model takes a customerId/customerName), so customerIsExisting
      // is always true.
      await TelemetryService.instance.capture(SaleCompleted(
        amountBucket: amountBucketZAR(amountEntered),
        isCredit: true,
        customerIsExisting: true,
      ));

      SchedulerBinding.instance.addPostFrameCallback((_) {
        resetFormAndNavigateAway(context);
      });
    } catch (error, st) {
      await CrashService.instance.recordNonFatal(
        error,
        st,
        reason: 'addCreditTransaction failed',
      );
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
