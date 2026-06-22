import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:io';

import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/contact/contact_management.dart';
import 'package:pasella/shared/billing/cost_breakdown.dart';
import 'package:pasella/shared/billing/cost_confirmation_sheet.dart';
import 'package:pasella/shared/billing/cost_sheet_outcome.dart';
import 'package:pasella/shared/widgets/forms/confirm_dialog.dart';
import 'package:pasella/templates/sms_message.dart';
import 'package:pasella/utils/balance_check_util.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/utils/photo_upload_util.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

class AddContactViewModel extends ChangeNotifier {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController numberController = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _isLoading = false;
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  DynamicPricingService? pricingService;
  final PhotoUploadUtil _photoUploadUtil = PhotoUploadUtil();
  File? _profileImage;
  bool _contactConsentAccepted = false;

  File? get profileImage => _profileImage;

  bool get isLoading => _isLoading;

  AddContactViewModel() {
    _initializeServices();
    nameController.addListener(notifyListeners);
    numberController.addListener(notifyListeners);
  }

  /// True when the user has typed a name, a number, picked a profile
  /// image, or accepted the consent box. Drives the unsaved-changes
  /// guard on the Add Contact screen.
  bool get isDirty =>
      nameController.text.isNotEmpty ||
      numberController.text.isNotEmpty ||
      _profileImage != null ||
      _contactConsentAccepted;

  Future<void> _initializeServices() async {
    pricingService = await DynamicPricingService.initialize();
    notifyListeners();
  }

  bool get contactConsentAccepted => _contactConsentAccepted;

  void setContactConsent(bool value) {
    if (_contactConsentAccepted == value) return;
    _contactConsentAccepted = value;
    notifyListeners();
  }

  Future<void> addCustomerToFirestore(
    BuildContext context,
    AppModel model,
  ) async {
    if (!_contactConsentAccepted) {
      showSnackbar(
        context,
        'Please confirm you have permission to store this contact before continuing.',
        Colors.orange,
      );
      return;
    }

    _setLoading(true);

    final customerName = nameController.text;
    final mobileNumber = numberController.text;

    if (customerName.isEmpty || currentUserId.isEmpty) {
      showSnackbar(
        context,
        'Validation failed or no user is logged in!',
        Colors.red,
      );
      _setLoading(false);
      return;
    }

    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        showSnackbar(
          context,
          'You\'re offline. Action queued and will complete when back online.',
          Colors.orange,
        );
      });
    }

    var newCustomer = {
      'category': model.selectedCustomerCategory,
      'name': customerName,
      'number': normalizePhoneNumber(mobileNumber),
      'lastTransaction': getDefaultTransaction(),
      'balance': 0.0,
      'isNPA': false,
    };

    // Duplicate guard.
    //
    // The bug surfaced from production: re-picking an already-saved
    // contact silently created a second customer document with the
    // same phone number. The user saw the form go quiet and assumed
    // nothing happened (because the success snackbar / nav was racing
    // with the cost confirmation sheet — see addCustomerToFirestore
    // notes below) so they tapped Confirm again, magnifying the
    // duplicate. We now check first and refuse to write a second
    // record for the same number.
    //
    // Match key: normalized SA local form (`0XXXXXXXXX`), which is
    // exactly what we persist in `number`. Skipped entirely when the
    // user adds a no-number customer — those are typically walk-in
    // placeholders ("Walk-in 1", "Walk-in 2") and should not collide.
    final normalizedNumber = newCustomer['number'] as String;
    if (normalizedNumber.isNotEmpty) {
      final existing = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .where('number', isEqualTo: normalizedNumber)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        _setLoading(false);
        // PAS-UX-16: blocked-create sub-event. The audit asked for
        // duplicate-number signal because it's been a recurring
        // confusion point in support; merchants tap Confirm again
        // when nothing visible happens.
        // ignore: unawaited_futures
        TelemetryService.instance.capture(
          const CustomerCreateBlocked(reason: 'duplicate_number'),
        );
        final existingDoc = existing.docs.first;
        final existingData = existingDoc.data();
        final existingName = (existingData['name'] as String?) ?? customerName;

        if (!context.mounted) return;
        final openExisting = await ConfirmDialog.show(
          context,
          title: 'Already in your contacts',
          message:
              '$existingName is already saved with this number. Open the existing customer instead?',
          confirmLabel: 'Open existing',
          cancelLabel: 'Cancel',
        );

        if (openExisting && context.mounted) {
          // Replace the AddContact route with the existing customer's
          // page so back navigation lands the user on the ledger they
          // came from, not back on the abandoned add form.
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => CustomerManagementPage(
                customerName: existingName,
                customerId: existingDoc.id,
                mobileNumber: normalizedNumber,
              ),
            ),
          );
        }
        return;
      }
    }

    // Linear async flow.
    //
    // The previous implementation chained `.add(...).then((docRef) async { ... })`
    // and immediately ran `nameController.clear()` and the dashboard
    // navigation right after kicking off the chain, NOT awaiting it.
    // The `then` callback's `await CostConfirmationSheet.show(...)`
    // therefore raced with `pushReplacementNamed('/dashboard')`, which
    // produced the silent-success bug observed in production:
    //   * Firestore wrote the contact (offline cache returns instantly)
    //   * The cost confirmation sheet was orphaned by the navigation
    //   * No success snackbar was shown
    //   * The form fields cleared but the page sat there
    //   * Users assumed nothing happened and tapped Confirm again,
    //     creating duplicate customer documents
    //
    // The fix: await each phase in order, only navigate after all
    // post-write side effects (image upload, cost sheet, SMS) finish,
    // and surface a success snackbar so the user has explicit
    // confirmation before the route changes.
    try {
      // PAS-UX-09: detect whether this is the merchant's first customer
      // BEFORE the write. If it is, the post-save destination is the
      // new customer's management page (Pay Later / Orders / Messages
      // tabs — i.e. the hero loop with Credit + Payment + WhatsApp
      // buttons in reach) instead of bouncing back to Dashboard. This
      // is the single biggest shortcut from signup to "believable
      // value moment": one tap creates the customer, the next tap
      // records the first credit on them.
      //
      // For non-first customers we keep the historical Dashboard
      // destination to respect habituated flow.
      final customerCollection = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers');
      final priorCustomersSnap = await customerCollection.limit(10).get();
      final isFirstCustomer = priorCustomersSnap.docs.isEmpty;
      final customerCountAfterSave = priorCustomersSnap.docs.length >= 10
          ? 10
          : priorCustomersSnap.docs.length + 1;

      final docRef = await customerCollection.add(newCustomer);

      if (_profileImage != null) {
        final url = await _photoUploadUtil.uploadImage(
          _profileImage!,
          'profile_images/$currentUserId/${docRef.id}.jpg',
        );
        await docRef.update({'profileImageUrl': url});
      }

      if (mobileNumber.isNotEmpty && pricingService != null) {
        final smsCost = SMSPricingUtil.calculateCost(
          text: SMSMessages.onboardingShort,
          unitCost: pricingService!.smsReminderTemplatePrice,
        );
        final whatsappCost = pricingService!.whatsappUtilityPrice;

        // Resolve which channel the dispatcher will most likely use so
        // the cost sheet quotes the right primary price. Both prices are
        // always shown — quoting only one is a money-correctness bug
        // because the actual deduction depends on whether WhatsApp
        // delivery succeeds.
        final expectedChannel =
            await MessagingNotificationService.resolveExpectedChannel(
          mobileNumber,
        );

        // Pre-flight cost confirmation. Tri-state outcome — explicit
        // skip is now a labelled action ("Skip & record only"), so the
        // contact is always saved and the merchant never has to guess
        // whether the welcome message went out.
        final breakdown = CostBreakdown.singleMessageMultiChannel(
          title: 'Send welcome message to $customerName?',
          subtitle: 'One-time onboarding message',
          whatsappCost: whatsappCost,
          smsCost: smsCost,
          expected: expectedChannel,
        );
        final outcome = await CostConfirmationSheet.showOutcome(
          context,
          breakdown: breakdown,
          confirmLabel: 'Send',
        );

        // Safety net for race conditions on the wallet balance. Use the
        // breakdown's quoted total (the primary channel cost) as the
        // affordability gate — matches what the user just confirmed.
        final canProceed = outcome.shouldSend &&
            await BalanceCheckUtil.checkBalanceAndProceed(
              context,
              currentUserId,
              breakdown.total,
            );

        if (canProceed) {
          await _sendSMS(currentUserId, docRef.id, customerName, mobileNumber);
        } else if (outcome.isSilent) {
          // Contact persisted, no welcome message. Surface the state.
          showSnackbar(
            context,
            'Contact saved. No welcome message sent.',
            Colors.blueGrey,
          );
        }
      }

      // Success path: clear inputs, confirm to the user, then navigate.
      // Order matters — clear() before the snackbar so the screen looks
      // settled when the toast appears, and snackbar before nav so it
      // queues onto the destination route's ScaffoldMessenger.

      // PAS-UX-16: CustomerCreated must capture hasImage BEFORE we
      // null out _profileImage as part of the form reset below,
      // otherwise the event always reports has_image=false.
      // Fire-and-forget so telemetry can't block the navigator push.
      final createdWithImage = _profileImage != null;
      // ignore: unawaited_futures
      TelemetryService.instance.capture(
        CustomerCreated(
          hasImage: createdWithImage,
          customerCountBucket: customerCountBucket(customerCountAfterSave),
        ),
      );

      nameController.clear();
      numberController.clear();
      _profileImage = null;
      _contactConsentAccepted = false;

      SchedulerBinding.instance.addPostFrameCallback((_) {
        final messenger = mobileNumber.isEmpty
            ? 'Customer added. You can add a number later via "Edit Customer".'
            : 'Customer added.';
        showSnackbar(context, messenger, Colors.green);
        if (isFirstCustomer) {
          // PAS-UX-09: first-customer fast-path. Replace the AddContact
          // route with the new customer's management page so the
          // merchant lands on the balance view with Credit / Payment /
          // WhatsApp actions one tap away. Back navigation still
          // resolves to Dashboard via the route stack underneath.
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => CustomerManagementPage(
                customerName: customerName,
                customerId: docRef.id,
                mobileNumber: normalizePhoneNumber(mobileNumber),
              ),
            ),
          );
        } else {
          Navigator.of(context).pushReplacementNamed('/dashboard');
        }
      });
    } catch (error) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        showSnackbar(
          context,
          'Error adding customer. It will retry when online.',
          Colors.red,
        );
      });
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _sendSMS(
    String userId,
    String customerId,
    String name,
    String number,
  ) async {
    try {
      MessagingNotificationService notificationService =
          await MessagingNotificationService.create();
      await notificationService.sendOnboardingMessage(
        userId,
        customerId,
        name,
        number,
      );
    } catch (e) {
      print(e);
    }
  }

  Future<void> handleImagePick(BuildContext context) async {
    await _photoUploadUtil.handleImagePick(context, (pickedImage) {
      _profileImage = pickedImage;
      notifyListeners();
    });
  }

  Map<String, dynamic> getDefaultTransaction() {
    return {
      'amount': 0,
      'remarks': 'No transactions yet',
      'status': 'PAID',
      'type': 'Payment',
      'date': Timestamp.now(),
    };
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    nameController.dispose();
    numberController.dispose();
    super.dispose();
  }
}
