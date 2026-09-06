import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/review_prompt_service.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/shared/billing/cost_sheet_outcome.dart';
import 'package:pasella/shared/billing/optional_transaction_messaging.dart';
import 'package:pasella/templates/sms_message.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:pasella/utils/balance_check_util.dart';
import 'package:pasella/utils/show_toast.dart';

class AddCreditViewModel extends TransactionViewModel {
  final String customerName;
  final String customerId;
  final String? mobileNumber;
  DateTime repaymentDate = DateTime.now().add(const Duration(days: 30));

  /// Cached ranked product suggestions for this customer, computed from
  /// the most recent N credit transactions on this customer's ledger.
  /// Kept in-memory only — refreshed once on construction. We don't
  /// stream this because the surface is a one-shot "what did this
  /// person usually buy?" hint, not a live dashboard.
  List<Product> _suggestedProducts = const [];

  @override
  List<Product> get suggestedProducts => _suggestedProducts;

  /// Max number of recent credit transactions to scan for the
  /// heuristic. Keeps the read bounded and the suggestion list
  /// dominated by current buying patterns rather than ancient ones.
  static const int _historyScanLimit = 10;

  /// Max suggestion chips to surface. Mobile-first: more than this
  /// overflows the horizontal scroller and dilutes signal.
  static const int _maxSuggestions = 5;

  AddCreditViewModel({
    required this.customerName,
    required this.customerId,
    this.mobileNumber,
  }) {
    _initialiseAsync();
  }

  Future<void> _initialiseAsync() async {
    await loadProducts();
    await _loadPreviousProductSuggestions();
  }

  /// Heuristic: rank product IDs from the customer's most recent
  /// [_historyScanLimit] credit transactions by number of transactions
  /// the product appeared in, tiebroken by most-recent appearance.
  /// Filter to products that still exist in inventory with stock > 0 so
  /// a tap on a chip never lands on an invalid add.
  Future<void> _loadPreviousProductSuggestions() async {
    try {
      final snapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('customers')
          .doc(customerId)
          .collection('transactions')
          .orderBy('date', descending: true)
          .limit(_historyScanLimit)
          .get();

      final Map<String, int> frequency = {};
      final Map<String, int> firstSeenAt = {};

      int txIndex = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if ((data['type'] as String?) != 'Credit') {
          txIndex++;
          continue;
        }
        final rawProducts = data['products'];
        if (rawProducts is! Map) {
          txIndex++;
          continue;
        }
        for (final key in rawProducts.keys) {
          final pid = key.toString();
          frequency.update(pid, (v) => v + 1, ifAbsent: () => 1);
          firstSeenAt.putIfAbsent(pid, () => txIndex);
        }
        txIndex++;
      }

      if (frequency.isEmpty) {
        _suggestedProducts = const [];
        notifyListeners();
        return;
      }

      final ranked = frequency.keys.toList()
        ..sort((a, b) {
          final byFreq = frequency[b]!.compareTo(frequency[a]!);
          if (byFreq != 0) return byFreq;
          return firstSeenAt[a]!.compareTo(firstSeenAt[b]!);
        });

      final resolved = <Product>[];
      for (final pid in ranked) {
        if (resolved.length >= _maxSuggestions) break;
        final match = products.firstWhere(
          (p) => p.id == pid,
          orElse: () => Product(),
        );
        if (match.id == null) continue;
        if (match.quantity == null || match.quantity! <= 0) continue;
        resolved.add(match);
      }

      _suggestedProducts = resolved;
      notifyListeners();
    } catch (error, st) {
      await CrashService.instance.recordNonFatal(
        error,
        st,
        reason: 'loadPreviousProductSuggestions failed',
      );
      _suggestedProducts = const [];
    }
  }

  /// Updates the credit's repayment date and notifies listeners. The
  /// previous flow mutated the field directly which left the on-screen
  /// label stale until something else triggered a rebuild.
  void setRepaymentDate(DateTime value) {
    repaymentDate = value;
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

      // Pre-flight cost confirmation. Tri-state outcome:
      //   * send      -> dispatcher charges + SMS goes out
      //   * skip      -> merchant explicitly chose "record only"
      //   * dismissed -> sheet closed without a choice
      // Only send and skip are permission to commit. Closing the drawer
      // asks whether to keep editing or discard before any Firestore or
      // inventory write is allowed.
      final messagingDecision = await chooseOptionalTransactionMessage(
        context,
        mobileNumber: mobileNumber,
        customerName: customerName,
        smsText: SMSMessages.creditConfirmationShort,
        smsPrice: TransactionSmsPrice.credit,
        title: 'Transaction recorded',
        confirmLabel: 'Send confirmation',
      );
      final outcome = messagingDecision.outcome;

      if (!outcome.shouldCommit) {
        if (outcome.shouldDiscard && context.mounted) {
          discardFormAndNavigateAway(context);
        }
        return;
      }

      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          showSnackbar(
            context,
            'You\'re offline. Action queued and will complete when back online.',
            Colors.orange,
          );
        });
      }

      // The ledger row and stock movement happen only after the merchant has
      // explicitly chosen Send confirmation or Done without sending.
      await firestore
          .collection('users')
          .doc(userId)
          .collection('customers')
          .doc(customerId)
          .collection('transactions')
          .add(transactionData);

      // Keep the stock mutation ordered after the ledger write so both are
      // downstream of the same explicit merchant choice.
      for (var productId in selectedProducts.keys) {
        Product? product = products.firstWhere(
          (p) => p.id == productId,
          orElse: () => Product(),
        );
        if (product.quantity != null) {
          await firestore
              .collection('users')
              .doc(userId)
              .collection('products')
              .doc(productId)
              .update({
            'quantity': product.quantity! - selectedProducts[productId]!,
          });
        }
      }

      // Safety net for race conditions (balance changed since the
      // sheet). Affordability gate uses the primary channel cost the
      // user just confirmed.
      var canProceed = false;
      if (messagingDecision.canSend) {
        canProceed = await BalanceCheckUtil.checkBalanceAndProceed(
          context,
          userId,
          messagingDecision.quotedTotal!,
        );
      }

      String successMessage = 'Transaction added successfully.';
      Color successColor = Colors.green;

      if (canProceed) {
        await sendSMS(
          userId,
          customerId,
          amountEntered,
          customerName,
          "Credit",
          mobileNumber,
          pricingSnapshot: messagingDecision.pricingSnapshot!,
        );
        successMessage = 'Transaction added and confirmation sent.';
      } else if (mobileNumber != null && mobileNumber!.isNotEmpty) {
        // Transaction recorded, but the merchant chose not to send a message or the
        // balance gate blocked the send. Keep the confirmation explicit.
        successMessage = 'Transaction added. No message sent.';
        successColor = Colors.blueGrey;
      }

      DocumentReference customerRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('customers')
          .doc(customerId);

      customerRef.update({'lastTransaction': transactionData});

      // Credit-on-ledger sale (BNPL). The customer is bound by construction
      // (this view model takes a customerId/customerName), so customerIsExisting
      // is always true.
      await TelemetryService.instance.capture(
        SaleCompleted(
          amountBucket: amountBucketZAR(amountEntered),
          isCredit: true,
          customerIsExisting: true,
          hasProducts: selectedProducts.isNotEmpty,
          productCountBucket: productCountBucket(selectedProducts.length),
        ),
      );

      // PAS-GROWTH: BNPL sale completed -- another genuine value moment.
      // ReviewPromptService internally throttles, so even a merchant who
      // hits both this and the cash-sale trigger in the same week will see
      // at most one OS prompt every 90 days. Fire-and-forget.
      // ignore: unawaited_futures
      ReviewPromptService.instance.maybePrompt(
        ReviewTrigger.saleCompletedCredit,
      );

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final rootMessenger = ScaffoldMessenger.maybeOf(
              Navigator.of(context, rootNavigator: true).context,
            ) ??
            ScaffoldMessenger.maybeOf(context);
        resetForm();
        rootMessenger?.hideCurrentSnackBar();
        rootMessenger?.showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: successColor,
          ),
        );
        Navigator.of(context).pop();
      });
    } catch (error, st) {
      await CrashService.instance.recordNonFatal(
        error,
        st,
        reason: 'addCreditTransaction failed',
      );
      SchedulerBinding.instance.addPostFrameCallback((_) {
        showErrorSnackBar(context, "Error adding transaction. Please retry.");
      });
    } finally {
      setLoading(false);
    }
  }
}
