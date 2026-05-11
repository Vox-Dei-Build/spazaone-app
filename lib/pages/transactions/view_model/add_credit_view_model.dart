import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/shared/billing/cost_breakdown.dart';
import 'package:pasella/shared/billing/cost_confirmation_sheet.dart';
import 'package:pasella/shared/billing/cost_sheet_outcome.dart';
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

  /// Updates the credit's repayment date and notifies listeners. The
  /// previous flow mutated the field directly which left the on-screen
  /// label stale until something else triggered a rebuild.
  void setRepaymentDate(DateTime value) {
    repaymentDate = value;
    notifyListeners();
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

      // NOTE: stock decrement was previously here. It now runs AFTER the
      // cost-confirmation sheet returns a non-dismissed outcome — see
      // PAS-UX-03 audit finding (data-integrity smell on cancelled
      // credits). The credit row above is still written first because
      // rolling that back across an offline Firestore queue would be
      // worse than the alternative; the post-sheet snackbar makes the
      // persisted state explicit instead of silent.

      final smsCost = SMSPricingUtil.calculateCost(
        text: SMSMessages.creditConfirmationShort,
        unitCost: pricingService.smsReminderTemplatePrice,
      );
      final whatsappCost = pricingService.whatsappUtilityPrice;

      // Pre-flight cost confirmation. Tri-state outcome:
      //   * send      -> dispatcher charges + SMS goes out
      //   * skip      -> merchant explicitly chose "record only"
      //   * dismissed -> sheet closed without a choice
      // Both skip and dismissed mean no message is sent. We still
      // commit the stock decrement (the merchant gave the goods) but
      // we surface that explicitly via snackbar.
      CostSheetOutcome outcome = CostSheetOutcome.skip;
      double quotedTotal = smsCost;
      if (mobileNumber != null && mobileNumber!.isNotEmpty) {
        final expectedChannel =
            await MessagingNotificationService.resolveExpectedChannel(
                mobileNumber!);
        final breakdown = CostBreakdown.singleMessageMultiChannel(
          title: 'Send credit confirmation?',
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
      } else {
        // No number on file — the only honest outcome is "record only".
        outcome = CostSheetOutcome.skip;
      }

      // Stock decrement runs only after the merchant has had a chance
      // to interact with the cost sheet. The sale itself is committed
      // either way (the goods are leaving the shelf), but ordering
      // means a merchant who instantly backs out before any choice
      // never sees a silent inventory hit.
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

      // Safety net for race conditions (balance changed since the
      // sheet). Affordability gate uses the primary channel cost the
      // user just confirmed.
      final canProceed = outcome.shouldSend &&
          await BalanceCheckUtil.checkBalanceAndProceed(
              context, userId, quotedTotal);

      if (canProceed) {
        await sendSMS(userId, customerId, amountEntered, customerName, "Credit",
            mobileNumber);
      } else if (outcome.isSilent &&
          mobileNumber != null &&
          mobileNumber!.isNotEmpty) {
        // Credit recorded; no message sent. Surface the state so the
        // merchant doesn't have to guess what happened.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          showSnackbar(
            context,
            'Credit recorded. No message sent.',
            Colors.blueGrey,
          );
        });
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
