import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pasella/services/store_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/services/orders_unread_clear.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/shared/billing/cost_breakdown.dart';
import 'package:pasella/shared/billing/cost_confirmation_sheet.dart';
import 'package:pasella/utils/balance_check_util.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/photo_upload_util.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/utils/sms_pricing_util.dart';
import 'package:pasella/templates/sms_message.dart';

class CustomerManagementViewModel extends ChangeNotifier {
  final String customerName;
  final String customerId;
  final String? mobileNumber;
  final CustomerBalanceSummaryProvider customerBalanceSummaryProvider;
  final String userId = StoreSession.instance.storeId;
  List<Map<String, dynamic>> transactions = [];
  File? _profileImage;
  String? _profileImageUrl;
  int _profileImageRevision = 0;
  late final DynamicPricingService pricingService;
  final ValueNotifier<bool> sendingReminderNotifier =
      ValueNotifier<bool>(false);
  bool isLoading = false;
  File? get profileImage => _profileImage; // Getter for profile image
  String? get profileImageUrl =>
      _profileImageUrl; // Getter for profile image URL
  String? get profileImageDisplayUrl {
    final url = _profileImageUrl;
    if (url == null || url.isEmpty || _profileImageRevision == 0) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}v=$_profileImageRevision';
  }

  final PhotoUploadUtil _photoUploadUtil = PhotoUploadUtil();
  late final MessagingNotificationService notificationService;
  bool hasWhatsApp = false;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController numberController = TextEditingController();
  int unreadMessagesCount = 0;
  int ordersUnreadCount = 0;
  bool _disposed = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _messagesUnreadSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _ordersUnreadSub;

  CustomerManagementViewModel(this.customerId, this.customerName,
      this.customerBalanceSummaryProvider, this.mobileNumber) {
    _loadCustomerDetails();
    _initServices();
  }

  Future<void> _initServices() async {
    _setLoading(true);
    try {
      notificationService = await MessagingNotificationService.create();
      if (_disposed) return;
      pricingService = await DynamicPricingService.initialize();
      if (_disposed) return;
      hasWhatsApp = (mobileNumber != null)
          ? await notificationService
              .isWhatsAppEnabled(normalizePhoneNumber(mobileNumber))
          : false;
      if (_disposed) return;

      fetchNumberOfUnreadMessages(); // (messages) already in your code
      _listenOrdersUnread(); // 👈 NEW: orders
      _setLoading(false);
    } catch (e) {
      if (_disposed) return;
      _setLoading(false);
    }
    if (_disposed) return;
    notifyListeners();
  }

  void fetchNumberOfUnreadMessages() async {
    try {
      // ✅ Listen for unread messages from Firestore **for this customer only**
      _messagesUnreadSub?.cancel();
      _messagesUnreadSub = FirebaseFirestore.instance
          .collection('users')
          .doc(userId) // 🔥 Replace with actual merchant ID
          .snapshots()
          .listen((snapshot) {
        // Stream cancellation is async (returns a Future); events already
        // queued before cancel() completes can still arrive after the
        // view-model has been disposed. Guard the callback so we don't
        // mutate state or notify on a disposed ChangeNotifier.
        if (_disposed) return;
        if (snapshot.exists) {
          var unreadMessages = snapshot.data()?['unreadMessages'] ?? [];

          // 🔥 Filter messages for this specific `customerId`. V1 truth-
          // surface: outbound bot mirrors share the unreadMessages array but
          // should not ring the merchant's bell — only inbound entries count.
          var filteredMessages = unreadMessages
              .where((msg) =>
                  msg['customerNumber'] == mobileNumber &&
                  (msg['direction'] == null ||
                      msg['direction'].toString().toLowerCase() == 'inbound') &&
                  msg['isRead'] != true)
              .toList();

          unreadMessagesCount = filteredMessages.length;

          notifyListeners();
        }
      });
    } catch (e) {}
  }

  void _listenOrdersUnread() {
    // Listen to users/{uid}/customers/{customerId}.ordersUnreadCount
    final uid = userId;
    if (uid.isEmpty) return;

    _ordersUnreadSub?.cancel();
    _ordersUnreadSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('customers')
        .doc(customerId)
        .snapshots()
        .listen((doc) {
      // Same disposal race as _messagesUnreadSub: cancel() is async, so
      // late events may arrive post-dispose.
      if (_disposed) return;
      if (doc.exists) {
        ordersUnreadCount = (doc.data()?['ordersUnreadCount'] as int?) ?? 0;
        notifyListeners();
      }
    });
  }

  Future<void> clearOrdersUnread() async {
    final uid = userId;
    if (uid.isEmpty) return;
    await OrdersUnreadClearService.clearForCustomer(
      merchantId: uid,
      customerId: customerId,
    );
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
    final String trimmed = numberController.text.trim();
    // Optional field: empty is OK (matches add-contact behavior).
    if (trimmed.isEmpty) return null;
    if (!isValidSAPhoneNumber(trimmed)) {
      return 'Enter a valid SA mobile number';
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
    if (_disposed) return;
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
        final String? previousUrl = _profileImageUrl;
        profileImageUrl = await _photoUploadUtil.uploadImage(
            _profileImage!, 'profile_images/$userId/$customerId.jpg');

        if (profileImageUrl != null) {
          await _evictProfileImageCache(previousUrl);
          if (profileImageUrl != previousUrl) {
            await _evictProfileImageCache(profileImageUrl);
          }
          _profileImageUrl = profileImageUrl;
          // Firebase Storage keeps the same download URL when the customer
          // image is overwritten at the same path. Give the active profile
          // surface a new request identity so its existing image stream
          // cannot continue displaying the previous bytes after navigation
          // returns from Edit Customer.
          _profileImageRevision = DateTime.now().microsecondsSinceEpoch;
          _profileImage = null;
        }
      }

      await customerRef.update({
        'name': nameController.text,
        'number': normalizePhoneNumber(numberController.text),
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      });

      // PAS-UX-16: CustomerUpdated. `hasImage` reflects whether a new
      // image was uploaded as part of THIS edit, not whether the
      // customer has a photo at all — the funnel cares about edit-time
      // image attach behaviour. Fire-and-forget.
      // ignore: unawaited_futures
      TelemetryService.instance
          .capture(CustomerUpdated(hasImage: profileImageUrl != null));

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

  Future<void> _evictProfileImageCache(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      await CachedNetworkImage.evictFromCache(url);
    } catch (_) {
      // Never let cache eviction failure mask a successful upload.
    }
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

    // Compute both channel costs up-front so the user sees an
    // accurate, channel-aware quote on the confirmation sheet
    // (replaces the cost-blind "Send reminder?" alert dialog and the
    // SMS-only quote that under/over-quoted the actual deduction).
    final smsCost = SMSPricingUtil.calculateCost(
      text: SMSMessages.reminderShort,
      unitCost: pricingService.smsReminderTemplatePrice,
    );
    final whatsappCost = pricingService.whatsappUtilityPrice;

    if (mobileNumber == null || mobileNumber!.isEmpty) {
      // No phone number on file — nothing to send. Bail before the
      // sheet so the user isn't asked to confirm a no-op.
      showSnackbar(
          context, 'No phone number on file for this customer.', Colors.orange);
      return;
    }

    final expectedChannel =
        await MessagingNotificationService.resolveExpectedChannel(
            mobileNumber!);

    // Reminder send is a pure side-effect (nothing to "record" if the
    // merchant doesn't send), so the legacy bool API still maps cleanly:
    // user explicitly confirms -> send, anything else -> do nothing.
    // No silent state to surface.
    //
    // PAS-UX-12: There is no underlying record being saved alongside this
    // dispatch — the reminder *is* the action — so the "Save without
    // sending" secondary button is suppressed (`showSkip: false`).
    // Merchants who change their mind dismiss via the close (X) icon in
    // the sheet header (or back gesture / scrim), all of which map to
    // dismissed and result in no send.
    final shouldSend = await CostConfirmationSheet.show(
      context,
      breakdown: CostBreakdown.singleMessageMultiChannel(
        title: 'Send payment reminder?',
        subtitle: 'Message to $customerName',
        whatsappCost: whatsappCost,
        smsCost: smsCost,
        expected: expectedChannel,
      ),
      confirmLabel: 'Send Reminder',
      showSkip: false,
    );

    if (shouldSend) await _sendReminder(context);
  }

  // PAS-WA-V1: Reminder caps audit. Historic versions of this app
  // gated reminders to "once per month" via a `lastReminderSent`
  // cooldown read here. Pasella now charges per send (paid-usage
  // model), so a count-based cap is invalid — merchants pay for the
  // value they get and the only legitimate gates are: (1) settled
  // balance, (2) phone-on-file, (3) wallet credit. The previous
  // helper was already orphaned (no callers in `lib/`) but is
  // removed outright to make the audit conclusion explicit and stop
  // future readers reintroducing a cap by re-wiring it.
  //
  // `lastReminderSent` is still written on each send (see
  // `_sendReminder`) and read by the reports tile for a purely
  // cosmetic "reminder sent recently" badge — that surface is the
  // only legitimate consumer.
  Future<void> _sendReminder(BuildContext context) async {
    sendingReminderNotifier.value = true;

    final String userId = StoreSession.instance.storeId;
    double netBalance =
        customerBalanceSummaryProvider.customerBalanceSummary.netBalance;

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

    // PAS-WA-V1: balance check must cover the worst-case channel
    // cost. The dispatcher decides WhatsApp-vs-SMS at send-time
    // (including a 30-day recheck for stale "no" cache entries), so
    // we cannot know in advance which price will be deducted. Gate
    // on the larger of the two so the wallet can never be driven
    // negative by a fallback we didn't quote against.
    final smsCost = SMSPricingUtil.calculateCost(
      text: SMSMessages.reminderShort,
      unitCost: pricingService.smsReminderTemplatePrice,
    );
    final whatsappCost = pricingService.whatsappUtilityPrice;
    final reminderMessageCost = smsCost > whatsappCost ? smsCost : whatsappCost;

    bool canProceed = await BalanceCheckUtil.checkBalanceAndProceed(
        context, userId, reminderMessageCost);

    if (!canProceed) {
      SnackbarComponents.showInsufficientBalance(context);
      sendingReminderNotifier.value = false;
      return; // Exit early, do NOT send the message
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
          userId, customerId, customerName, netBalance, mobileNumber);
    }).catchError((error) {
      showSnackbar(context, 'Error sending reminder. Please retry when online.',
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

      // PAS-UX-16: CustomerDeleted. Fire-and-forget so telemetry
      // can't delay the navigator.pop below.
      // ignore: unawaited_futures
      TelemetryService.instance.capture(const CustomerDeleted());

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
              title: Text("Confirm Deletion",
                  style: TextStyle(fontSize: SizeConfig.textMultiplier * 2.5)),
              content: Text(
                  "Are you sure you want to delete this customer? This action cannot be undone.",
                  style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
              actions: <Widget>[
                TextButton(
                  child: Text("Cancel",
                      style:
                          TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red, // Red color for delete
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text("Delete",
                      style:
                          TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
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
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _messagesUnreadSub?.cancel();
    _ordersUnreadSub?.cancel();
    sendingReminderNotifier.dispose();
    nameController.dispose();
    numberController.dispose();
    super.dispose();
  }
}
