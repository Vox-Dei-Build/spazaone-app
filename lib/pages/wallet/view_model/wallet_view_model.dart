import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/models/wallet/banking_detail_model.dart';
import 'package:pasella/pages/wallet/widgets/paystack_form.dart';
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

  // 🆕 Repayment history (list of repayments)
  final List<Map<String, dynamic>> repaymentHistory;

  WalletState({
    required this.balance,
    required this.hasBankAccount,
    required this.hasPendingPayout,
    required this.cashAdvanceBalance,
    required this.cashAdvanceWithdrawn,
    required this.penaltyFee,
    required this.accountSuspended,
    required this.cashAdvanceDueDate,
    required this.totalCashAdvanceGiven,
    required this.totalCashAdvanceRepaid,
    required this.repaymentHistory,
  });
}

class WalletViewModel {
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
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';

  // State Notifiers
  final ValueNotifier<bool> isProcessing = ValueNotifier<bool>(false);
  bool isLoading = false;
  final ValueNotifier<bool> isProcessingPayoutRequest =
      ValueNotifier<bool>(false);
  final ValueNotifier<bool> virtualBalance = ValueNotifier<bool>(false);
  // Wallet state stream
  final StreamController<WalletState> _walletStateController =
      StreamController<WalletState>.broadcast();
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

    walletDocRef.snapshots().listen((snapshot) async {
      final data = snapshot.data();

      final balance = data?['virtualBalance']?.toDouble() ?? 0.0;
      final cashAdvanceBalance = data?['cashAdvanceBalance']?.toDouble() ?? 0.0;
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
      final hasPendingPayout = await hasPendingOrProcessingPayout();

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
      print('🔥 Error fetching merged history: $e\n$st');
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

      showSnackbar(
          context,
          'Payout request submitted successfully, we will notify you once transferred.',
          Colors.green);
      Navigator.pushReplacementNamed(context, '/dashboard');
    } catch (e) {
      print('Error submitting payout request: $e');
      showSnackbar(context, 'Failed to submit payout request.', Colors.red);
    } finally {
      isProcessingPayoutRequest.value = false;
    }
  }

  Future<void> initializeBankingDetails() async {
    editingDocumentId = await checkAndFetchBankingDetailsDocId(userId);
    if (editingDocumentId != null) {
      final details = await fetchBankingDetails(editingDocumentId!, userId);
      if (details != null) {
        bankName.text = details.bankName;
        accountHolderName.text = details.accountHolderName;
        accountNumber.text = details.accountNumber;
        accountType.text = details.accountType;
        branchCode.text = details.branchCode;
        reference.text = details.reference;
      }
    }
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

  Future<void> saveBankingDetails() async {
    isProcessing.value = true;
    try {
      final bankingDetails = BankingDetails(
        bankName: bankName.text.trim(),
        accountHolderName: accountHolderName.text.trim(),
        accountNumber: accountNumber.text.trim(),
        accountType: accountType.text.trim(),
        branchCode: branchCode.text.trim(),
        reference: reference.text.trim(),
      );

      final collectionRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('bankingDetails');

      if (editingDocumentId == null) {
        await collectionRef.add(bankingDetails.toJson());
      } else {
        await collectionRef
            .doc(editingDocumentId)
            .update(bankingDetails.toJson());
      }
    } catch (e) {
      print('Error saving banking details: $e');
    } finally {
      isProcessing.value = false;
    }
  }

  /// 🔥 Transfer money from Cash Advance to Virtual Balance using wallet subcollection
  Future<void> transferToVirtualBalance(
      BuildContext context, double amount) async {
    final walletRef = firestore
        .collection('users')
        .doc(userId)
        .collection('wallet')
        .doc('current');

    await firestore.runTransaction((transaction) async {
      final walletSnapshot = await transaction.get(walletRef);
      if (!walletSnapshot.exists) return;

      final data = walletSnapshot.data();

      double virtualBalance = (data?['virtualBalance'] ?? 0.0).toDouble();
      double cashAdvanceBalance =
          (data?['cashAdvanceBalance'] ?? 0.0).toDouble();

      if (cashAdvanceBalance < amount) {
        showSnackbar(
            context, '❌ Insufficient Cash Advance Balance.', Colors.red);
        return;
      }

      double newVirtualBalance = virtualBalance + amount;
      double newCashAdvanceBalance = cashAdvanceBalance - amount;

      transaction.update(walletRef, {
        'virtualBalance': newVirtualBalance,
        'cashAdvanceBalance': newCashAdvanceBalance,
      });

      showSnackbar(
          context, '✅ R$amount moved to Virtual Balance.', Colors.green);
    });
  }

  /// Open the Paystack Form screen
  void openPaystackForm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const PaystackFormScreen(),
      ),
    );
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('An error occurred while preparing WhatsApp message')),
      );
      print('WhatsApp Error: $e');
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

  void dispose() {
    bankName.dispose();
    accountHolderName.dispose();
    accountNumber.dispose();
    accountType.dispose();
    branchCode.dispose();
    reference.dispose();
    isProcessing.dispose();
    isProcessingPayoutRequest.dispose();
    _walletStateController.close();
  }
}
