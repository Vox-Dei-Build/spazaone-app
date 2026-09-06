import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:pasella/services/store_session.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/models/wallet/banking_detail_model.dart';
import 'package:pasella/pages/wallet/view_model/banking_details_persistence.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/utils/banking_util.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletState {
  final double balance;
  final bool hasBankAccount;
  final bool hasPendingPayout;
  final double cashAdvanceBalance;

  // 🆕 Repayment-related fields
  final double cashAdvanceWithdrawn;
  final double penaltyFee;
  final bool accountSuspended;
  final DateTime? cashAdvanceDueDate;
  final double totalCashAdvanceGiven;
  final double totalCashAdvanceRepaid;
  final double salesVirtualBalance;

  // 🆕 Repayment history (list of repayments)
  final List<Map<String, dynamic>> repaymentHistory;

  WalletState({
    required this.balance,
    required this.hasBankAccount,
    required this.hasPendingPayout,
    required this.cashAdvanceBalance,
    required this.salesVirtualBalance,
    required this.cashAdvanceWithdrawn,
    required this.penaltyFee,
    required this.accountSuspended,
    required this.cashAdvanceDueDate,
    required this.totalCashAdvanceGiven,
    required this.totalCashAdvanceRepaid,
    required this.repaymentHistory,
  });
}

class WalletViewModel extends ChangeNotifier {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;

  // UI Controllers
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController bankName = TextEditingController();
  final TextEditingController accountHolderName = TextEditingController();
  final TextEditingController accountNumber = TextEditingController();
  final TextEditingController accountType = TextEditingController();
  final TextEditingController branchCode = TextEditingController();
  final TextEditingController reference = TextEditingController();

  String? editingDocumentId;
  final String userId = StoreSession.instance.storeId;
  bool _disposed = false;

  // State Notifiers
  final ValueNotifier<bool> isProcessing = ValueNotifier<bool>(false);
  bool isLoading = false;
  final ValueNotifier<bool> isProcessingPayoutRequest =
      ValueNotifier<bool>(false);
  final ValueNotifier<bool> virtualBalance = ValueNotifier<bool>(false);
  // Wallet state stream
  final StreamController<WalletState> _walletStateController =
      StreamController<WalletState>.broadcast();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _walletDocSubscription;
  Stream<WalletState> get walletStateStream => _walletStateController.stream;

  WalletViewModel() {
    _initWalletState();
  }

  /// Fetches max cash advance amount from Remote Config
  Future<double> getMaxCashAdvanceAmount() async {
    final remoteConfigService = await RemoteConfigService.getInstance();
    final String maxAmount =
        remoteConfigService.getString('MAX_CASH_ADVANCE_AMOUNT');

    return double.tryParse(maxAmount) ?? 0.0; // Default to R3000 if not set
  }

  // Initialization
  void _initWalletState() {
    final walletDocRef = firestore
        .collection('users')
        .doc(userId)
        .collection('wallet')
        .doc('current');

    _walletDocSubscription = walletDocRef.snapshots().listen((snapshot) async {
      if (_disposed) return;
      final data = snapshot.data();

      final balance = data?['virtualBalance']?.toDouble() ?? 0.0;
      final cashAdvanceBalance = data?['cashAdvanceBalance']?.toDouble() ?? 0.0;
      final salesVirtualBalance =
          data?['salesVirtualBalance']?.toDouble() ?? 0.0;
      final cashAdvanceWithdrawn =
          data?['cashAdvanceWithdrawn']?.toDouble() ?? 0.0;
      final penaltyFee = data?['penaltyFee']?.toDouble() ?? 0.0;
      final accountSuspended = data?['accountSuspended'] ?? false;

      final cashAdvanceDueDate = data?['cashAdvanceDueDate'] != null
          ? (data!['cashAdvanceDueDate'] as Timestamp).toDate()
          : null;

      final totalCashAdvanceGiven =
          data?['totalCashAdvanceGiven']?.toDouble() ?? 0.0;
      final totalCashAdvanceRepaid =
          data?['totalCashAdvanceRepaid']?.toDouble() ?? 0.0;

      final hasBankAccount = await hasBankingDetails(userId);
      if (_disposed) return;
      final hasPendingPayout = await hasPendingOrProcessingPayout();
      if (_disposed) return;

      final repaymentHistory =
          (data?['repaymentHistory'] as List<dynamic>?)?.map((entry) {
                return {
                  "date": entry['date'] is Timestamp
                      ? (entry['date'] as Timestamp).toDate()
                      : DateTime.tryParse(entry['date']) ?? DateTime.now(),
                  "amount": (entry['amount'] as num).toDouble(),
                  "method": entry['method'] ?? "N/A",
                  "status": entry['status'] ?? "N/A",
                  "reference": entry['reference'] ?? "N/A",
                };
              }).toList() ??
              [];

      _walletStateController.add(WalletState(
        balance: balance,
        hasBankAccount: hasBankAccount,
        hasPendingPayout: hasPendingPayout,
        cashAdvanceBalance: cashAdvanceBalance,
        salesVirtualBalance: salesVirtualBalance,
        cashAdvanceWithdrawn: cashAdvanceWithdrawn,
        penaltyFee: penaltyFee,
        accountSuspended: accountSuspended,
        cashAdvanceDueDate: cashAdvanceDueDate,
        totalCashAdvanceGiven: totalCashAdvanceGiven,
        totalCashAdvanceRepaid: totalCashAdvanceRepaid,
        repaymentHistory: repaymentHistory,
      ));
    });
  }

  static WalletState fromFirestore(Map<String, dynamic> data) {
    return WalletState(
      balance: (data['virtualBalance'] ?? 0.0).toDouble(),
      hasBankAccount: false,
      hasPendingPayout: false,
      salesVirtualBalance: data['salesVirtualBalance']?.toDouble() ?? 0.0,
      cashAdvanceBalance: (data['cashAdvanceBalance'] ?? 0.0).toDouble(),
      cashAdvanceWithdrawn: (data['cashAdvanceWithdrawn'] ?? 0.0).toDouble(),
      penaltyFee: (data['penaltyFee'] ?? 0.0).toDouble(),
      accountSuspended: data['accountSuspended'] ?? false,
      cashAdvanceDueDate: data['cashAdvanceDueDate'] is Timestamp
          ? (data['cashAdvanceDueDate'] as Timestamp).toDate()
          : null,
      totalCashAdvanceGiven: (data['totalCashAdvanceGiven'] ?? 0.0).toDouble(),
      totalCashAdvanceRepaid:
          (data['totalCashAdvanceRepaid'] ?? 0.0).toDouble(),
      repaymentHistory: (data['repaymentHistory'] as List<dynamic>? ?? [])
          .map((item) {
            item['date'] = item['date'] is Timestamp
                ? (item['date'] as Timestamp).toDate()
                : DateTime.tryParse(item['date']) ?? DateTime.now();
            return item;
          })
          .cast<Map<String, dynamic>>()
          .toList(),
    );
  }

  Future<List<Map<String, dynamic>>> fetchMergedTransactionHistory() async {
    try {
      const int limitCount = 20;
      print(
          '📥 [fetchMergedTransactionHistory] Starting with limit: $limitCount');

      print('📡 Fetching top-up transactions...');
      final transactionsFuture = firestore
          .collection('users')
          .doc(userId)
          .collection('topUpTransactions')
          .orderBy('createdAt', descending: true)
          .limit(limitCount)
          .get();

      print('📡 Fetching customer notifications...');
      final notificationsFuture = firestore
          .collection('notifications')
          .doc(userId)
          .collection('customer_notifications')
          .orderBy('timestamp', descending: true)
          .limit(limitCount)
          .get();

      print('📡 Fetching payout requests...');
      final payoutsFuture = firestore
          .collection('payoutRequests')
          .where('merchantId', isEqualTo: userId)
          .orderBy('requestedOn', descending: true)
          .limit(limitCount)
          .get();

      // Fetch all in parallel
      final results = await Future.wait([
        transactionsFuture,
        notificationsFuture,
        payoutsFuture,
      ]);

      final transactionsSnap = results[0];
      final notificationsSnap = results[1];
      final payoutSnap = results[2];

      print('✅ Top-ups fetched: ${transactionsSnap.docs.length}');
      print('✅ Notifications fetched: ${notificationsSnap.docs.length}');
      print('✅ Payouts fetched: ${payoutSnap.docs.length}');

      final mergedList = <Map<String, dynamic>>[];

      for (var tx in transactionsSnap.docs) {
        mergedList.add({
          'type': 'top-up',
          'amount': (tx['amount'] as num?) ?? 0,
          'timestamp':
              (tx['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        });
      }

      for (var notification in notificationsSnap.docs) {
        final data = notification
            .data(); // Ensure you're working with a Map<String, dynamic>
        var message = data['message'] ?? '';
        var templateType = data['templateType'] ?? 'sms';

        final customerDetails =
            data['customer_details'] as Map<String, dynamic>?;

        if (customerDetails != null) {
          final amount = customerDetails['amount']?.toString() ?? '';
          final balance = customerDetails['balance']?.toString() ?? '';
          final shopName = customerDetails['shopName']?.toString() ?? '';
          final customerName = customerDetails['name']?.toString() ?? '';

          message = message
              .replaceAll('{balance}', balance)
              .replaceAll('{shopName}', shopName)
              .replaceAll('{customerName}', customerName)
              .replaceAll('{amount}', amount);
        }

        mergedList.add({
          'type': 'message',
          'message': message,
          'messageCost': (data['messageCost'] as num?) ?? 0,
          'phone': data['customer_phone']?.toString() ?? '',
          'timestamp':
              (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
          'templateType': templateType,
        });
      }

      for (var payout in payoutSnap.docs) {
        final data = payout.data();
        mergedList.add({
          'type': 'payout',
          'amount': (data['amount'] as num?) ?? 0,
          'status': data['payoutStatus'] ?? 'Unknown',
          'timestamp':
              (data['requestedOn'] as Timestamp?)?.toDate() ?? DateTime.now(),
        });
      }

      print('🔄 Sorting merged list of ${mergedList.length} items...');
      mergedList.sort((a, b) {
        final aTime = a['timestamp'] as DateTime;
        final bTime = b['timestamp'] as DateTime;
        return bTime.compareTo(aTime);
      });

      print('✅ Merged transaction history ready. Total: ${mergedList.length}');
      return mergedList;
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'getMergedTransactionHistory failed',
      );
      return [];
    }
  }

  Future<void> requestPayout(BuildContext context, double amount) async {
    isProcessingPayoutRequest.value = true;
    try {
      await FirebaseFirestore.instance.collection('payoutRequests').add({
        'merchantId': userId,
        'amount': amount,
        'payoutStatus': 'pending',
        'status': 'pending',
        'requestedOn': FieldValue.serverTimestamp(),
        'penaltyApplied': false,
        'repaymentDueDate': null,
        'repaymentStatus': 'pending'
      });

      // Backend transitions payoutStatus async; we only see the request here.
      // PayoutCompleted/PayoutFailed (post-transition) must be emitted server-side.
      await TelemetryService.instance.capture(
        PayoutRequested(amountBucket: amountBucketZAR(amount)),
      );

      showSnackbar(
          context,
          'Payout request submitted successfully, we will notify you once transferred.',
          Colors.green);
      Navigator.pushReplacementNamed(context, '/walletPage');
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'requestPayout submission failed',
      );
      // Submission-time failure (e.g. Firestore unreachable). The merchant
      // never reached the pending state, so emit PayoutFailed with a fixed
      // failure_code so the funnel can distinguish it from server rejections.
      await TelemetryService.instance.capture(PayoutFailed(
        amountBucket: amountBucketZAR(amount),
        failureCode: 'client_submit_error',
      ));
      showSnackbar(context, 'Failed to submit payout request.', Colors.red);
    } finally {
      isProcessingPayoutRequest.value = false;
    }
  }

  BankingDetails get bankingDetails => BankingDetails(
        bankName: bankName.text,
        accountHolderName: accountHolderName.text,
        accountNumber: accountNumber.text,
        accountType: accountType.text,
        branchCode: branchCode.text,
        reference: reference.text,
      );

  void _applyBankingDetails(BankingDetails details) {
    bankName.text = details.bankName;
    accountHolderName.text = details.accountHolderName;
    accountNumber.text = details.accountNumber;
    accountType.text = details.accountType;
    branchCode.text = details.branchCode;
    reference.text = details.reference;
  }

  Future<void> initializeBankingDetails() async {
    // Fetch the document and its ID together. A failed read must not look like
    // a missing account or open an empty form over an existing saved account.
    final snapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('bankingDetails')
        .limit(1)
        .get();
    if (_disposed) return;
    final document = snapshot.docs.firstOrNull;
    editingDocumentId = document?.id;
    _applyBankingDetails(BankingDetails.fromFirestore(document?.data() ?? {}));
  }

  Future<bool> hasPendingOrProcessingPayout() async {
    var snapshot = await FirebaseFirestore.instance
        .collection('payoutRequests')
        .where('merchantId', isEqualTo: userId)
        .where('payoutStatus', whereIn: ['pending', 'processing'])
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  Future<void> saveBankingDetails(BankingDetails details) async {
    if (_disposed ||
        StoreSession.instance.storeId != userId ||
        !StoreSession.instance.canManageOperators) {
      throw StateError(
          'Only an owner or administrator of this shop can edit banking details.');
    }
    if (isProcessing.value) {
      throw StateError('Banking details are already saving.');
    }
    isProcessing.value = true;
    try {
      final collectionRef = firestore
          .collection('users')
          .doc(userId)
          .collection('bankingDetails');
      final documentId = await persistBankingDetails(
        details: details,
        documentId: editingDocumentId,
        create: (value) async => (await collectionRef.add(value.toJson())).id,
        update: (id, value) => collectionRef.doc(id).update(value.toJson()),
      );
      if (_disposed) return;
      editingDocumentId = documentId;
      _applyBankingDetails(details);
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'saveBankingDetails failed',
      );
      rethrow;
    } finally {
      if (!_disposed) isProcessing.value = false;
    }
  }

  /// 🔥 Transfer money from Sales Balance to Virtual Balance
  Future<void> transferToVirtualBalance(
      BuildContext context, double amount) async {
    try {
      final operationId = firestore.collection('_operationIds').doc().id;
      await FirebaseFunctions.instance
          .httpsCallable('transferSalesToCampaignCredits')
          .call({
        'storeId': userId,
        'amount': amount,
        'operationId': operationId,
      });
      if (!context.mounted) return;
      showSnackbar(
        context,
        'R$amount moved to your SpazaOne balance.',
        Colors.green,
      );
    } on FirebaseFunctionsException catch (error) {
      if (!context.mounted) return;
      final message = error.message == 'INSUFFICIENT_SALES_BALANCE'
          ? 'Insufficient sales balance.'
          : error.message ?? 'Could not move funds.';
      showSnackbar(context, message, Colors.red);
    } catch (_) {
      if (!context.mounted) return;
      showSnackbar(context, 'Could not move funds.', Colors.red);
    }
  }

  Future<void> _sendWhatsAppMessage(
    BuildContext context, {
    required String Function(String merchantName, String shopName)
        messageBuilder,
  }) async {
    try {
      final String? merchantName = await fetchNameForUser(userId);
      final String? shopName = await fetchShopNameForUser(userId);
      final remoteConfigService = await RemoteConfigService.getInstance();
      final String supportNumber =
          remoteConfigService.getString('WA_SUPPORT_NUMBER');

      if (merchantName == null || shopName == null || supportNumber.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not retrieve required details')),
        );
        return;
      }

      final String formattedNumber =
          formatPhoneNumberForWhatsapp(supportNumber);
      final String message =
          Uri.encodeComponent(messageBuilder(merchantName, shopName));
      final Uri whatsappUri =
          Uri.parse('https://wa.me/$formattedNumber?text=$message');

      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else {
        _showCallSnackbar(context, supportNumber);
      }
    } catch (e, st) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('An error occurred while preparing WhatsApp message')),
      );
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: '_sendWhatsAppMessage launchUrl failed',
      );
    }
  }

  Future<void> requestCashAdvance(BuildContext context,
      {double amount = 500.0}) async {
    await _sendWhatsAppMessage(
      context,
      messageBuilder: (merchant, shop) => "Hi, it's me $merchant,\n\n"
          "I'd like to request a *cash advance* for *$shop* for *R$amount*.\n\n"
          "Please let me know if this is possible. Thanks! 😊",
    );
  }

  Future<void> sendTopUpWhatsAppMessage(BuildContext context,
      {double amount = 100.0}) async {
    await _sendWhatsAppMessage(
      context,
      messageBuilder: (merchant, shop) => "Hi, it's me $merchant 😊,\n\n"
          "I'd like to top up my account at *$shop* with *R$amount*.\n\n"
          "Can you assist me? Thanks! 😊",
    );
  }

  Future<void> sendRepaymentWhatsAppMessage(BuildContext context) async {
    await _sendWhatsAppMessage(
      context,
      messageBuilder: (merchant, shop) => "Hi, it's me $merchant 😊,\n\n"
          "I'd like to repay my cash advance at *$shop*. Can you assist me with this?\n\nThanks! 😊",
    );
  }

  /// Show a Snackbar with a Call button if WhatsApp isn't available
  void _showCallSnackbar(BuildContext context, String phoneNumber) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'WhatsApp is not available. You can call instead.',
        ),
        action: SnackBarAction(
          label: 'Call Now',
          onPressed: () => _makePhoneCall(phoneNumber),
        ),
      ),
    );
  }

  /// Make a direct phone call to the merchant
  void _makePhoneCall(String phoneNumber) async {
    final Uri callUri = Uri.parse('tel:$phoneNumber');

    if (await canLaunchUrl(callUri)) {
      await launchUrl(callUri);
    } else {
      print('Could not launch call to $phoneNumber');
    }
  }

  void resetFields() {
    bankName.clear();
    accountHolderName.clear();
    accountNumber.clear();
    accountType.clear();
    branchCode.clear();
    reference.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    bankName.dispose();
    accountHolderName.dispose();
    accountNumber.dispose();
    accountType.dispose();
    branchCode.dispose();
    reference.dispose();
    isProcessing.dispose();
    isProcessingPayoutRequest.dispose();
    _walletDocSubscription?.cancel();
    _walletStateController.close();
    super.dispose();
  }
}
