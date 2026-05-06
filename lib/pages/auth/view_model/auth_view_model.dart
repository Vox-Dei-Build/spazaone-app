import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/show_toast.dart';

enum VerificationPurpose { login, registration, linkAnonymous }

class AuthViewModel with ChangeNotifier {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final mobileNoController = TextEditingController();
  final nameController = TextEditingController();
  final shopNameController = TextEditingController();
  final registrationMobileNoController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final registrationFormKey = GlobalKey<FormState>();
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  void startLoading() {
    isLoading.value = true;
    notifyListeners();
  }

  void stopLoading() {
    isLoading.value = false;
    notifyListeners();
  }

  Future<void> handleLogin(BuildContext context) async {
    startLoading();

    try {
      String formattedPhoneNumber = formatPhoneNumber(mobileNoController.text);
      String normalizedPhoneNumber = normalizePhoneNumber(formattedPhoneNumber);
      bool isRegistered = await _isUserRegistered(normalizedPhoneNumber);

      if (!isRegistered) {
        showErrorSnackBar(
            context, "This number is not registered. Please register first.",
            isWarning: true);
        stopLoading();
        return;
      }

      final verificationId = await initiatePhoneNumberVerification(
          formattedPhoneNumber, context, VerificationPurpose.login);
      if (verificationId != null) {
        await _promptForVerificationCode(context, verificationId, (smsCode) {
          signInWithVerificationCode(smsCode, verificationId, context);
        });
      } else {
        stopLoading();
      }
    } catch (e) {
      showErrorSnackBar(context, 'Something went wrong, please try again: $e');
    } finally {
      stopLoading();
    }
  }

  Future<void> registerUser(BuildContext context,
      {String? referrerUserId}) async {
    startLoading();
    try {
      String formattedPhoneNumber =
          formatPhoneNumber(registrationMobileNoController.text);
      String normalizedPhoneNumber = normalizePhoneNumber(formattedPhoneNumber);
      bool isAlreadyRegistered = await _isUserRegistered(normalizedPhoneNumber);

      if (isAlreadyRegistered) {
        showErrorSnackBar(
            context, "This number is already registered. Please log in.",
            isWarning: true);
        return;
      }

      final verificationId = await initiatePhoneNumberVerification(
          formattedPhoneNumber, context, VerificationPurpose.registration,
          referrerUserId: referrerUserId);
      if (verificationId != null) {
        await _promptForVerificationCode(context, verificationId,
            (smsCode) async {
          await signInWithVerificationCode(smsCode, verificationId, context,
              onSuccess: () async {
            User? user = auth.currentUser;
            if (user != null) {
              await _storeUserDetails(context, user,
                  referrerUserId: referrerUserId);
              handleSuccessfulLogin(context);
            } else {
              showErrorSnackBar(context,
                  "User not found after verification. Please try again.");
            }
          });
        });
      } else {
        showErrorSnackBar(context,
            "No verification ID received, potentially auto-signed in.");
      }
    } catch (e) {
      print("An error occurred during registration: $e");
      showErrorSnackBar(
          context, 'Something went wrong during registration: $e');
    } finally {
      stopLoading();
    }
  }

  Future<void> registerAnonymousAccount(BuildContext context,
      {String? referrerUserId}) async {
    startLoading();
    try {
      String formattedPhoneNumber =
          formatPhoneNumber(registrationMobileNoController.text);
      String normalizedPhoneNumber = normalizePhoneNumber(formattedPhoneNumber);
      bool isAlreadyRegistered = await _isUserRegistered(normalizedPhoneNumber);
      if (isAlreadyRegistered) {
        stopLoading();
        showErrorSnackBar(
            context, "This number is already registered. Please log in.");
        return;
      }

      final verificationId = await initiatePhoneNumberVerification(
          formattedPhoneNumber, context, VerificationPurpose.linkAnonymous,
          referrerUserId: referrerUserId);

      if (verificationId == null) {
        // Auto verification completed or failed
        stopLoading();
        return;
      }

      // Manual code input required
      await _promptForVerificationCode(context, verificationId,
          (smsCode) async {
        try {
          AuthCredential credential = PhoneAuthProvider.credential(
              verificationId: verificationId, smsCode: smsCode);
          await linkPhoneNumberWithAnonymousAccount(
              credential, context, referrerUserId);
        } catch (e) {
          showErrorSnackBar(context, "Failed to link anonymous account: $e");
        } finally {
          stopLoading();
        }
      });
    } catch (e) {
      showErrorSnackBar(context, "Failed to link anonymous account: $e");
    } finally {
      stopLoading();
    }
  }

  Future<void> signInWithVerificationCode(
      String smsCode, String verificationId, BuildContext context,
      {Function? onSuccess}) async {
    try {
      final AuthCredential credential = PhoneAuthProvider.credential(
          verificationId: verificationId, smsCode: smsCode);
      await signInWithCredential(credential, context, onSuccess: onSuccess);
    } catch (e) {
      showErrorSnackBar(context, "Failed to sign in: $e");
      stopLoading();
    }
  }

  Future<void> signInWithCredential(
      AuthCredential credential, BuildContext context,
      {Function? onSuccess}) async {
    startLoading();
    try {
      await auth.signInWithCredential(credential);
      if (onSuccess != null) {
        onSuccess();
      }
      handleSuccessfulLogin(context);
    } catch (e) {
      showErrorSnackBar(context, "Failed to authenticate: $e");
    } finally {
      stopLoading();
    }
  }

  Future<void> signInAnonymously(BuildContext context) async {
    startLoading();
    try {
      final UserCredential userCredential =
          await FirebaseAuth.instance.signInAnonymously();

      print("Signed in anonymously as ${userCredential.user?.uid}");

      stopLoading();

      // Navigate to the main part of your app
      handleSuccessfulLogin(context);
    } catch (e) {
      print("Anonymous sign-in failed: $e");
      showErrorSnackBar(context, "Failed to sign in anonymously.");
    } finally {
      stopLoading();
    }
  }

  Future<void> _promptForVerificationCode(
    BuildContext context,
    String verificationId,
    Function(String smsCode) onVerifyPressed,
  ) async {
    Completer<void> completer = Completer<void>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        String smsCode = "";

        return AlertDialog(
          title: Text('Enter SMS Code',
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 2.5)),
          content: SingleChildScrollView(
            child: Container(
              padding:
                  LayoutConstants.padding10Horizontal, // Add padding if needed
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    onChanged: (value) => smsCode = value,
                    decoration: const InputDecoration(hintText: "SMS Code"),
                    keyboardType: TextInputType.number,
                    autofocus: true, // Automatically focus on the TextField
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              child: Text('Cancel',
                  style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                completer.complete();
              },
            ),
            TextButton(
              child: Text('Verify',
                  style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
              onPressed: () {
                onVerifyPressed(smsCode);
                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop(); // Dismiss the dialog
                }
                completer.complete();
              },
            ),
          ],
        );
      },
    );

    return completer.future;
  }

  Future<bool> _isUserRegistered(String normalizedMobileNumber) async {
    try {
      // Query by the normalized field. We also fall back to a query on
      // the legacy raw `mobileNumber` field so accounts created before
      // `mobileNumberNormalized` was written (which may have raw values
      // like "082 123 4567" or "+27821234567") are still found via the
      // matching E.164 form.
      final String e164 = formatPhoneNumber(normalizedMobileNumber);
      final QuerySnapshot bothSnapshots = await FirebaseFirestore.instance
          .collection('users')
          .where(Filter.or(
            Filter('mobileNumberNormalized',
                isEqualTo: normalizedMobileNumber),
            Filter('mobileNumber', isEqualTo: e164),
            Filter('mobileNumber', isEqualTo: normalizedMobileNumber),
          ))
          .get();

      return bothSnapshots.docs.isNotEmpty;
    } catch (e) {
      print('Something went wrong while checking registered user: $e');
      return false; // Return false here within the catch block
    }
  }

  Future<String?> initiatePhoneNumberVerification(
      String phoneNumber, BuildContext context, VerificationPurpose purpose,
      {String? referrerUserId}) async {
    Completer<String?> completer = Completer();
    auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await auth.signInWithCredential(credential);
          User? user = auth.currentUser;
          if (user != null) {
            switch (purpose) {
              case VerificationPurpose.registration:
                // Store user details before navigation
                await _storeUserDetails(context, user,
                    referrerUserId: referrerUserId);
                handleSuccessfulLogin(context);
                break;
              case VerificationPurpose.login:
                // Directly navigate to the dashboard
                handleSuccessfulLogin(context);
                break;
              case VerificationPurpose.linkAnonymous:
                // Link account and then navigate
                await linkPhoneNumberWithAnonymousAccount(
                    credential, context, referrerUserId);
                break;
            }
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        } catch (e) {
          if (!completer.isCompleted) completer.completeError(e);
          showErrorSnackBar(context, "Auto sign-in failed: $e");
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
        showErrorSnackBar(context, "Verification failed: ${e.message}");
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!completer.isCompleted) {
          completer.complete(verificationId);
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
    return completer.future;
  }

  Future<void> linkPhoneNumberWithAnonymousAccount(AuthCredential credential,
      BuildContext context, String? referrerUserId) async {
    try {
      await auth.currentUser!.linkWithCredential(credential);
      User? user = auth.currentUser;
      if (user != null) {
        // Assuming you want to store additional user details on successful link
        await _storeUserDetailsAfterLinking(context, user,
            referrerUserId: referrerUserId);
        handleSuccessfulLogin(
            context); // Navigate or perform other actions post successful link
      }
    } catch (e) {
      showErrorSnackBar(context, "Failed to link anonymous account: $e");
      rethrow; // Rethrow if you need further error handling upstream
    } finally {
      stopLoading();
    }
  }

  Future<void> _storeUserDetailsAfterLinking(BuildContext context, User? user,
      {String? referrerUserId}) async {
    if (user == null) return;

    try {
      final String rawNumber = registrationMobileNoController.text;
      final String normalized = normalizePhoneNumber(rawNumber);
      // Set root user details
      await _firestore.collection('users').doc(user.uid).set({
        'name': nameController.text,
        'shopName': shopNameController.text,
        'mobileNumber': rawNumber,
        'mobileNumberNormalized': normalized,
        'referralCount': 0,
        'referrerUserId': referrerUserId ?? "",
      }, SetOptions(merge: true));

      // DRY ✅ create wallet doc
      await _createInitialWallet(user.uid);

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      print("Error storing user details after linking: $error");
      showErrorSnackBar(context, "Error storing user details: $error");
    }
  }

  Future<void> _storeUserDetails(BuildContext context, User user,
      {String? referrerUserId}) async {
    try {
      final String rawNumber = registrationMobileNoController.text;
      final String normalized = normalizePhoneNumber(rawNumber);
      final Map<String, dynamic> userData = {
        'name': nameController.text,
        'shopName': shopNameController.text,
        'mobileNumber': rawNumber,
        'mobileNumberNormalized': normalized,
        'referralCount': 0,
      };

      if (referrerUserId != null) {
        userData['referrerUserId'] = referrerUserId;
      }

      // Merge to avoid clobbering fields that may already exist (e.g.
      // when this is called after `_storeUserDetailsAfterLinking`).
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(userData, SetOptions(merge: true));

      // DRY ✅ create wallet doc
      await _createInitialWallet(user.uid);
    } catch (error) {
      print("Error storing user details: $error");
      showErrorSnackBar(context, "Error storing user details: $error");
    }
  }

  /// 🧠 DRY: Shared helper to create initial wallet doc
  Future<void> _createInitialWallet(String userId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('wallet')
        .doc('current')
        .set({
      'virtualBalance': 15.0,
      'cashAdvanceBalance': 0.0,
      'salesVirtualBalance': 0.0,
      'cashAdvanceWithdrawn': 0.0,
      'cashAdvanceDueDate': null,
      'penaltyFee': 0.0,
      'accountSuspended': false,
      'totalCashAdvanceGiven': 0.0,
      'totalCashAdvanceRepaid': 0.0,
      'repaymentHistory': [
        {
          'date': DateTime.now().toIso8601String(),
          'amount': 0.0,
          'method': "N/A",
          'status': "N/A",
          'reference': "N/A"
        }
      ]
    });
  }

  Future<void> clearDeepLinkData() async {
    var box = Hive.box('deepLinkBox');
    await box.delete('referrerUserId');
  }

  void handleSuccessfulLogin(BuildContext context) {
    Navigator.of(context).pushReplacementNamed('/dashboard');
  }

  @override
  void dispose() {
    mobileNoController.dispose();
    nameController.dispose();
    shopNameController.dispose();
    registrationMobileNoController.dispose();
    super.dispose();
  }
}
