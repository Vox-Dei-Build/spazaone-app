import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/photo_upload_util.dart';
import 'package:pasella/utils/show_toast.dart';

class CustomerManagementViewModel extends ChangeNotifier {
  final String customerName;
  final String customerId;
  final String? mobileNumber;
  final CustomerBalanceSummaryProvider customerBalanceSummaryProvider;
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  List<Map<String, dynamic>> transactions = [];
  File? _profileImage;
  String? _profileImageUrl;

  final ValueNotifier<bool> sendingReminderNotifier =
      ValueNotifier<bool>(false);
  bool isLoading = false;
  File? get profileImage => _profileImage; // Getter for profile image
  String? get profileImageUrl =>
      _profileImageUrl; // Getter for profile image URL
  final PhotoUploadUtil _photoUploadUtil = PhotoUploadUtil();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController numberController = TextEditingController();

  CustomerManagementViewModel(this.customerId, this.customerName,
      this.customerBalanceSummaryProvider, this.mobileNumber) {
    _loadCustomerDetails();
  }

  /// ✅ **Validation Logic**
  String? validateName() {
    if (nameController.text.trim().isEmpty) {
      return "Name cannot be empty";
    }
    if (nameController.text.trim().length < 3) {
      return "Name must be at least 3 characters";
    }
    return null;
  }

  String? validateNumber() {
    String trimmedNumber = numberController.text.trim();
    if (trimmedNumber.isNotEmpty && trimmedNumber.length < 10) {
      return "Enter a valid mobile number (at least 10 digits)";
    }
    return null;
  }

  /// ✅ **Enables Save Button only if changes are made & values are valid**
  bool get isSaveEnabled {
    return validateName() == null &&
        validateNumber() == null &&
        (nameController.text.trim() != customerName ||
            numberController.text.trim() != (mobileNumber ?? ''));
  }

  Future<void> _loadCustomerDetails() async {
    final DocumentReference customerRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('customers')
        .doc(customerId);

    DocumentSnapshot customerDoc = await customerRef.get();
    Map<String, dynamic> customerData =
        customerDoc.data() as Map<String, dynamic>;
    nameController.text = customerData['name'] ?? '';
    numberController.text = customerData['number'] ?? '';
    _profileImageUrl = customerData['profileImageUrl'];
    notifyListeners();
  }

  Future<void> updateCustomerDetails(BuildContext context) async {
    isLoading = true;
    notifyListeners();

    final DocumentReference customerRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('customers')
        .doc(customerId);

    try {
      String? profileImageUrl;
      if (_profileImage != null) {
        profileImageUrl = await _photoUploadUtil.uploadImage(
            _profileImage!, 'profile_images/$userId/$customerId.jpg');
        _profileImageUrl = profileImageUrl; // Update the local state
      }

      await customerRef.update({
        'name': nameController.text,
        'number': normalizePhoneNumber(numberController.text),
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      });

      showSnackbar(
          context, 'Customer details updated successfully :)', Colors.green);

      Navigator.pop(
          context, profileImageUrl); // Return the new profile image URL
    } catch (error) {
      showErrorSnackBar(
        context,
        "Error updating customer details :(",
      );
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> handleImagePick(BuildContext context) async {
    await _photoUploadUtil.handleImagePick(context, (pickedImage) async {
      if (pickedImage != null) {
        print("📸 New profile image picked: $_profileImage"); // Debug print
        _profileImage = pickedImage;
        notifyListeners(); // 🔥 Ensure UI updates
      }
    });
  }

  Map<String, List<Map<String, dynamic>>> groupTransactionsByDate() {
    Map<String, List<Map<String, dynamic>>> groupedTransactions = {};

    for (var transaction in transactions) {
      if (!groupedTransactions.containsKey(transaction['date'])) {
        groupedTransactions[transaction['date']] = [];
      }
      groupedTransactions[transaction['date']]?.add(transaction);
    }

    // ✅ Sort date keys (ascending order so latest is at the bottom)
    var sortedKeys = groupedTransactions.keys.toList()..sort();

    // ✅ Sort transactions inside each date group
    Map<String, List<Map<String, dynamic>>> sortedGroupedTransactions = {};
    for (var key in sortedKeys) {
      sortedGroupedTransactions[key] = groupedTransactions[key]!
        ..sort((a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(
            b['date']))); // Ensure transactions are sorted within the group
    }

    return sortedGroupedTransactions;
  }

  Stream<List<Map<String, dynamic>>> streamTransactions(
      String userId, String customerId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('customers')
        .doc(customerId)
        .collection('transactions')
        .orderBy('date', descending: true) // order by date
        .snapshots()
        .map((snapshot) {
      List<Map<String, dynamic>> transactions = [];
      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data();
        data['id'] = doc.id;
        if (data['date'] is Timestamp) {
          data['date'] = (data['date'] as Timestamp).toDate().toIso8601String();
        }
        transactions.add(data);
      }
      customerBalanceSummaryProvider.updateForCustomer(transactions);

      return transactions;
    });
  }

  void handleReminderTap(BuildContext context) async {
    if (sendingReminderNotifier.value) return;

    double netBalance =
        customerBalanceSummaryProvider.customerBalanceSummary.netBalance;
    if (netBalance >= 0.0) {
      showSnackbar(
          context, 'Balance is settled. No need for reminders!', Colors.green);
      return;
    }

    bool shouldSend = await _showConfirmationDialog(context);
    if (shouldSend) await _sendReminder(context);
  }

  Future<DateTime?> _getLastReminderSentDate() async {
    var customerDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('customers')
        .doc(customerId)
        .get();

    return customerDoc.data()?['lastReminderSent']?.toDate();
  }

  Future<bool> _showConfirmationDialog(BuildContext context) async {
    return await showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Send Reminder'),
            content: const Text('Do you want to send a payment reminder?'),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                child: const Text('Send'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _sendReminder(BuildContext context) async {
    sendingReminderNotifier.value = true;

    final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    sendingReminderNotifier.value = true;

    // Connectivity check
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      // Inform the user about offline status and action queued
      SchedulerBinding.instance.addPostFrameCallback((_) {
        showSnackbar(
            context,
            'You\'re offline. Action queued and will complete when back online.',
            Colors.orange);
      });
    }

    FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('customers')
        .doc(customerId)
        .update({'lastReminderSent': DateTime.now()}).then((value) async {
      MessagingNotificationService notificationService =
          await MessagingNotificationService.create();
      await notificationService.sendReminderMessage(
          userId, customerId, customerName, mobileNumber);
    }).catchError((error) {
      showSnackbar(context, 'Error adding credit. Please retry when online.',
          Colors.red);
    });

    sendingReminderNotifier.value = false;
  }

  Future<void> deleteCustomer(BuildContext context) async {
    bool confirmDelete = await _showDeleteConfirmationDialog(context);
    if (!confirmDelete) return;

    _setLoading(true);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('customers')
          .doc(customerId)
          .delete();

      showSnackbar(context, 'Customer deleted successfully.', Colors.green);

      // Close the screen or navigate back after deletion
      Navigator.of(context).pop();
    } catch (error) {
      showErrorSnackBar(context, "Error deleting customer :(");
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> _showDeleteConfirmationDialog(BuildContext context) async {
    return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text("Confirm Deletion"),
              content: const Text(
                  "Are you sure you want to delete this customer? This action cannot be undone."),
              actions: <Widget>[
                TextButton(
                  child: const Text("Cancel"),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red, // Red color for delete
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("Delete"),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  set profileImageUrl(String? url) {
    _profileImageUrl = url;
    notifyListeners();
  }

  void _setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    sendingReminderNotifier.dispose();
    nameController.dispose();
    numberController.dispose();
    super.dispose();
  }
}
