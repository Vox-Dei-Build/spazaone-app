import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'consent_service.dart';

/// Thin wrapper around Firebase Crashlytics.
///
/// Why a wrapper:
///   * Single place to enforce PII scrubbing on custom keys / log breadcrumbs.
///   * Consent-gated: collection toggles on/off via [applyConsent] in response
///     to the consent modal and Settings -> Privacy switches.
///   * Never crashes the app. Every method is `try/catch`-wrapped because
///     telemetry must never be the reason a user-visible flow fails.
///
/// Crashlytics is initialised on by default (see `firebase_crashlytics_collection_enabled`
/// in AndroidManifest.xml / Info.plist) but the manifest values are set to
/// `false`; we call [applyConsent] from `main()` to flip collection on once
/// we have read the persisted consent state.
class CrashService {
  CrashService._();
  static final CrashService instance = CrashService._();

  bool _initialised = false;

  /// Wires `FlutterError.onError` and `PlatformDispatcher.instance.onError`
  /// so all uncaught Flutter + async errors flow into Crashlytics.
  ///
  /// Call once from `main()` after `Firebase.initializeApp()`. Calling more
  /// than once is a no-op.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    FlutterError.onError = (FlutterErrorDetails details) {
      // Log to console in debug; ship to Crashlytics in release.
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };

    // Catch async errors that escape the Flutter framework.
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Reflects the current [ConsentState.crash] value in Crashlytics' native
  /// collection flag. Safe to call repeatedly.
  Future<void> applyConsent(ConsentState consent) async {
    try {
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(consent.crash);
    } catch (_) {
      // Swallow: a Crashlytics config call must never break the app.
    }
  }

  /// Records a non-fatal error. Use inside `catch` blocks where you want a
  /// breadcrumb but the app continues running.
  Future<void> recordNonFatal(
    Object error,
    StackTrace? stack, {
    String? reason,
    Map<String, Object> context = const {},
  }) async {
    try {
      // Promote scrubbed context to custom keys for searchability in the
      // Crashlytics console.
      final scrubbed = _scrub(context);
      for (final entry in scrubbed.entries) {
        await FirebaseCrashlytics.instance
            .setCustomKey(entry.key, entry.value.toString());
      }
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: reason,
        fatal: false,
      );
    } catch (_) {
      // Never let telemetry crash the host app.
    }
  }

  /// Adds a string breadcrumb to the next crash report. Cheap and PII-safe
  /// because we scrub before forwarding.
  Future<void> log(String message, {Map<String, Object> context = const {}}) async {
    try {
      final scrubbed = _scrub(context);
      final suffix = scrubbed.isEmpty
          ? ''
          : ' ${scrubbed.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
      await FirebaseCrashlytics.instance.log('$message$suffix');
    } catch (_) {
      // ignored
    }
  }

  /// Sets the Crashlytics user identifier to the merchant id ONLY.
  /// Never pass email, phone, or display name -- those would leak into the
  /// Crashlytics console and any export.
  Future<void> setMerchantId(String? merchantId) async {
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier(merchantId ?? '');
    } catch (_) {
      // ignored
    }
  }

  /// Removes any obvious PII keys before they reach Crashlytics.
  ///
  /// This is a defence-in-depth check. The first line of defence is callers
  /// not passing PII in the first place; this catches mistakes.
  Map<String, Object> _scrub(Map<String, Object> context) {
    const blocked = {
      'email',
      'phone',
      'phone_number',
      'msisdn',
      'first_name',
      'last_name',
      'full_name',
      'name',
      'id_number',
      'account_number',
      'card_number',
      'cvv',
      'pin',
      'password',
      'otp',
      'address',
    };
    return {
      for (final entry in context.entries)
        if (!blocked.contains(entry.key.toLowerCase())) entry.key: entry.value,
    };
  }
}
