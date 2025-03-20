import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/models/wallet/wallet_model.dart';
import 'package:pasella/pages/wallet/widgets/paystack_form.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletState {
  final double balance;
  final bool hasBankAccount;
  final bool hasPendingPayout;

  WalletState({
    required this.balance,
    required this.hasBankAccount,
    required this.hasPendingPayout,
  });
}

class WalletViewModel {
  // UI Controllers
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController accountHolderName = TextEditingController();
  final TextEditingController accountNumber = TextEditingController();
  final TextEditingController flashVendorId = TextEditingController();
  final TextEditingController helloPaisaAccountId = TextEditingController();

  String? editingDocumentId;
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';

  // State Notifiers
  final ValueNotifier<bool> isProcessing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isProcessingPayoutRequest =
      ValueNotifier<bool>(false);

  // Wallet state stream
  final StreamController<WalletState> _walletStateController =
      StreamController<WalletState>.broadcast();
  Stream<WalletState> get walletStateStream => _walletStateController.stream;

  WalletViewModel() {
    _initWalletState();
  }

  // Initialization
  void _initWalletState() {
    FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen((snapshot) async {
      final balance = snapshot.data()?['virtualBalance']?.toDouble() ?? 0.0;
      final hasBankAccount = await hasBankingDetails();
      final hasPendingPayout = await hasPendingOrProcessingPayout();

      _walletStateController.add(WalletState(
        balance: balance,
        hasBankAccount: hasBankAccount,
        hasPendingPayout: hasPendingPayout,
      ));
    });
  }

  // Check Banking Details
  Future<bool> hasBankingDetails() async {
    var snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('bankingDetails')
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  Future<String?> checkAndFetchBankingDetailsDocId() async {
    var snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('bankingDetails')
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty ? snapshot.docs.first.id : null;
  }

  Future<void> initializeBankingDetails() async {
    editingDocumentId = await checkAndFetchBankingDetailsDocId();
    if (editingDocumentId != null) {
      final details = await fetchBankingDetails(editingDocumentId!);
      if (details != null) {
        accountHolderName.text = details.accountHolderName;
        accountNumber.text = details.accountNumber;
        // You can set additional fields here if applicable
      }
    }
  }

  /// Open the Paystack Form screen
  void openPaystackForm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const PaystackFormScreen(),
      ),
    );
  }

  /// Send a prefilled WhatsApp message with merchant and shop details
  Future<void> sendWhatsAppMessage(BuildContext context,
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

  Future<BankingDetails?> fetchBankingDetails(String docId) async {
    try {
      var snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('bankingDetails')
          .doc(docId)
          .get();
      if (snapshot.exists && snapshot.data() != null) {
        return BankingDetails.fromFirestore(snapshot.data()!);
      }
      return null;
    } catch (e) {
      print('Error fetching banking details: $e');
      return null;
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

  Future<void> saveBankingDetails(BuildContext context, String selectedService,
      String selectedAccountType) async {
    isProcessing.value = true;
    try {
      BankingDetails bankingDetails = BankingDetails(
        selectedService: selectedService,
        selectedAccountType: selectedAccountType,
        accountHolderName: accountHolderName.text,
        accountNumber: accountNumber.text,
        referenceCode: selectedService == 'Flash'
            ? flashVendorId.text
            : helloPaisaAccountId.text,
      );

      var collectionRef = FirebaseFirestore.instance
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

      showSnackbar(context, 'Banking details saved successfully', Colors.green);
      Navigator.pop(context);
    } catch (e) {
      print('Error saving banking details: $e');
      showSnackbar(
          context, 'Failed to save details, please try again.', Colors.red);
    } finally {
      isProcessing.value = false;
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
      });

      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'virtualBalance': FieldValue.increment(-amount),
      });

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

  String? findBankByAccountNumber(
      String selectedService, String accountNumber) {
    Map<String, String>? serviceDetails =
        predefinedAccountDetails[selectedService];
    if (serviceDetails != null) {
      // Iterate through the map to find which bank has the matching account number.
      for (var entry in serviceDetails.entries) {
        if (entry.value == accountNumber && entry.key != 'AccountName') {
          return entry.key; // Return the matching bank's name.
        }
      }
    }
    return null; // Return null if no matching bank is found or the service doesn't exist.
  }

  Future<void> refreshBalance() async {
    // Call Firestore to update balance (or fetch latest)
  }

  void resetFields() {
    accountHolderName.clear();
    accountNumber.clear();
    flashVendorId.clear();
    helloPaisaAccountId.clear();
  }

  void dispose() {
    accountHolderName.dispose();
    accountNumber.dispose();
    flashVendorId.dispose();
    helloPaisaAccountId.dispose();
    isProcessing.dispose();
    isProcessingPayoutRequest.dispose();
    _walletStateController.close();
  }
}
