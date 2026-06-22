import 'dart:async';
import 'dart:io' show SocketException;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/main.dart' show navigatorKey;
import 'package:pasella/pages/auth/widgets/otp_code_dialog.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/show_toast.dart';

enum VerificationPurpose { login, registration, linkAnonymous }

/// Converts Firebase Phone Auth failures into bounded, merchant-safe copy.
///
/// Firebase exception messages can contain package names, signing details,
/// Play Integrity diagnostics, and other backend configuration information.
/// Those details belong in crash reporting, never in the user-facing snackbar.
String phoneVerificationErrorMessage(FirebaseAuthException error) {
  switch (error.code) {
    case 'invalid-phone-number':
      return 'Enter a valid South African mobile number and try again.';
    case 'network-request-failed':
      return "You're offline. Please check your connection and try again.";
    case 'too-many-requests':
      return 'Too many verification attempts. Please wait and try again.';
    case 'quota-exceeded':
      return 'Verification is temporarily unavailable. Please try again later.';
    default:
      return "We couldn't send the verification code. Please try again.";
  }
}

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
          context,
          "This number is not registered. Please register first.",
          isWarning: true,
        );
        stopLoading();
        return;
      }

      final verificationId = await initiatePhoneNumberVerification(
        formattedPhoneNumber,
        context,
        VerificationPurpose.login,
      );
      if (verificationId != null) {
        final verified = await _promptForVerificationCode(
          context,
          verificationId,
          (smsCode, activeVerificationId) {
            return signInWithVerificationCode(
              smsCode,
              activeVerificationId,
              context,
              navigateOnSuccess: false,
            );
          },
          phoneNumber: formattedPhoneNumber,
        );
        if (verified) {
          handleSuccessfulLogin(context);
        }
      } else {
        stopLoading();
      }
    } catch (e) {
      showErrorSnackBar(context, _friendlyAuthError(e), isWarning: true);
    } finally {
      stopLoading();
    }
  }

  Future<void> registerUser(
    BuildContext context, {
    String? referrerUserId,
  }) async {
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

      String formattedPhoneNumber = formatPhoneNumber(
        registrationMobileNoController.text,
      );
      String normalizedPhoneNumber = normalizePhoneNumber(formattedPhoneNumber);
      bool isAlreadyRegistered = await _isUserRegistered(normalizedPhoneNumber);

      if (isAlreadyRegistered) {
        showErrorSnackBar(
          context,
          "This number is already registered. Please log in.",
          isWarning: true,
        );
        return;
      }

      final verificationId = await initiatePhoneNumberVerification(
        formattedPhoneNumber,
        context,
        VerificationPurpose.registration,
        referrerUserId: referrerUserId,
      );
      if (verificationId != null) {
        final verified = await _promptForVerificationCode(
          context,
          verificationId,
          (smsCode, activeVerificationId) async {
            return signInWithVerificationCode(
              smsCode,
              activeVerificationId,
              context,
              navigateOnSuccess: false,
              onSuccess: () async {
                User? user = auth.currentUser;
                if (user != null) {
                  await _storeUserDetails(
                    context,
                    user,
                    referrerUserId: referrerUserId,
                  );
                  // Phone-OTP signup completed (manual code entry path).
                  // We identify the merchant immediately so subsequent events
                  // attach to a person profile rather than the anonymous id.
                  await TelemetryService.instance.identify(
                    merchantId: user.uid,
                  );
                  await TelemetryService.instance.capture(
                    const SignupCompleted(method: 'phone'),
                  );
                } else {
                  showErrorSnackBar(
                    context,
                    "User not found after verification. Please try again.",
                  );
                }
              },
            );
          },
          phoneNumber: formattedPhoneNumber,
        );
        if (verified) {
          handleSuccessfulLogin(context);
        }
      } else {
        showErrorSnackBar(
          context,
          "No verification ID received, potentially auto-signed in.",
        );
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

  Future<void> registerAnonymousAccount(
    BuildContext context, {
    String? referrerUserId,
  }) async {
    startLoading();
    try {
      String formattedPhoneNumber = formatPhoneNumber(
        registrationMobileNoController.text,
      );
      String normalizedPhoneNumber = normalizePhoneNumber(formattedPhoneNumber);
      bool isAlreadyRegistered = await _isUserRegistered(normalizedPhoneNumber);
      if (isAlreadyRegistered) {
        stopLoading();
        showErrorSnackBar(
          context,
          "This number is already registered. Please log in.",
        );
        return;
      }

      final verificationId = await initiatePhoneNumberVerification(
        formattedPhoneNumber,
        context,
        VerificationPurpose.linkAnonymous,
        referrerUserId: referrerUserId,
      );

      if (verificationId == null) {
        // Auto verification completed or failed
        stopLoading();
        return;
      }

      // Manual code input required
      await _promptForVerificationCode(context, verificationId, (
        smsCode,
        activeVerificationId,
      ) async {
        try {
          AuthCredential credential = PhoneAuthProvider.credential(
            verificationId: activeVerificationId,
            smsCode: smsCode,
          );
          await linkPhoneNumberWithAnonymousAccount(
            credential,
            context,
            referrerUserId,
          );
          return true;
        } catch (e) {
          showErrorSnackBar(context, "Failed to link anonymous account: $e");
          return false;
        } finally {
          stopLoading();
        }
      }, phoneNumber: formattedPhoneNumber);
    } catch (e) {
      showErrorSnackBar(context, "Failed to link anonymous account: $e");
    } finally {
      stopLoading();
    }
  }

  Future<bool> signInWithVerificationCode(
    String smsCode,
    String verificationId,
    BuildContext context, {
    FutureOr<void> Function()? onSuccess,
    bool navigateOnSuccess = true,
  }) async {
    try {
      final AuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      return signInWithCredential(
        credential,
        context,
        onSuccess: onSuccess,
        navigateOnSuccess: navigateOnSuccess,
      );
    } catch (e) {
      showErrorSnackBar(context, "Failed to sign in: $e");
      stopLoading();
      return false;
    }
  }

  Future<bool> signInWithCredential(
    AuthCredential credential,
    BuildContext context, {
    FutureOr<void> Function()? onSuccess,
    bool navigateOnSuccess = true,
  }) async {
    startLoading();
    try {
      await auth.signInWithCredential(credential);
      if (onSuccess != null) {
        // Caller (registration) takes over -- they fire the signup event.
        await onSuccess();
      } else {
        // No onSuccess callback means this is a login flow (manual OTP entry).
        // Identify the merchant and fire the signin event.
        final user = auth.currentUser;
        if (user != null) {
          await TelemetryService.instance.identify(merchantId: user.uid);
          await TelemetryService.instance.capture(
            const SigninCompleted(method: 'phone'),
          );
        }
      }
      if (navigateOnSuccess) {
        handleSuccessfulLogin(context);
      }
      return true;
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'signInWithCredential failed',
      );
      showErrorSnackBar(context, "Failed to authenticate: $e");
      return false;
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
        await TelemetryService.instance.capture(
          const SignupCompleted(method: 'anonymous'),
        );
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

  Future<bool> _promptForVerificationCode(
    BuildContext context,
    String verificationId,
    Future<bool> Function(String smsCode, String verificationId)
    onVerifyPressed, {
    String? phoneNumber,
    VerificationPurpose? purpose,
    DateTime? codeSentAt,
    Future<String?> Function()? onResend,
  }) async {
    String activeVerificationId = verificationId;
    DateTime activeCodeSentAt = codeSentAt ?? DateTime.now();
    final String? maskedNumber = _maskPhoneNumber(phoneNumber);
    final purposeName =
        purpose == null ? null : _analyticsPurposeForOtp(purpose);

    return showOtpCodeDialog(
      context,
      maskedNumber: maskedNumber,
      enableAutosubmit: FeatureFlags.enableOtpAutosubmit,
      enableResend: FeatureFlags.enableOtpResendInDialog && onResend != null,
      onCancel: () async {
        if (purposeName == null) return;
        await TelemetryService.instance.capture(
          OtpCancelled(
            purpose: purposeName,
            elapsedBucket: _elapsedBucketSince(activeCodeSentAt),
          ),
        );
      },
      onResend:
          onResend == null
              ? null
              : () async {
                if (purposeName != null) {
                  await TelemetryService.instance.capture(
                    OtpResendRequested(
                      purpose: purposeName,
                      elapsedBucket: _elapsedBucketSince(activeCodeSentAt),
                    ),
                  );
                }
                final nextVerificationId = await onResend();
                if (nextVerificationId != null) {
                  activeVerificationId = nextVerificationId;
                  activeCodeSentAt = DateTime.now();
                }
              },
      onVerify: (smsCode) async {
        return onVerifyPressed(smsCode, activeVerificationId);
      },
    );
  }

  /// PAS-AUTH-01: Mask a phone number for display in the OTP dialog.
  /// Keeps the country/leading code and the last 3 digits visible so the
  /// user can confirm they entered the right number, while hiding the
  /// middle digits to limit PII exposure if the screen is recorded or
  /// screen-shared. Returns null if [phoneNumber] is null/empty/too short
  /// so the caller can fall back to a generic message.
  String? _maskPhoneNumber(String? phoneNumber) {
    if (phoneNumber == null) return null;
    final trimmed = phoneNumber.trim();
    if (trimmed.length < 6) return null;
    // Keep the first 3 (e.g. "+27") and the last 3, mask the middle.
    final head = trimmed.substring(0, 3);
    final tail = trimmed.substring(trimmed.length - 3);
    return '$head•••$tail';
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
    String phoneNumber,
    BuildContext context,
    VerificationPurpose purpose, {
    String? referrerUserId,
  }) async {
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
                await _storeUserDetails(
                  context,
                  user,
                  referrerUserId: referrerUserId,
                );
                // Auto-verified phone registration -- identify and fire signup.
                await TelemetryService.instance.identify(merchantId: user.uid);
                await TelemetryService.instance.capture(
                  const SignupCompleted(method: 'phone'),
                );
                handleSuccessfulLogin(context);
                break;
              case VerificationPurpose.login:
                // Auto-verified login. identify() in case this is the first
                // session for this merchant on this device.
                await TelemetryService.instance.identify(merchantId: user.uid);
                await TelemetryService.instance.capture(
                  const SigninCompleted(method: 'phone'),
                );
                handleSuccessfulLogin(context);
                break;
              case VerificationPurpose.linkAnonymous:
                // Link account and then navigate. The signup event is fired
                // inside linkPhoneNumberWithAnonymousAccount once the link
                // resolves successfully (single source of truth for that path).
                await linkPhoneNumberWithAnonymousAccount(
                  credential,
                  context,
                  referrerUserId,
                );
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
        unawaited(
          CrashService.instance.recordNonFatal(
            e,
            StackTrace.current,
            reason: 'phone verification failed',
            context: {'code': e.code},
          ),
        );
        showErrorSnackBar(context, phoneVerificationErrorMessage(e));
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

  Future<void> linkPhoneNumberWithAnonymousAccount(
    AuthCredential credential,
    BuildContext context,
    String? referrerUserId,
  ) async {
    try {
      await auth.currentUser!.linkWithCredential(credential);
      User? user = auth.currentUser;
      if (user != null) {
        // Assuming you want to store additional user details on successful link
        await _storeUserDetailsAfterLinking(
          context,
          user,
          referrerUserId: referrerUserId,
        );
        // Anonymous account upgraded to a phone account. The Firebase UID is
        // unchanged across the link so we re-identify (idempotent) and fire
        // SignupCompleted with method: 'phone' to mark the upgrade in funnels.
        await TelemetryService.instance.identify(merchantId: user.uid);
        await TelemetryService.instance.capture(
          const SignupCompleted(method: 'phone'),
        );
        handleSuccessfulLogin(
          context,
        ); // Navigate or perform other actions post successful link
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

  Future<void> _storeUserDetailsAfterLinking(
    BuildContext context,
    User? user, {
    String? referrerUserId,
  }) async {
    if (user == null) return;

    try {
      final String rawNumber = registrationMobileNoController.text;
      final String normalized = normalizePhoneNumber(rawNumber);
      // PAS-UX-09 follow-up: shopName is optional at signup. Persist as a
      // trimmed string and skip the field entirely when blank, so empty
      // strings don't leak into outbound SMS / WhatsApp templates as
      // visible blanks. Merchants recover this via Settings → Business Name.
      final String trimmedShopName = shopNameController.text.trim();
      final Map<String, dynamic> rootData = {
        'name': nameController.text,
        'mobileNumber': rawNumber,
        'mobileNumberNormalized': normalized,
        'referralCount': 0,
        'referrerUserId': referrerUserId ?? "",
      };
      if (trimmedShopName.isNotEmpty) {
        rootData['shopName'] = trimmedShopName;
      }
      // Set root user details
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(rootData, SetOptions(merge: true));

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

  Future<void> _storeUserDetails(
    BuildContext context,
    User user, {
    String? referrerUserId,
  }) async {
    try {
      final String rawNumber = registrationMobileNoController.text;
      final String normalized = normalizePhoneNumber(rawNumber);
      // PAS-UX-09 follow-up: see _storeUserDetailsAfterLinking — only
      // persist shopName when the merchant actually entered one.
      final String trimmedShopName = shopNameController.text.trim();
      final Map<String, dynamic> userData = {
        'name': nameController.text,
        'mobileNumber': rawNumber,
        'mobileNumberNormalized': normalized,
        'referralCount': 0,
      };
      if (trimmedShopName.isNotEmpty) {
        userData['shopName'] = trimmedShopName;
      }

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
              'reference': "N/A",
            },
          ],
        });
  }

  Future<void> clearDeepLinkData() async {
    var box = Hive.box('deepLinkBox');
    await box.delete('referrerUserId');
  }

  void handleSuccessfulLogin(BuildContext context) {
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/dashboard');
      return;
    }
    final navState = navigatorKey.currentState;
    if (navState != null) {
      navState.pushReplacementNamed('/dashboard');
    }
  }

  // ---------------------------------------------------------------------------
  // PAS-UX-22: number-first onboarding entry points.
  //
  // These methods are used by `PhoneEntryPage` and `FinishProfilePage`. They
  // intentionally do NOT touch `mobileNoController`, `registrationMobileNo-
  // Controller`, `nameController` or `shopNameController` — the number-first
  // surface owns its own form state and passes plain strings in. This keeps
  // the legacy `handleLogin` / `registerUser` paths working bit-for-bit while
  // the feature flag rolls out, and avoids any controller-aliasing surprises
  // if both surfaces are ever exercised in the same session (e.g. via the
  // legacy compat redirect).
  // ---------------------------------------------------------------------------

  /// Number-first entry point. Validates connectivity, looks up the phone
  /// against `users`, then routes to OTP-as-login or OTP-as-registration.
  ///
  /// On registration-OTP success the user is pushed to `/finishProfilePage`
  /// (NOT `/dashboard`) so they can supply Business Name + Full Name. On
  /// login-OTP success the user goes straight to `/dashboard` exactly like
  /// the legacy login flow.
  ///
  /// Lookup failures (offline mid-read, Firestore unavailable, permission)
  /// surface a retry-style error and DO NOT advance into either branch —
  /// this is load-bearing for duplicate-account prevention (N1 in the spec).
  Future<void> lookupAndRoute(
    BuildContext context,
    String rawPhone, {
    String? referrerUserId,
  }) async {
    if (isLoading.value) return;
    startLoading();
    try {
      if (!await _hasNetwork()) {
        showErrorSnackBar(
          context,
          "You're offline. Please connect to the internet and try again.",
          isWarning: true,
        );
        await TelemetryService.instance.capture(
          const PhoneLookupFailed(reason: 'offline'),
        );
        return;
      }

      final String formatted = formatPhoneNumber(rawPhone);
      final String normalized = normalizePhoneNumber(formatted);
      if (formatted.isEmpty || normalized.isEmpty) {
        // Defensive: the form validator should have caught this. If we
        // somehow got here with a non-SA number, refuse rather than try
        // to look it up against Firestore with an empty string.
        showErrorSnackBar(context, kSAOnlyPhoneMessage, isWarning: true);
        return;
      }

      bool isRegistered;
      try {
        isRegistered = await _isUserRegistered(normalized);
      } catch (e, st) {
        await CrashService.instance.recordNonFatal(
          e,
          st,
          reason: 'number-first phone lookup failed',
        );
        await TelemetryService.instance.capture(
          PhoneLookupFailed(reason: _classifyLookupFailure(e)),
        );
        showErrorSnackBar(
          context,
          "Couldn't check your number. Tap Continue to try again.",
          isWarning: true,
        );
        return;
      }

      await TelemetryService.instance.capture(
        PhoneLookupSucceeded(isRegistered: isRegistered),
      );

      if (isRegistered) {
        await _initiateOtpAndRoute(
          context,
          formatted,
          VerificationPurpose.login,
          referrerUserId: referrerUserId,
        );
      } else {
        await _initiateOtpAndRoute(
          context,
          formatted,
          VerificationPurpose.registration,
          referrerUserId: referrerUserId,
        );
      }
    } finally {
      stopLoading();
    }
  }

  /// Triggers `verifyPhoneNumber` then prompts for the SMS code, using the
  /// existing OTP dialog. On success it dispatches to one of:
  ///
  ///   * login:        sign in, identify, fire SigninCompleted, go to dashboard.
  ///   * registration: sign in, write the auth-keyed minimum to users/{uid},
  ///                   identify, fire SignupCompleted, navigate to
  ///                   `/finishProfilePage` for name + shopName collection.
  ///
  /// Reuses [initiatePhoneNumberVerification] but bypasses its baked-in
  /// `_storeUserDetails(...)` call on auto-verification — the auto path
  /// relies on the registration form controllers being populated, which
  /// they are not on the number-first surface. To work around that without
  /// touching the legacy code path, we look at `auth.currentUser` after the
  /// fact and write the minimum doc ourselves if needed.
  Future<void> _initiateOtpAndRoute(
    BuildContext context,
    String formattedPhone,
    VerificationPurpose purpose, {
    String? referrerUserId,
  }) async {
    final purposeName = _analyticsPurposeForOtp(purpose);
    DateTime activeCodeSentAt = DateTime.now();
    bool routed = false;
    bool promptVisible = false;

    Future<String?> requestOtpCode() async {
      final requestStartedAt = DateTime.now();
      final completer = Completer<String?>();

      await auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          if (routed) return;
          routed = true;
          if (promptVisible && context.mounted) {
            unawaited(
              Navigator.of(context, rootNavigator: true).maybePop(true),
            );
          }
          try {
            await auth.signInWithCredential(credential);
            await TelemetryService.instance.capture(
              OtpAutoVerified(
                purpose: purposeName,
                elapsedBucket: _elapsedBucketSince(requestStartedAt),
              ),
            );
            await _onNumberFirstAuthSuccess(
              context,
              purpose,
              formattedPhone: formattedPhone,
              referrerUserId: referrerUserId,
            );
          } catch (e, st) {
            await CrashService.instance.recordNonFatal(
              e,
              st,
              reason: 'number-first auto sign-in failed',
            );
            await TelemetryService.instance.capture(
              OtpVerificationFailed(
                purpose: purposeName,
                failureCode: _otpFailureCode(e),
                elapsedBucket: _elapsedBucketSince(requestStartedAt),
              ),
            );
            showErrorSnackBar(context, "Auto sign-in failed: $e");
          } finally {
            if (!completer.isCompleted) completer.complete(null);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!completer.isCompleted) completer.complete(null);
          unawaited(
            CrashService.instance.recordNonFatal(
              e,
              StackTrace.current,
              reason: 'number-first phone verification failed',
              context: {'code': e.code},
            ),
          );
          unawaited(
            TelemetryService.instance.capture(
              OtpVerificationFailed(
                purpose: purposeName,
                failureCode: e.code,
                elapsedBucket: _elapsedBucketSince(requestStartedAt),
              ),
            ),
          );
          showErrorSnackBar(context, phoneVerificationErrorMessage(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          activeCodeSentAt = DateTime.now();
          unawaited(
            TelemetryService.instance.capture(
              OtpCodeSent(purpose: purposeName),
            ),
          );
          if (!completer.isCompleted) completer.complete(verificationId);
        },
        codeAutoRetrievalTimeout: (String _) {},
      );

      return completer.future;
    }

    final verificationId = await requestOtpCode();
    if (routed || verificationId == null) return;

    promptVisible = true;
    final verified = await _promptForVerificationCode(
      context,
      verificationId,
      (smsCode, activeVerificationId) async {
        try {
          final credential = PhoneAuthProvider.credential(
            verificationId: activeVerificationId,
            smsCode: smsCode,
          );
          await auth.signInWithCredential(credential);
          await TelemetryService.instance.capture(
            OtpManualVerified(
              purpose: purposeName,
              elapsedBucket: _elapsedBucketSince(activeCodeSentAt),
            ),
          );
          return true;
        } catch (e, st) {
          await CrashService.instance.recordNonFatal(
            e,
            st,
            reason: 'number-first manual sign-in failed',
          );
          await TelemetryService.instance.capture(
            OtpVerificationFailed(
              purpose: purposeName,
              failureCode: _otpFailureCode(e),
              elapsedBucket: _elapsedBucketSince(activeCodeSentAt),
            ),
          );
          showErrorSnackBar(context, "Failed to sign in: $e");
          return false;
        }
      },
      phoneNumber: formattedPhone,
      purpose: purpose,
      codeSentAt: activeCodeSentAt,
      onResend: requestOtpCode,
    );
    promptVisible = false;

    if (verified && !routed) {
      routed = true;
      await _onNumberFirstAuthSuccess(
        context,
        purpose,
        formattedPhone: formattedPhone,
        referrerUserId: referrerUserId,
      );
    }
  }

  /// Post-OTP success handler for the number-first flow.
  ///
  /// Login branch: identify + SigninCompleted + go to dashboard. Identical
  /// behaviour to the legacy login path, including identify-on-first-session.
  ///
  /// Registration branch: writes the auth-keyed minimum (mobileNumber,
  /// mobileNumberNormalized, referralCount, optional referrerUserId) and
  /// creates the initial wallet so any downstream code that assumes a wallet
  /// exists for an authenticated user keeps working. Then identifies, fires
  /// SignupCompleted(method:'phone'), and navigates to `/finishProfilePage`.
  /// Name and shopName are deferred to that screen.
  Future<void> _onNumberFirstAuthSuccess(
    BuildContext context,
    VerificationPurpose purpose, {
    required String formattedPhone,
    String? referrerUserId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      showErrorSnackBar(
        context,
        "User not found after verification. Please try again.",
      );
      return;
    }

    if (purpose == VerificationPurpose.registration) {
      await _writeAuthKeyedUserDoc(
        user,
        formattedPhone: formattedPhone,
        referrerUserId: referrerUserId,
      );
      await TelemetryService.instance.identify(merchantId: user.uid);
      await TelemetryService.instance.capture(
        const SignupCompleted(method: 'phone'),
      );
      _routeToFinishProfile(context);
    } else {
      await TelemetryService.instance.identify(merchantId: user.uid);
      await TelemetryService.instance.capture(
        const SigninCompleted(method: 'phone'),
      );
      handleSuccessfulLogin(context);
    }
  }

  /// Persists the bare-minimum `users/{uid}` doc that the number-first
  /// registration branch creates immediately after OTP success.
  ///
  /// Intentionally omits `name` and `shopName` — those are collected on
  /// `/finishProfilePage` and added with `merge: true`. The post-auth
  /// [BusinessNameGate] continues to guard the dashboard against any user
  /// that somehow reaches it without a `shopName` (e.g. abandons before
  /// submitting the finish-profile form), so the soft-gate stays as
  /// defense in depth.
  Future<void> _writeAuthKeyedUserDoc(
    User user, {
    required String formattedPhone,
    String? referrerUserId,
  }) async {
    try {
      // Store the formatted E.164 string under `mobileNumber` so it's
      // consistent with how the registration flow writes it once name/
      // shopName arrive. The lookup helpers query both
      // `mobileNumberNormalized` and the legacy `mobileNumber` field so
      // either form is recoverable.
      final String normalized = normalizePhoneNumber(formattedPhone);
      final Map<String, dynamic> data = {
        'mobileNumber': formattedPhone,
        'mobileNumberNormalized': normalized,
        'referralCount': 0,
      };
      if (referrerUserId != null && referrerUserId.isNotEmpty) {
        data['referrerUserId'] = referrerUserId;
      }
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));

      // Wallet creation is keyed to authenticated user existence, not
      // profile completeness. Downstream code (BNPL, wallet balance
      // streams) reads `users/{uid}/wallet/current` for any signed-in
      // user, so we seed it here at the same time the user doc is
      // created — exactly like the legacy `_storeUserDetails` does.
      await _createInitialWallet(user.uid);
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'number-first user doc write failed',
      );
      // Don't surface the raw error to the merchant here. They've already
      // signed in successfully; FinishProfilePage will retry the write on
      // submit and surface any persistent issue there.
    }
  }

  void _routeToFinishProfile(BuildContext context) {
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/finishProfilePage');
      return;
    }
    final navState = navigatorKey.currentState;
    if (navState != null) {
      navState.pushReplacementNamed('/finishProfilePage');
    }
  }

  /// Called by `FinishProfilePage` once the user has supplied Business
  /// Name and Full Name. Merges them into the existing `users/{uid}` doc
  /// (created by [_writeAuthKeyedUserDoc] above), then navigates to the
  /// dashboard. Throws on Firestore failure so the caller can surface a
  /// retry on the form.
  Future<void> completeProfileForNumberFirst(
    BuildContext context, {
    required String name,
    required String shopName,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError(
        'completeProfileForNumberFirst called with no auth user',
      );
    }
    final String trimmedName = name.trim();
    final String trimmedShop = shopName.trim();
    await _firestore.collection('users').doc(user.uid).set({
      'name': trimmedName,
      if (trimmedShop.isNotEmpty) 'shopName': trimmedShop,
    }, SetOptions(merge: true));
    handleSuccessfulLogin(context);
  }

  /// Coarse classifier for [_isUserRegistered] failures so we can attach a
  /// stable enum-ish reason to [PhoneLookupFailed] rather than the raw
  /// exception message (which can contain PII or change wording across
  /// SDK versions).
  String _classifyLookupFailure(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'unavailable') return 'unavailable';
      if (error.code == 'permission-denied') return 'permission';
    }
    if (error is SocketException) return 'offline';
    if (error.toString().contains('SocketException')) return 'offline';
    return 'unknown';
  }

  String _analyticsPurposeForOtp(VerificationPurpose purpose) {
    switch (purpose) {
      case VerificationPurpose.login:
        return 'login';
      case VerificationPurpose.registration:
        return 'registration';
      case VerificationPurpose.linkAnonymous:
        return 'link_anonymous';
    }
  }

  String _elapsedBucketSince(DateTime startedAt) {
    final seconds = DateTime.now().difference(startedAt).inSeconds;
    if (seconds < 10) return '0_10s';
    if (seconds < 30) return '10_30s';
    if (seconds < 60) return '30_60s';
    if (seconds < 120) return '60_120s';
    return '120s_plus';
  }

  String _otpFailureCode(Object error) {
    if (error is FirebaseAuthException) return error.code;
    if (error is FirebaseException) return error.code;
    if (error is SocketException) return 'offline';
    if (error.toString().contains('SocketException')) return 'offline';
    return 'unknown';
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
