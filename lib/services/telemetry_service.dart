import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import 'analytics_event.dart';
import 'consent_service.dart';
import 'crash_service.dart';

/// Single entry point for all PostHog interaction.
///
/// Why a wrapper:
///   * Lessons from Smartlook -- scattered SDK calls across the codebase made
///     removal painful. Every PostHog call goes through this class so when
///     (not if) we replace or upgrade the SDK, the blast radius is one file.
///   * Consent gating. We force `optOut = true` during `setup()` and only
///     flip it off after [ConsentService] reports analytics consent. This
///     means the SDK never sends a single event before the user has agreed.
///   * PII scrubbing. PostHog 4.11 has no `beforeSend` hook, so we scrub
///     properties here before calling `Posthog().capture()`. Replay snapshots
///     are masked at SDK config time (see [_buildConfig]) and at widget level
///     via `PostHogMaskWidget`.
///   * Typed events. The public API only accepts [AnalyticsEvent] subclasses;
///     no callsite can fire a free-form string + map.
class TelemetryService {
  TelemetryService._();
  static final TelemetryService instance = TelemetryService._();

  static const _euHost = 'https://eu.i.posthog.com';
  static const _envKey = 'POSTHOG_KEY';

  bool _setupCalled = false;
  bool _enabled = false;

  /// Convenience: PostHog's navigator observer to wire screen-view events.
  /// Available immediately so it can be passed to MaterialApp regardless of
  /// whether the user has consented yet -- the observer fires no-ops when
  /// the SDK is opted out.
  final PosthogObserver navigatorObserver = PosthogObserver();

  /// Initialises the SDK and applies the persisted consent state.
  ///
  /// Order of operations matters:
  ///   1. Read `.env` for the project token.
  ///   2. Call `Posthog().setup(...)` exactly once with `optOut = true` so
  ///      nothing is captured before consent.
  ///   3. Read the consent state and, if analytics is enabled, flip optOut
  ///      off and start session replay if replay is also enabled.
  ///
  /// If the project token is missing the wrapper degrades to a no-op so
  /// debug/local builds without `.env` still run.
  Future<void> init() async {
    if (_setupCalled) return;
    _setupCalled = true;

    final apiKey = dotenv.maybeGet(_envKey)?.trim() ?? '';
    if (apiKey.isEmpty) {
      // Fail open: log once and stay disabled. This keeps local dev frictionless.
      if (kDebugMode) {
        debugPrint(
          '[telemetry] $_envKey missing from .env -- PostHog disabled.',
        );
      }
      return;
    }

    final config = _buildConfig(apiKey);

    try {
      await Posthog().setup(config);
    } catch (e, st) {
      // Never let telemetry init crash the host app.
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'PostHog setup failed',
      );
      return;
    }

    await applyConsent(ConsentService.instance.state);
  }

  PostHogConfig _buildConfig(String apiKey) {
    final config = PostHogConfig(apiKey)
      ..host = _euHost
      ..captureApplicationLifecycleEvents = true
      ..debug = kDebugMode
      // Identify-only person profiles: anonymous events do not create a person
      // profile (cheaper, simpler audit). Once `identify()` is called we get
      // a stitched profile keyed by Firebase UID.
      ..personProfiles = PostHogPersonProfiles.identifiedOnly
      // Hard gate. We flip this off in [applyConsent] only when the user has
      // explicitly agreed. Without this the SDK could send events between
      // setup() returning and applyConsent() running.
      ..optOut = true
      ..sessionReplay = true;

    // Strict masking: every text node and image is masked at the native
    // recorder level. Specific widgets can be unmasked later with
    // PostHogMaskWidget(masking: false) once we've audited what's safe.
    config.sessionReplayConfig
      ..maskAllTexts = true
      ..maskAllImages = true;

    return config;
  }

  /// Reflects the current consent state in PostHog's runtime state.
  ///
  /// Called from:
  ///   * [init] right after `setup()`.
  ///   * Settings -> Privacy when the user toggles a switch.
  ///   * The first-run consent modal when the user submits their choices.
  Future<void> applyConsent(ConsentState consent) async {
    if (!_setupCalled) return;
    try {
      if (consent.analytics) {
        await Posthog().enable();
        _enabled = true;
      } else {
        await Posthog().disable();
        _enabled = false;
      }

      // Replay is a strict subset of analytics: you cannot record without
      // also capturing events. The PostHog SDK enforces this implicitly
      // (replay snapshots ride on the same transport) so when analytics is
      // off, replay is automatically off too.
      //
      // PostHog 4.11 has no runtime API to start/stop replay independently
      // of opt-out -- replay follows the `sessionReplay` config flag which
      // is set once at setup. If the user disables replay but keeps
      // analytics, we cannot honour that within this SDK version. See note
      // in docs/observability.md; we'll revisit when we move to PostHog 5.x.
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'PostHog applyConsent failed',
      );
    }
  }

  /// Stitches the PostHog anonymous id to the merchant's Firebase UID, and
  /// mirrors the same id into Firebase Analytics so GA4 / Google Ads can
  /// attribute downstream conversions (and retention cohorts) to the same
  /// merchant across sessions.
  Future<void> identify({
    required String merchantId,
    String? businessType,
    String? businessCategory,
  }) async {
    if (!_enabled) return;
    try {
      await Posthog().identify(
        userId: merchantId,
        userProperties: {
          if (businessType != null) 'business_type': businessType,
          if (businessCategory != null) 'business_category': businessCategory,
        },
      );
    } catch (_) {
      // ignored
    }
    // Firebase Analytics user stamping. Wrapped separately so a PostHog
    // failure doesn't skip FA and vice versa.
    try {
      await FirebaseAnalytics.instance.setUserId(id: merchantId);
      if (businessType != null) {
        await FirebaseAnalytics.instance.setUserProperty(
          name: 'business_type',
          value: businessType,
        );
      }
      if (businessCategory != null) {
        await FirebaseAnalytics.instance.setUserProperty(
          name: 'business_category',
          value: businessCategory,
        );
      }
    } catch (_) {
      // ignored
    }
  }

  /// Clears the identified user (call on sign-out) and starts a new
  /// anonymous session in both PostHog and Firebase Analytics.
  Future<void> reset() async {
    if (!_setupCalled) return;
    try {
      await Posthog().reset();
    } catch (_) {
      // ignored
    }
    try {
      await FirebaseAnalytics.instance.setUserId(id: null);
      await FirebaseAnalytics.instance.resetAnalyticsData();
    } catch (_) {
      // ignored
    }
  }

  /// Captures a typed [AnalyticsEvent]. No-op if analytics is disabled.
  ///
  /// PostHog is the primary sink for the full taxonomy. A small allow-list
  /// of activation events is additionally mirrored to Firebase Analytics so
  /// Google Ads / GA4 can attribute campaigns to real activation
  /// (signup -> first sale -> first payout) rather than just install volume.
  /// See [_mirrorToFirebase] for the mapping.
  Future<void> capture(AnalyticsEvent event) async {
    if (!_enabled) {
      // TEMP DEBUG (PAS-GROWTH-03 verification): remove once GA4 receipt
      // is confirmed.
      if (kDebugMode) {
        debugPrint('[telemetry] capture(${event.name}) SKIPPED -- '
            '_enabled=false (analytics consent not granted)');
      }
      return;
    }
    try {
      final scrubbed = _scrub(event.properties);
      await Posthog().capture(
        eventName: event.name,
        properties: scrubbed,
      );
    } catch (_) {
      // ignored -- telemetry never breaks the caller
    }
    // Mirror happens after PostHog so a PostHog failure doesn't drop the
    // Google Ads conversion signal.
    await _mirrorToFirebase(event);
  }

  /// Forwards a narrow allow-list of activation events to Firebase Analytics
  /// using GA4 standard event names where possible so they light up in
  /// Google Ads conversion / audience tooling without extra config:
  ///
  ///   * [SignupCompleted]   -> `sign_up`        (standard)
  ///   * [SigninCompleted]   -> `login`          (standard, retention signal)
  ///   * [CustomerCreated]   -> `generate_lead`  (standard, onboarding hop)
  ///   * [SaleCompleted]     -> `purchase`       (standard, conversion + value)
  ///   * [PayoutRequested]   -> `payout_requested` (custom)
  ///
  /// `purchase.value` is the midpoint of the existing `amountBucketZAR`
  /// band, NOT the raw transaction amount. Keeping the bucket midpoint here
  /// honours the same PII contract used elsewhere (no raw transaction sizes
  /// leave the device) while still giving Google Ads a usable ROAS signal.
  /// Update [_bucketMidpointZAR] in lock-step with `amountBucketZAR` in
  /// `analytics_event.dart` if the bands change.
  Future<void> _mirrorToFirebase(AnalyticsEvent event) async {
    try {
      final fa = FirebaseAnalytics.instance;
      // TEMP DEBUG (PAS-GROWTH-03 verification): remove once GA4 receipt
      // is confirmed. Prints every event reaching the mirror, even ones
      // that fall through the default branch -- so you can tell the
      // difference between "consent off" and "event not mapped".
      if (kDebugMode) {
        debugPrint('[fa-mirror] received ${event.runtimeType} '
            '(enabled=$_enabled)');
      }
      switch (event) {
        case SignupCompleted(:final method, :final businessType, :final businessCategory):
          await fa.logEvent(
            name: 'sign_up',
            parameters: {
              'method': method,
              if (businessType != null) 'business_type': businessType,
              if (businessCategory != null) 'business_category': businessCategory,
            },
          );
        case SigninCompleted(:final method):
          await fa.logEvent(
            name: 'login',
            parameters: {'method': method},
          );
        case CustomerCreated(:final hasImage):
          // GA4 standard `generate_lead` event. We deliberately omit the
          // optional `value` / `currency` params -- a freshly added contact
          // has no monetary value attached yet; revenue shows up on the
          // subsequent `purchase` event when the merchant transacts with
          // that customer. Marking `generate_lead` as a conversion in GA4
          // lights up the "signup -> first customer" hop in Google Ads.
          await fa.logEvent(
            name: 'generate_lead',
            parameters: {
              'has_image': hasImage ? 1 : 0,
            },
          );
        case SaleCompleted(
            :final amountBucket,
            :final isCredit,
            :final customerIsExisting,
          ):
          await fa.logEvent(
            name: 'purchase',
            parameters: {
              'currency': 'ZAR',
              'value': _bucketMidpointZAR(amountBucket),
              'amount_bucket': amountBucket,
              'is_credit': isCredit ? 1 : 0,
              'customer_is_existing': customerIsExisting ? 1 : 0,
            },
          );
        case PayoutRequested(:final amountBucket):
          await fa.logEvent(
            name: 'payout_requested',
            parameters: {
              'amount_bucket': amountBucket,
              'value': _bucketMidpointZAR(amountBucket),
              'currency': 'ZAR',
            },
          );
        default:
          // Every other event stays PostHog-only by design. Adding a new
          // FA mirror is a deliberate edit here, not a default behaviour,
          // so the GA4 / Google Ads event surface stays curated.
          return;
      }
    } catch (_) {
      // ignored -- telemetry never breaks the caller
    }
  }

  /// Midpoint (in ZAR) of each `amountBucketZAR` band. Kept here -- and not
  /// in `analytics_event.dart` -- because it is only ever used by the FA
  /// mirror; PostHog dashboards group by the bucket label, not the midpoint.
  num _bucketMidpointZAR(String bucket) {
    switch (bucket) {
      case '0-50':
        return 25;
      case '50-200':
        return 125;
      case '200-500':
        return 350;
      case '500-1000':
        return 750;
      case '1000-5000':
        return 3000;
      case '5000-20000':
        return 12500;
      case '20000+':
        return 25000;
      default:
        return 0;
    }
  }

  /// Captures a Dart exception as a PostHog `$exception` event.
  ///
  /// Crashlytics is the primary error tool; this is a secondary channel that
  /// lets us correlate exceptions with replay sessions in the PostHog UI.
  /// Call from [FlutterError.onError] and the global `runZonedGuarded`
  /// handler in `main.dart`.
  Future<void> captureException(Object error, StackTrace stack) async {
    if (!_enabled) return;
    try {
      await Posthog().capture(
        eventName: '\$exception',
        properties: {
          'exception_type': error.runtimeType.toString(),
          'exception_message': error.toString(),
          'exception_stack': stack.toString(),
        },
      );
    } catch (_) {
      // ignored
    }
  }

  /// Defence-in-depth PII scrub on event properties. Mirrors [CrashService._scrub].
  ///
  /// Drops blocked keys and any null values (PostHog's `capture` API rejects
  /// nulls -- properties are typed `Map<String, Object>`).
  Map<String, Object> _scrub(Map<String, Object?> properties) {
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
    final out = <String, Object>{};
    for (final entry in properties.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (blocked.contains(entry.key.toLowerCase())) continue;
      out[entry.key] = value;
    }
    return out;
  }
}
