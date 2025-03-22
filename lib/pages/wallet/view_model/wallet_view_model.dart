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
    final walletDocRef = FirebaseFirestore.instance
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

      /*  await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'cashAdvanceBalance': FieldValue.increment(-amount),
      }); */

      showSnackbar(
          context, 'Payout request submitted successfully', Colors.green);
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

  /// Request a Cash Advance via WhatsApp
  Future<void> requestCashAdvance(BuildContext context,
      {double amount = 500.0}) async {
    try {
      // Fetch merchant details
      final String? merchantName = await fetchNameForUser(userId);
      final String? shopName = await fetchShopNameForUser(userId);

      // Fetch WhatsApp Support Number from Remote Config
      final remoteConfigService = await RemoteConfigService.getInstance();
      final String merchantNumber =
          remoteConfigService.getString('WA_SUPPORT_NUMBER');

      if (merchantName == null || shopName == null || merchantNumber.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not retrieve required details')),
        );
        return;
      }

      // Ensure phone number is correctly formatted
      final String formattedNumber =
          formatPhoneNumberForWhatsapp(merchantNumber);

      // Construct WhatsApp message
      final String message = Uri.encodeComponent(
          "Hi, it's me $merchantName,\n\n"
          "I'd like to request a *cash advance* for *$shopName* for *R$amount*.\n\n"
          "Please let me know if this is possible. Thanks! 😊");

      // Construct WhatsApp URL
      final Uri whatsappUri =
          Uri.parse('https://wa.me/$formattedNumber?text=$message');

      // Try launching WhatsApp
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else {
        _showCallSnackbar(context, merchantNumber);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('An error occurred while preparing WhatsApp message')),
      );
      print('Error sending WhatsApp message: $e');
    }
  }

  /// Send a prefilled WhatsApp message with merchant and shop details
  Future<void> sendTopUpWhatsAppMessage(BuildContext context,
      {double amount = 100.0}) async {
    try {
      // Fetch merchant details
      final String? merchantName = await fetchNameForUser(userId);
      final String? shopName = await fetchShopNameForUser(userId);

      // Fetch WhatsApp Support Number from Remote Config
      final remoteConfigService = await RemoteConfigService.getInstance();
      final String merchantNumber =
          remoteConfigService.getString('WA_SUPPORT_NUMBER');

      if (merchantName == null || shopName == null || merchantNumber.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not retrieve required details')),
        );
        return;
      }

      // Ensure phone number is correctly formatted
      final String formattedNumber =
          formatPhoneNumberForWhatsapp(merchantNumber);

      // Construct WhatsApp message
      final String message = Uri.encodeComponent(
          "Hi, it's me $merchantName 😊,\n\n"
          "I'd like to top up my account at *$shopName* with *R$amount*.\n\n"
          "Can you assist me? Thanks! 😊");

      // Construct WhatsApp URL
      final Uri whatsappUri =
          Uri.parse('https://wa.me/$formattedNumber?text=$message');

      // Check if WhatsApp can be launched
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else {
        _showCallSnackbar(context, merchantNumber);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('An error occurred while preparing WhatsApp message')),
      );
      print('Error sending WhatsApp message: $e');
    }
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

  Future<void> sendRepaymentWhatsAppMessage(BuildContext context) async {
    try {
      // Fetch merchant details
      final String? merchantName = await fetchNameForUser(userId);
      final String? shopName = await fetchShopNameForUser(userId);

      // Fetch WhatsApp Support Number from Remote Config
      final remoteConfigService = await RemoteConfigService.getInstance();
      final String merchantNumber =
          remoteConfigService.getString('WA_SUPPORT_NUMBER');

      if (merchantName == null || shopName == null || merchantNumber.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not retrieve required details')),
        );
        return;
      }

      // Ensure phone number is correctly formatted
      final String formattedNumber =
          formatPhoneNumberForWhatsapp(merchantNumber);

      // Construct WhatsApp message specifically for repayment
      final String message = Uri.encodeComponent(
          "Hi, it's me $merchantName 😊,\n\n"
          "I'd like to repay my cash advance at *$shopName*. Can you assist me with this?\n\nThanks! 😊");

      // Construct WhatsApp URL
      final Uri whatsappUri =
          Uri.parse('https://wa.me/$formattedNumber?text=$message');

      // Check if WhatsApp can be launched
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Cannot launch WhatsApp. Please contact $merchantNumber directly.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('An error occurred while preparing WhatsApp message')),
      );
      print('Error sending WhatsApp repayment message: $e');
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
