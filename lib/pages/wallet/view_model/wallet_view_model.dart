import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/models/wallet/wallet_model.dart';
import 'package:pasella/utils/show_toast.dart';

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
