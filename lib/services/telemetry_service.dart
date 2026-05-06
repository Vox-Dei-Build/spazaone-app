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
  static const _envKey = 'posthog_key';

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

  /// Stitches the PostHog anonymous id to the merchant's Firebase UID.
  /// Call once after a successful sign-in.
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
  }

  /// Clears the identified user (call on sign-out) and starts a new
  /// anonymous session.
  Future<void> reset() async {
    if (!_setupCalled) return;
    try {
      await Posthog().reset();
    } catch (_) {
      // ignored
    }
  }

  /// Captures a typed [AnalyticsEvent]. No-op if analytics is disabled.
  Future<void> capture(AnalyticsEvent event) async {
    if (!_enabled) return;
    try {
      final scrubbed = _scrub(event.properties);
      await Posthog().capture(
        eventName: event.name,
        properties: scrubbed,
      );
    } catch (_) {
      // ignored -- telemetry never breaks the caller
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
