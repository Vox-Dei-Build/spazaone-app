import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:pasella/config/spaza_environment.dart';

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

  final NavigatorObserver navigatorObserver = _CrashNavigatorObserver();

  bool _initialised = false;
  bool _developmentProbeRecorded = false;
  final Map<String, Object> _lastDiagnosticValues = {};

  static const String _buildCommit = String.fromEnvironment(
    'BUILD_COMMIT',
    defaultValue: 'unknown',
  );
  static const bool _developmentProbeEnabled = bool.fromEnvironment(
    'CRASHLYTICS_DIAGNOSTIC_PROBE',
  );

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
      // Framework explicitly marked this as silent (e.g. an error already
      // surfaced to the user via a snapshot). Don't double-report.
      if (details.silent) {
        return;
      }
      if (_isRenderOverflow(details)) {
        // Attach orientation and logical viewport dimensions before recording
        // the non-fatal. This turns future overflow reports into actionable
        // device/layout evidence without collecting merchant data.
        unawaited(_recordRenderOverflow(details));
        return;
      }
      // Classify recoverable network / backend errors (e.g. Cloud Functions
      // transient failures, App Check token churn, image fetch failures)
      // as NON-fatal. These flow into FlutterError.onError via FutureBuilder
      // when an async future rejects, but they are not real crashes and
      // inflate the fatal crash rate. UI surfaces them via snapshot.hasError
      // already.
      if (_isNonFatalFlutterError(details)) {
        FirebaseCrashlytics.instance.recordFlutterError(details);
        return;
      }
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };

    // Catch async errors that escape the Flutter framework.
    PlatformDispatcher.instance.onError = (error, stack) {
      final fatal = !_isRecoverableBackendError(error);
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal);
      return true;
    };
  }

  Future<void> configureBuild({
    required String version,
    required String buildNumber,
  }) async {
    await _setDiagnosticValues({
      'environment': SpazaRuntimeEnvironment.label.toLowerCase(),
      'app_version': version.trim().isEmpty ? 'unknown' : version.trim(),
      'app_build': buildNumber.trim().isEmpty ? 'unknown' : buildNumber.trim(),
      'build_commit': _buildCommit,
    });
  }

  Future<void> updateUiContext(BuildContext context) async {
    final media = MediaQuery.maybeOf(context);
    if (media == null) return;
    await _setDiagnosticValues({
      'layout_orientation':
          media.orientation == Orientation.landscape ? 'landscape' : 'portrait',
      'viewport_size_bucket': viewportSizeBucketForTesting(media.size),
      'text_scale_bucket': textScaleBucketForTesting(media.textScaler.scale(1)),
      'keyboard_visibility': media.viewInsets.bottom > 0 ? 'visible' : 'hidden',
    });
  }

  Future<void> setSurface(String? surface) async {
    await _setDiagnosticValues({
      'route_surface': sanitizeSurfaceForTesting(surface),
    });
  }

  Future<void> setStoreState({required bool present}) async {
    await _setDiagnosticValues({
      'store_state': present ? 'present' : 'empty',
    });
  }

  Future<void> _setDiagnosticValues(Map<String, Object> values) async {
    try {
      for (final entry in values.entries) {
        if (_lastDiagnosticValues[entry.key] == entry.value) continue;
        _lastDiagnosticValues[entry.key] = entry.value;
        await FirebaseCrashlytics.instance.setCustomKey(entry.key, entry.value);
      }
    } catch (_) {
      // Diagnostics must never affect the user flow.
    }
  }

  @visibleForTesting
  static String viewportSizeBucketForTesting(Size size) {
    final shortest = size.shortestSide;
    if (shortest < 360) return 'compact';
    if (shortest < 600) return 'phone';
    if (shortest < 900) return 'tablet';
    return 'large';
  }

  @visibleForTesting
  static String textScaleBucketForTesting(double scale) {
    if (scale <= 1.0) return 'default';
    if (scale <= 1.3) return 'medium';
    if (scale <= 2.0) return 'large';
    return 'extra_large';
  }

  @visibleForTesting
  static String sanitizeSurfaceForTesting(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 'unnamed';
    final path = Uri.tryParse(raw)?.path ?? '';
    if (path.isEmpty) return 'unnamed';
    final segments = path.split('/').where((part) => part.isNotEmpty).map(
      (part) {
        if (part.length > 32 || RegExp(r'\d|@|\+').hasMatch(part)) {
          return ':dynamic';
        }
        return part.replaceAll(RegExp(r'[^A-Za-z_-]'), '');
      },
    ).where((part) => part.isNotEmpty);
    final sanitized = '/${segments.join('/')}';
    return sanitized.length > 120 ? sanitized.substring(0, 120) : sanitized;
  }

  /// Errors that represent transient backend / network / token failures rather
  /// than programming bugs. Recording these as fatal misleads the crash-free
  /// users metric and drowns real crashes in noise.
  bool _isRecoverableBackendError(Object error) {
    if (error is FirebaseFunctionsException) {
      // Transient codes worth retrying; everything else (permission-denied,
      // unauthenticated, invalid-argument, etc.) is still classified as
      // non-fatal because a misbehaving Cloud Function is not an app crash.
      return true;
    }
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      final message = (error.message ?? '').toLowerCase();
      if (code.contains('firebase_remote_config') ||
          code.contains('firebase_functions') ||
          message.contains('unable to connect') ||
          message.contains('network') ||
          message.contains('timed out')) {
        return true;
      }
    }
    // Network-layer failures from dart:io. These bubble up from image
    // providers (NetworkImage / CachedNetworkImageProvider), http calls,
    // and any direct Firebase Storage download. Not an app crash.
    if (error is HttpException ||
        error is SocketException ||
        error is HandshakeException ||
        error is TlsException) {
      return true;
    }
    // Generic async timeouts (e.g. await with .timeout()).
    if (error is TimeoutException) {
      return true;
    }
    // The Functions plugin sometimes wraps transient errors in a generic
    // FlutterError whose message contains the Java `ExecutionException`
    // text. Match on that as a backstop.
    final msg = error.toString();
    if (msg.contains('underlying tasks failed') ||
        msg.contains('firebase_functions/')) {
      return true;
    }
    return false;
  }

  @visibleForTesting
  bool isRecoverableForTesting(Object error) {
    return _isRecoverableBackendError(error);
  }

  bool _isNonFatalFlutterError(FlutterErrorDetails details) {
    return _isRecoverableBackendError(details.exception) ||
        _isImageLibraryError(details) ||
        _isRenderOverflow(details);
  }

  @visibleForTesting
  bool isNonFatalFlutterErrorForTesting(FlutterErrorDetails details) {
    return _isNonFatalFlutterError(details);
  }

  /// A RenderFlex overflow is a visual defect, not a process-ending crash.
  /// Keep the event searchable in Crashlytics without corrupting the fatal
  /// crash-free metric.
  bool _isRenderOverflow(FlutterErrorDetails details) {
    return details.exceptionAsString().contains('A RenderFlex overflowed by');
  }

  Future<void> _recordRenderOverflow(FlutterErrorDetails details) async {
    try {
      final views = PlatformDispatcher.instance.views;
      if (views.isNotEmpty) {
        final view = views.first;
        final logicalSize = view.physicalSize / view.devicePixelRatio;
        await FirebaseCrashlytics.instance.setCustomKey(
          'layout_orientation',
          logicalSize.width > logicalSize.height ? 'landscape' : 'portrait',
        );
        await FirebaseCrashlytics.instance.setCustomKey(
          'layout_logical_width',
          logicalSize.width.round(),
        );
        await FirebaseCrashlytics.instance.setCustomKey(
          'layout_logical_height',
          logicalSize.height.round(),
        );
      }
      await FirebaseCrashlytics.instance.recordFlutterError(details);
    } catch (_) {
      // Telemetry must not become another user-visible failure.
    }
  }

  /// Errors reported by Flutter's image pipeline (NetworkImage, decode
  /// failures, etc.) are not app crashes. The framework surfaces them via
  /// `errorBuilder` on Image widgets; promoting them to fatal Crashlytics
  /// events drowns real crashes in deleted-avatar / expired-token noise.
  bool _isImageLibraryError(FlutterErrorDetails details) {
    return details.library == 'image resource service';
  }

  /// Reflects the current [ConsentState.crash] value in Crashlytics' native
  /// collection flag. Safe to call repeatedly.
  Future<void> applyConsent(ConsentState consent) async {
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        consent.effectiveCrash,
      );
    } catch (_) {
      // Swallow: a Crashlytics config call must never break the app.
    }
  }

  /// Emits a single non-fatal event for verifying development Crashlytics
  /// wiring and the coarse diagnostic keys set by this service.
  ///
  /// The probe is inert unless the app is a development build compiled with
  /// `--dart-define=CRASHLYTICS_DIAGNOSTIC_PROBE=true`, and it never overrides
  /// the merchant's crash-reporting consent.
  Future<bool> recordDevelopmentDiagnosticProbe({
    required bool crashReportingConsented,
  }) async {
    if (!SpazaRuntimeEnvironment.isDevelopment ||
        !_developmentProbeEnabled ||
        !crashReportingConsented ||
        _developmentProbeRecorded) {
      return false;
    }
    _developmentProbeRecorded = true;
    try {
      await _setDiagnosticValues({
        'diagnostic_probe': 'development_nonfatal',
      });
      await FirebaseCrashlytics.instance.recordError(
        StateError('SpazaOne development Crashlytics diagnostic probe'),
        StackTrace.current,
        reason: 'development diagnostics verification',
        fatal: false,
      );
      await FirebaseCrashlytics.instance.sendUnsentReports();
      return true;
    } catch (_) {
      // Telemetry verification must never affect the app flow.
      return false;
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
        await FirebaseCrashlytics.instance.setCustomKey(
          entry.key,
          entry.value.toString(),
        );
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
  Future<void> log(
    String message, {
    Map<String, Object> context = const {},
  }) async {
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

  /// Backwards-compatible auth-state hook. No account identifier is retained.
  Future<void> setMerchantId(String? merchantId) async {
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier('');
      await _setDiagnosticValues({
        'auth_state': merchantId?.trim().isNotEmpty == true
            ? 'authenticated'
            : 'anonymous',
      });
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
      'identity_number',
      'document_number',
      'passport_number',
      'business_registration_number',
      'account_number',
      'bank_account_number',
      'card_number',
      'cvv',
      'pin',
      'password',
      'otp',
      'address',
      'coordinates',
      'latitude',
      'longitude',
      'balance',
      'amount',
      'raw_payload',
      'payload',
      'user_id',
      'merchant_id',
      'store_id',
      'customer_id',
      'account_id',
    };
    return {
      for (final entry in context.entries)
        if (!blocked.contains(entry.key.toLowerCase()))
          entry.key: {'route', 'surface'}.contains(entry.key.toLowerCase())
              ? sanitizeSurfaceForTesting(entry.value.toString())
              : entry.value,
    };
  }
}

class _CrashNavigatorObserver extends NavigatorObserver {
  void _record(Route<dynamic>? route) {
    unawaited(CrashService.instance.setSurface(route?.settings.name));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _record(newRoute);
  }
}
