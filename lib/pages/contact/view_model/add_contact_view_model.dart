import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/photo_upload_util.dart';
import 'package:pasella/utils/show_toast.dart';

class AddContactViewModel extends ChangeNotifier {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController numberController = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _isLoading = false;
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  File? _profileImage;
  String? _profileImageUrl;
  final PhotoUploadUtil _photoUploadUtil = PhotoUploadUtil();

  bool get isLoading => _isLoading;
  File? get profileImage => _profileImage;
  String? get profileImageUrl => _profileImageUrl;

  Future<void> addCustomerToFirestore(
      BuildContext context, AppModel model) async {
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
      'profileImageUrl': _profileImageUrl,
    };

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('customers')
          .add(newCustomer)
          .then((docRef) async {
        await _sendSMS(currentUserId, docRef.id, customerName, mobileNumber);
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

  Future<void> pickImage(BuildContext context) async {
    await _photoUploadUtil.handleImagePick(context, (pickedImage) {
      if (pickedImage != null) {
        _profileImage = pickedImage;
        notifyListeners();
      }
    });
  }

  Future<void> uploadProfileImage() async {
    if (_profileImage != null) {
      _profileImageUrl = await _photoUploadUtil.uploadImage(_profileImage!,
          'profile_images/$currentUserId/${nameController.text}.jpg');
      notifyListeners();
    }
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
