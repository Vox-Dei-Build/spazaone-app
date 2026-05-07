import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:io';

import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/shared/billing/cost_breakdown.dart';
import 'package:pasella/shared/billing/cost_confirmation_sheet.dart';
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
      BuildContext context, AppModel model) async {
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
          context, 'Validation failed or no user is logged in!', Colors.red);
      _setLoading(false);
      return;
    }

    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        showSnackbar(
            context,
            'You\'re offline. Action queued and will complete when back online.',
            Colors.orange);
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

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .add(newCustomer)
          .then((docRef) async {
        if (_profileImage != null) {
          final url = await _photoUploadUtil.uploadImage(
              _profileImage!, 'profile_images/$currentUserId/${docRef.id}.jpg');
          await docRef.update({'profileImageUrl': url});
        }
        if (mobileNumber.isNotEmpty && pricingService != null) {
          final onboardingMessageCost = SMSPricingUtil.calculateCost(
            text: SMSMessages.onboardingShort,
            unitCost: pricingService!.smsReminderTemplatePrice,
          );

          // Pre-flight cost confirmation. Cancel still saves the contact;
          // only the welcome SMS is skipped.
          final userConfirmed = await CostConfirmationSheet.show(
            context,
            breakdown: CostBreakdown.singleMessage(
              title: 'Send welcome SMS to $customerName?',
              subtitle: 'One-time onboarding message',
              channelLabel: 'Welcome SMS',
              cost: onboardingMessageCost,
            ),
            confirmLabel: 'Send SMS',
          );

          // Safety net for race conditions.
          final canProceed = userConfirmed &&
              await BalanceCheckUtil.checkBalanceAndProceed(
                  context, currentUserId, onboardingMessageCost);

          if (canProceed) {
            await _sendSMS(
                currentUserId, docRef.id, customerName, mobileNumber);
          }
        } else {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            showSnackbar(
              context,
              'Customer added without a number. You can update it later via "Edit Customer".',
              Colors.blue,
            );
          });
        }
      }).catchError((error) {
        showSnackbar(context,
            'Error adding customer. It will retry when online.', Colors.red);
      });

      nameController.clear();
      numberController.clear();

      SchedulerBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed('/dashboard');
      });
    } catch (error) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        showSnackbar(context,
            'Error adding customer. It will retry when online.', Colors.red);
      });
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _sendSMS(
      String userId, String customerId, String name, String number) async {
    try {
      MessagingNotificationService notificationService =
          await MessagingNotificationService.create();
      await notificationService.sendOnboardingMessage(
          userId, customerId, name, number);
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
      'date': Timestamp.now()
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
