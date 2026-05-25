import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:in_app_review/in_app_review.dart';

import 'analytics_event.dart';
import 'crash_service.dart';
import 'telemetry_service.dart';

/// Reasons a review nudge fired (or didn't). Kept as an enum so call-sites
/// and analytics events agree on a closed taxonomy.
enum ReviewTrigger {
  /// Cash sale completed via `sale_view_model`.
  saleCompletedCash,

  /// Credit / BNPL sale completed via `add_credit_view_model`.
  saleCompletedCredit,
}

extension on ReviewTrigger {
  String get analyticsName {
    switch (this) {
      case ReviewTrigger.saleCompletedCash:
        return 'sale_completed_cash';
      case ReviewTrigger.saleCompletedCredit:
        return 'sale_completed_credit';
    }
  }
}

/// Tasteful, throttled in-app review prompt.
///
/// Why a dedicated service:
///   * Review prompts are the easiest growth feature to mis-tune. Every
///     call-site goes through one gate so the cooldown / eligibility logic
///     lives in a single, testable place.
///   * The native APIs (`SKStoreReviewController` on iOS, Google Play's
///     In-App Review on Android) are themselves quota-throttled by the
///     platform. We layer our OWN cooldown on top so we don't even ask the
///     platform until the merchant looks ready.
///   * Persisted state (counters, last-shown timestamp, opt-out flag) lives
///     in the existing `appBox` Hive box -- mirrors `MerchantHeartbeat` and
///     `ConsentService` patterns in this codebase.
///
/// Eligibility rules (all must hold):
///   1. Native `isAvailable()` returns true (Play Services on Android,
///      iOS 10.3+ on iOS).
///   2. The merchant has hit at least [_minTriggerCount] qualifying value
///      moments (e.g. 3 completed sales). New merchants are NEVER prompted
///      on their first sale.
///   3. At least [_firstPromptCooldown] has elapsed since first install /
///      first qualifying event -- gives the merchant time to actually use
///      the app before we ask for a rating.
///   4. At least [_repeatCooldown] has elapsed since the last prompt, if
///      any. After a real prompt fires we back off for a long time because
///      the platform won't show it again anyway.
///   5. The merchant has not previously opted out.
///
/// All persistence and SDK calls are wrapped in try/catch + non-fatal crash
/// reporting. Review nudges must never crash the host app.
class ReviewPromptService {
  ReviewPromptService._();
  static final ReviewPromptService instance = ReviewPromptService._();

  /// Visible for tests / debugging.
  @visibleForTesting
  static const String storageKey = 'review_prompt_state_v1';

  static const String _boxName = 'appBox';

  /// Minimum number of qualifying value moments before we'll consider asking.
  /// Three completed sales is the threshold at which the merchant has clearly
  /// adopted the core flow but is not so deep they've already formed a rigid
  /// opinion. Tunable -- read from Remote Config later if needed.
  static const int _minTriggerCount = 3;

  /// Minimum age of the merchant's local install before a first prompt.
  /// Even if they hit the trigger count fast, we don't ask on day zero.
  static const Duration _firstPromptCooldown = Duration(days: 2);

  /// Minimum gap between two prompts. We deliberately err long: the OS-level
  /// quota (Apple: ~3 prompts/365 days; Google: ~1/quarter) is the real
  /// limit, but locally we add 90 days so two app updates can't both ask.
  static const Duration _repeatCooldown = Duration(days: 90);

  InAppReview _review = InAppReview.instance;

  /// Test seam.
  @visibleForTesting
  set reviewClientForTest(InAppReview value) => _review = value;

  bool _initialised = false;
  _State _state = _State.empty();

  /// Read once during `main()` boot so the first qualifying event has state
  /// to compare against. The `appBox` Hive box must already be open.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      final box = Hive.box(_boxName);
      final raw = box.get(storageKey);
      if (raw is String && raw.isNotEmpty) {
        try {
          _state = _State.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {
          // Corrupt payload -- reset rather than crash. The merchant has at
          // worst lost their counter; they'll just re-qualify naturally.
          _state = _State.empty();
        }
      }
      // First-ever boot: seed firstSeenAt so we can enforce the minimum
      // install-age before any prompt fires.
      if (_state.firstSeenAt == null) {
        _state = _state.copyWith(firstSeenAt: DateTime.now());
        await _persist();
      }
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'ReviewPromptService.init failed',
      );
    }
  }

  /// Call this from a value-moment site. Increments the counter, evaluates
  /// eligibility, and -- if eligible -- asks the OS for the review prompt.
  ///
  /// Fire-and-forget. Returns the resolved decision for the call-site to
  /// optionally log, but no caller should await this in a critical path.
  Future<ReviewPromptOutcome> maybePrompt(ReviewTrigger trigger) async {
    if (!_initialised) {
      // Defensive: callers shouldn't fire events before init, but if they
      // do we silently no-op rather than crash.
      return ReviewPromptOutcome.notInitialised;
    }
    try {
      _state = _state.copyWith(
        triggerCount: _state.triggerCount + 1,
        lastTriggerAt: DateTime.now(),
      );
      await _persist();

      final reason = _evaluateEligibility();
      if (reason != null) {
        return reason;
      }

      // Native availability is async and can hit Play Services -- check it
      // last so we don't waste the call on already-ineligible merchants.
      final available = await _review.isAvailable();
      if (!available) {
        return ReviewPromptOutcome.notAvailable;
      }

      await _review.requestReview();

      _state = _state.copyWith(lastPromptedAt: DateTime.now(), promptCount: _state.promptCount + 1);
      await _persist();

      // Telemetry: we fire AFTER the request so a crash inside the SDK
      // doesn't leave us with a misleading "shown" event.
      // ignore: unawaited_futures
      TelemetryService.instance.capture(
        ReviewNudgeShown(triggerName: trigger.analyticsName),
      );

      return ReviewPromptOutcome.shown;
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'ReviewPromptService.maybePrompt failed',
      );
      return ReviewPromptOutcome.error;
    }
  }

  /// Lets a future Settings toggle ("Don't ask me again") permanently mute
  /// the prompt without us inventing a new schema.
  Future<void> optOut() async {
    _state = _state.copyWith(optedOut: true);
    await _persist();
  }

  /// Returns null when eligible; otherwise the reason we suppressed.
  ReviewPromptOutcome? _evaluateEligibility() {
    if (_state.optedOut) {
      return ReviewPromptOutcome.optedOut;
    }
    if (_state.triggerCount < _minTriggerCount) {
      return ReviewPromptOutcome.notEnoughActivity;
    }
    final firstSeen = _state.firstSeenAt;
    if (firstSeen == null ||
        DateTime.now().difference(firstSeen) < _firstPromptCooldown) {
      return ReviewPromptOutcome.tooEarlyAfterInstall;
    }
    final lastPrompted = _state.lastPromptedAt;
    if (lastPrompted != null &&
        DateTime.now().difference(lastPrompted) < _repeatCooldown) {
      return ReviewPromptOutcome.cooldown;
    }
    return null;
  }

  Future<void> _persist() async {
    try {
      final box = Hive.box(_boxName);
      await box.put(storageKey, jsonEncode(_state.toJson()));
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'ReviewPromptService persist failed',
      );
    }
  }

  /// Test seam: read-only snapshot of internal state.
  @visibleForTesting
  Map<String, Object?> debugStateSnapshot() => _state.toJson();

  /// Test seam: reset everything (does NOT clear Hive on its own).
  @visibleForTesting
  void resetForTest() {
    _initialised = false;
    _state = _State.empty();
  }
}

/// Outcome of a single `maybePrompt` call. Useful for telemetry and tests.
enum ReviewPromptOutcome {
  shown,
  notEnoughActivity,
  tooEarlyAfterInstall,
  cooldown,
  optedOut,
  notAvailable,
  notInitialised,
  error,
}

@immutable
class _State {
  final DateTime? firstSeenAt;
  final int triggerCount;
  final DateTime? lastTriggerAt;
  final int promptCount;
  final DateTime? lastPromptedAt;
  final bool optedOut;

  const _State({
    required this.firstSeenAt,
    required this.triggerCount,
    required this.lastTriggerAt,
    required this.promptCount,
    required this.lastPromptedAt,
    required this.optedOut,
  });

  factory _State.empty() => const _State(
        firstSeenAt: null,
        triggerCount: 0,
        lastTriggerAt: null,
        promptCount: 0,
        lastPromptedAt: null,
        optedOut: false,
      );

  _State copyWith({
    DateTime? firstSeenAt,
    int? triggerCount,
    DateTime? lastTriggerAt,
    int? promptCount,
    DateTime? lastPromptedAt,
    bool? optedOut,
  }) =>
      _State(
        firstSeenAt: firstSeenAt ?? this.firstSeenAt,
        triggerCount: triggerCount ?? this.triggerCount,
        lastTriggerAt: lastTriggerAt ?? this.lastTriggerAt,
        promptCount: promptCount ?? this.promptCount,
        lastPromptedAt: lastPromptedAt ?? this.lastPromptedAt,
        optedOut: optedOut ?? this.optedOut,
      );

  Map<String, Object?> toJson() => {
        'firstSeenAt': firstSeenAt?.toIso8601String(),
        'triggerCount': triggerCount,
        'lastTriggerAt': lastTriggerAt?.toIso8601String(),
        'promptCount': promptCount,
        'lastPromptedAt': lastPromptedAt?.toIso8601String(),
        'optedOut': optedOut,
      };

  factory _State.fromJson(Map<String, dynamic> json) => _State(
        firstSeenAt: _parseDate(json['firstSeenAt']),
        triggerCount: (json['triggerCount'] as num?)?.toInt() ?? 0,
        lastTriggerAt: _parseDate(json['lastTriggerAt']),
        promptCount: (json['promptCount'] as num?)?.toInt() ?? 0,
        lastPromptedAt: _parseDate(json['lastPromptedAt']),
        optedOut: json['optedOut'] as bool? ?? false,
      );

  static DateTime? _parseDate(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw);
    }
    return null;
  }
}
