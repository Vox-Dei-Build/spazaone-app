import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pasella/services/store_session.dart';
import 'package:flutter/material.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/services/payment_receipt_tracker.dart';
import 'package:pasella/shared/billing/cost_breakdown.dart';
import 'package:pasella/shared/billing/cost_confirmation_sheet.dart';
import 'package:pasella/shared/billing/cost_sheet_outcome.dart';
import 'package:pasella/templates/sms_message.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:pasella/utils/balance_check_util.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

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
    final String currentUserId = StoreSession.instance.storeId;

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
      final transactionRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .doc(customerId)
          .collection('transactions')
          .add(transactionData);

      await PaymentReceiptTracker.instance.capture(
        PaymentReceived(
          transactionId: 'ledger_payment:${transactionRef.id}',
          amountBucket: amountBucketZAR(amountEntered),
          source: 'ledger_repayment',
          method: 'manual',
        ),
      );

      final smsCost = SMSPricingUtil.calculateCost(
        text: SMSMessages.paymentConfirmationShort,
        unitCost: pricingService.smsPaymentTemplatePrice,
      );
      final whatsappCost = pricingService.whatsappUtilityPrice;

      // Pre-flight cost confirmation sheet — user explicitly confirms
      // the deduction before it happens (no surprise charge). The sheet
      // returns a tri-state outcome:
      //   * send      -> dispatcher is allowed to charge + send
      //   * skip      -> merchant explicitly chose "record only"
      //   * dismissed -> sheet was closed without an explicit choice
      // skip and dismissed both keep the recorded payment but skip the
      // SMS. We surface a snackbar in either case so the merchant is
      // never left guessing whether anything went out.
      CostSheetOutcome outcome = CostSheetOutcome.skip;
      double quotedTotal = smsCost;
      if (mobileNumber != null && mobileNumber!.isNotEmpty) {
        final expectedChannel =
            await MessagingNotificationService.resolveExpectedChannel(
                mobileNumber!);
        final breakdown = CostBreakdown.singleMessageMultiChannel(
          title: 'Send payment confirmation?',
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
        // No mobile number on file — there was never a message path,
        // so the only honest outcome is "skip" (record only). No sheet,
        // no surprise.
        outcome = CostSheetOutcome.skip;
      }

      // Safety net for race conditions (balance changed between sheet
      // and dispatch). Keeps the legacy "Insufficient Balance" dialog
      // as a last-resort fallback only — should rarely fire now.
      // Affordability gate uses the primary channel cost the user just
      // confirmed.
      final canProceed = outcome.shouldSend &&
          await BalanceCheckUtil.checkBalanceAndProceed(
              context, userId, quotedTotal);

      if (canProceed) {
        await sendSMS(currentUserId, customerId, amountEntered, customerName,
            "Payment", mobileNumber);
      } else if (outcome.isSilent &&
          mobileNumber != null &&
          mobileNumber!.isNotEmpty) {
        // The payment is recorded but the merchant chose not to send
        // (or dismissed the sheet). Surface that explicitly so the
        // post-action state is never invisible.
        showSnackbar(
          context,
          'Payment recorded. No message sent.',
          Colors.blueGrey,
        );
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
