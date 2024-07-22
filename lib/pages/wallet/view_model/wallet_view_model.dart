import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/models/wallet/wallet_model.dart';
import 'package:pasella/utils/banking_util.dart';

class WalletViewModel {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController accountHolderName = TextEditingController();
  final TextEditingController accountNumber = TextEditingController();
  final TextEditingController flashVendorId = TextEditingController();
  final TextEditingController helloPaisaAccountId = TextEditingController();
  String? editingDocumentId;
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final ValueNotifier<bool> isProcessing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isProcessingPayoutRequest =
      ValueNotifier<bool>(false);

  WalletViewModel();

  Future<void> initializeBankingDetails() async {
    String? docId = await checkAndFetchIfBankingDetailsExist();
    editingDocumentId =
        docId; // Store the document ID (null if no details exist)
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

  Future<String?> checkAndFetchIfBankingDetailsExist() async {
    var docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('bankingDetails');
    var snapshot = await docRef.get();
    if (snapshot.docs.isNotEmpty) {
      return snapshot.docs.first.id;
    }

    return null;
  }

  Future<bool> hasBankAccount() async {
    return await checkIfBankingDetailsExist(userId);
  }

  Future<BankingDetails?> fetchBankingDetails(String docId) async {
    try {
      var docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('bankingDetails')
          .doc(docId);
      var snapshot = await docRef.get();
      if (snapshot.exists) {
        // Converts Firestore data directly into BankingDetails instance
        return BankingDetails.fromFirestore(
            snapshot.data() as Map<String, dynamic>);
      }
      return null; // Return null if document doesn't exist or has no data
    } catch (e) {
      print("Error fetching document: $e");
      return null; // Return null if document doesn't exist or has no data
    }
  }

  Future<bool> hasPendingPayoutRequest() async {
    String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    var payoutRequestsRef =
        FirebaseFirestore.instance.collection('payoutRequests');
    var querySnapshot = await payoutRequestsRef
        .where('merchantId', isEqualTo: userId)
        .where('payoutStatus', isEqualTo: 'pending')
        .limit(
            1) // We only need to find one to know if there's a pending request
        .get();

    return querySnapshot
        .docs.isNotEmpty; // True if there is at least one pending request
  }

  Future<bool> hasProcessingPayoutRequest() async {
    String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    var payoutRequestsRef =
        FirebaseFirestore.instance.collection('payoutRequests');
    var querySnapshot = await payoutRequestsRef
        .where('merchantId', isEqualTo: userId)
        .where('payoutStatus', isEqualTo: 'processing')
        .limit(
            1) // We only need to find one to know if there's a pending request
        .get();

    return querySnapshot
        .docs.isNotEmpty; // True if there is at least one pending request
  }

  Future<void> saveBankingDetails(
      BuildContext context, selectedService, selectedAccountType) async {
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

      var userDocRef =
          FirebaseFirestore.instance.collection('users').doc(userId);

      if (editingDocumentId == null) {
        // Add new document
        await userDocRef
            .collection('bankingDetails')
            .add(bankingDetails.toJson());
      } else {
        // Update existing document
        await userDocRef
            .collection('bankingDetails')
            .doc(editingDocumentId)
            .update(bankingDetails.toJson());
      }

      _showSnackBar(
          context, 'Banking details saved successfully', Colors.green);

      Navigator.pop(context);
    } catch (e) {
      _showSnackBar(
          context,
          'There seems to be an error with saving the details, please try again',
          Colors.red);
    } finally {
      isProcessing.value = false;
    }
  }

  Stream<double> getVirtualBalanceStream() {
    String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    var docRef = FirebaseFirestore.instance.collection('users').doc(userId);

    return docRef.snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return snapshot.data()!.containsKey('virtualBalance')
            ? (snapshot.data()!['virtualBalance'] as num).toDouble()
            : 0.0;
      } else {
        return 0.0;
      }
    });
  }

  void requestPayout(BuildContext context, double amount) async {
    String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    var payoutRequestsRef =
        FirebaseFirestore.instance.collection('payoutRequests');

    try {
      // Create a new payout request
      isProcessingPayoutRequest.value = true;
      await payoutRequestsRef.add({
        'merchantId': userId,
        'amount': amount,
        'payoutStatus': 'pending',
        'status': 'pending', // Initial status
        'requestedOn': FieldValue
            .serverTimestamp(), // Use server timestamp for consistency
      });

      // Optionally, subtract the amount from the merchant's virtual balance
      // Note: Consider transaction or server-side logic to avoid race conditions and ensure data integrity
      var merchantRef =
          FirebaseFirestore.instance.collection('users').doc(userId);
      await merchantRef
          .update({'virtualBalance': FieldValue.increment(-amount)});

      // Provide user feedback
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Payout request submitted successfully'),
          backgroundColor: Colors.green));

      Navigator.of(context).pushReplacementNamed('/dashboard');
    } catch (e) {
      print("Error submitting payout request: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit payout request')));
    } finally {
      isProcessingPayoutRequest.value = false;
    }
  }

  void _showSnackBar(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      duration: Duration(seconds: 2),
    ));
  }

  GlobalKey<FormState> getFormKey() {
    return _formKey;
  }

  void resetFields() {
    // Clear the text fields
    accountHolderName.clear();
    accountNumber.clear();
    flashVendorId.clear();
    helloPaisaAccountId.clear();
  }

  void dispose() {
    accountHolderName.dispose();
    accountNumber.dispose();
    helloPaisaAccountId.dispose();
    flashVendorId.dispose();
    isProcessing.dispose();
    isProcessingPayoutRequest.dispose();
  }
}
