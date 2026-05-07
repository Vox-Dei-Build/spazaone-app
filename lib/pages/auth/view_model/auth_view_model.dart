import 'dart:async';
import 'dart:io' show SocketException;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/widgets/private_region.dart';

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
    // Guard against re-entry (e.g. double-tap of the Login button) which would
    // otherwise trigger two verifyPhoneNumber calls and two SMS messages.
    if (isLoading.value) return;
    startLoading();

    try {
      // Network-first: the registered-user lookup needs an authoritative
      // answer from Firestore. If the device is offline, Firestore silently
      // returns empty results from cache, which would tell the user they
      // aren't registered and push them into the registration flow — risking
      // duplicate accounts.
      if (!await _hasNetwork()) {
        showErrorSnackBar(
          context,
          "You're offline. Please connect to the internet and try again.",
          isWarning: true,
        );
        stopLoading();
        return;
      }

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
      showErrorSnackBar(context, _friendlyAuthError(e), isWarning: true);
    } finally {
      stopLoading();
    }
  }

  Future<void> registerUser(BuildContext context,
      {String? referrerUserId}) async {
    // Guard against re-entry; prevents duplicate SMS sends from double-taps.
    if (isLoading.value) return;
    startLoading();
    try {
      // Network-first: see comment in handleLogin().
      if (!await _hasNetwork()) {
        showErrorSnackBar(
          context,
          "You're offline. Please connect to the internet and try again.",
          isWarning: true,
        );
        stopLoading();
        return;
      }

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
              // Phone-OTP signup completed (manual code entry path).
              // We identify the merchant immediately so subsequent events
              // attach to a person profile rather than the anonymous id.
              await TelemetryService.instance.identify(merchantId: user.uid);
              await TelemetryService.instance
                  .capture(const SignupCompleted(method: 'phone'));
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
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'phone registration failed',
      );
      showErrorSnackBar(context, _friendlyAuthError(e), isWarning: true);
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
        // Caller (registration) takes over -- they fire the signup event.
        onSuccess();
      } else {
        // No onSuccess callback means this is a login flow (manual OTP entry).
        // Identify the merchant and fire the signin event.
        final user = auth.currentUser;
        if (user != null) {
          await TelemetryService.instance.identify(merchantId: user.uid);
          await TelemetryService.instance
              .capture(const SigninCompleted(method: 'phone'));
        }
      }
      handleSuccessfulLogin(context);
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'signInWithCredential failed',
      );
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

      final user = userCredential.user;
      if (user != null) {
        // Anonymous "Explore" signup. We still call identify() so the merchant
        // has a person profile keyed by their anonymous Firebase UID; if they
        // later upgrade to a phone account that UID survives via linking.
        await TelemetryService.instance.identify(merchantId: user.uid);
        await TelemetryService.instance
            .capture(const SignupCompleted(method: 'anonymous'));
      }

      stopLoading();

      // Navigate to the main part of your app
      handleSuccessfulLogin(context);
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'anonymous sign-in failed',
      );
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
                  PrivateRegion(
                    child: TextField(
                      onChanged: (value) => smsCode = value,
                      decoration: const InputDecoration(hintText: "SMS Code"),
                      keyboardType: TextInputType.number,
                      autofocus: true, // Automatically focus on the TextField
                    ),
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

  /// Returns true if the device currently has a usable network connection.
  /// Uses the same `connectivity_plus` API used elsewhere in the app.
  ///
  /// NOTE: This only reflects whether a radio (Wi-Fi / cellular) is enabled,
  /// not whether the internet is actually reachable. Captive portals, DNS
  /// failure, weak signal and similar will all report "online" here. Treat
  /// this as a cheap pre-check; the real reachability test is the Firestore
  /// query itself, whose `[cloud_firestore/unavailable]` error is caught and
  /// translated by [_friendlyAuthError].
  Future<bool> _hasNetwork() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (_) {
      // If the connectivity check itself fails, assume we have a connection
      // and let the downstream Firestore call fail loudly.
      return true;
    }
  }

  /// Translates an exception thrown during the auth flow into a user-facing
  /// message. The single most common failure mode is the device being
  /// effectively offline (no DNS, captive portal, server unreachable), which
  /// surfaces as `[cloud_firestore/unavailable]` — show a clear "you're
  /// offline" message rather than the raw Firestore error.
  String _friendlyAuthError(Object e) {
    if (e is FirebaseException && e.code == 'unavailable') {
      return "You're offline or our servers are unreachable. "
          "Please check your connection and try again.";
    }
    if (e is SocketException || e.toString().contains('SocketException')) {
      return "You're offline. Please check your connection and try again.";
    }
    return 'Something went wrong, please try again: $e';
  }

  Future<bool> _isUserRegistered(String normalizedMobileNumber) async {
    try {
      if (normalizedMobileNumber.isEmpty) return false;

      final String e164 = formatPhoneNumber(normalizedMobileNumber);
      final users = FirebaseFirestore.instance.collection('users');
      // Force a server fetch. Without this, Firestore will happily return
      // empty results from cache when offline, which would tell the user
      // they aren't registered when in fact the lookup never reached the
      // server. The connectivity guard in the caller catches the common
      // case; Source.server is belt-and-braces for stale-cache scenarios.
      const opts = GetOptions(source: Source.server);

      // 1) Preferred: query the new normalized field. Matches accounts
      //    written/updated since the normalization fix.
      final byNormalized = await users
          .where('mobileNumberNormalized', isEqualTo: normalizedMobileNumber)
          .limit(1)
          .get(opts);
      if (byNormalized.docs.isNotEmpty) return true;

      // 2) Legacy fallback: query the raw `mobileNumber` field. Existing
      //    accounts may have been stored as either the local form
      //    ("0648370009") or the E.164 form ("+27648370009") depending on
      //    what the user typed at registration time.
      //
      //    NOTE: two sequential single-field queries are used (instead of
      //    Filter.or) so this works without a composite index and on
      //    older cloud_firestore SDK versions.
      final byLegacyLocal = await users
          .where('mobileNumber', isEqualTo: normalizedMobileNumber)
          .limit(1)
          .get(opts);
      if (byLegacyLocal.docs.isNotEmpty) return true;

      if (e164.isNotEmpty && e164 != normalizedMobileNumber) {
        final byLegacyE164 = await users
            .where('mobileNumber', isEqualTo: e164)
            .limit(1)
            .get(opts);
        if (byLegacyE164.docs.isNotEmpty) return true;
      }

      return false;
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'isUserRegistered lookup failed',
      );
      // Re-throw so callers can distinguish "lookup failed" (e.g. offline /
      // permission denied) from "lookup succeeded and returned no match".
      // Previously this swallowed the exception and returned false, which
      // told users they weren't registered when the query had actually
      // failed.
      rethrow;
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
                // Auto-verified phone registration -- identify and fire signup.
                await TelemetryService.instance
                    .identify(merchantId: user.uid);
                await TelemetryService.instance
                    .capture(const SignupCompleted(method: 'phone'));
                handleSuccessfulLogin(context);
                break;
              case VerificationPurpose.login:
                // Auto-verified login. identify() in case this is the first
                // session for this merchant on this device.
                await TelemetryService.instance
                    .identify(merchantId: user.uid);
                await TelemetryService.instance
                    .capture(const SigninCompleted(method: 'phone'));
                handleSuccessfulLogin(context);
                break;
              case VerificationPurpose.linkAnonymous:
                // Link account and then navigate. The signup event is fired
                // inside linkPhoneNumberWithAnonymousAccount once the link
                // resolves successfully (single source of truth for that path).
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
        // Anonymous account upgraded to a phone account. The Firebase UID is
        // unchanged across the link so we re-identify (idempotent) and fire
        // SignupCompleted with method: 'phone' to mark the upgrade in funnels.
        await TelemetryService.instance.identify(merchantId: user.uid);
        await TelemetryService.instance
            .capture(const SignupCompleted(method: 'phone'));
        handleSuccessfulLogin(
            context); // Navigate or perform other actions post successful link
      }
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'link anonymous to phone failed',
      );
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
    } catch (error, st) {
      await CrashService.instance.recordNonFatal(
        error,
        st,
        reason: 'store user details after linking failed',
      );
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
    } catch (error, st) {
      await CrashService.instance.recordNonFatal(
        error,
        st,
        reason: 'store user details failed',
      );
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
