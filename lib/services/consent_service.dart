import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_local_storage/hive_local_storage.dart';

/// Captures user choices made on the first-run consent modal (and re-edited
/// later via Settings -> Privacy).
///
/// Persisted to Hive box `consentBox` under key [_storageKey] as a JSON map.
@immutable
class ConsentState {
  /// `null` means the user has never seen the consent modal.
  final DateTime? decidedAt;

  /// PostHog product analytics events (capture, identify, screen views).
  final bool analytics;

  /// PostHog session replay snapshots.
  final bool replay;

  /// Firebase Crashlytics crash + non-fatal reports.
  final bool crash;

  /// Schema version. Bump if we ever need to migrate the persisted shape.
  final int version;

  const ConsentState({
    required this.analytics,
    required this.replay,
    required this.crash,
    required this.decidedAt,
    this.version = 1,
  });

  /// First-launch UI defaults:
  ///   * `crash: true`   -- preselects crash reports in the consent UI.
  ///   * `analytics: true` -- preselects usage insights in the consent UI.
  ///   * `replay: false` -- session replay is screen recording and remains
  ///     opt-in only.
  ///
  /// These are presentation defaults only. The `effective*` getters below
  /// return false while `decidedAt` is null, so no telemetry sink is enabled
  /// before the merchant has made a choice.
  ///
  /// `decidedAt` is null so we still know to show the modal on first launch.
  const ConsentState.firstRun()
    : analytics = true,
      replay = false,
      crash = true,
      decidedAt = null,
      version = 1;

  bool get hasDecided => decidedAt != null;

  bool get effectiveAnalytics => hasDecided && analytics;

  bool get effectiveReplay => hasDecided && analytics && replay;

  bool get effectiveCrash => hasDecided && crash;

  ConsentState copyWith({
    bool? analytics,
    bool? replay,
    bool? crash,
    DateTime? decidedAt,
  }) {
    return ConsentState(
      analytics: analytics ?? this.analytics,
      replay: replay ?? this.replay,
      crash: crash ?? this.crash,
      decidedAt: decidedAt ?? this.decidedAt,
      version: version,
    );
  }

  Map<String, dynamic> toJson() => {
    'analytics': analytics,
    'replay': replay,
    'crash': crash,
    'decidedAt': decidedAt?.toIso8601String(),
    'version': version,
  };

  factory ConsentState.fromJson(Map<String, dynamic> json) {
    return ConsentState(
      analytics: json['analytics'] as bool? ?? false,
      replay: json['replay'] as bool? ?? false,
      crash: json['crash'] as bool? ?? true,
      decidedAt:
          (json['decidedAt'] as String?) != null
              ? DateTime.tryParse(json['decidedAt'] as String)
              : null,
      version: json['version'] as int? ?? 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConsentState &&
          other.analytics == analytics &&
          other.replay == replay &&
          other.crash == crash &&
          other.decidedAt == decidedAt &&
          other.version == version;

  @override
  int get hashCode => Object.hash(analytics, replay, crash, decidedAt, version);
}

/// Singleton wrapper around the Hive-backed consent state.
///
/// Initialise once from `main()` after `Hive.openBox('consentBox')` has run.
/// Listen to [notifier] to react to consent changes (e.g. enable/disable
/// telemetry at runtime when the user toggles a switch in Settings).
class ConsentService {
  ConsentService._();
  static final ConsentService instance = ConsentService._();

  static const String boxName = 'consentBox';
  static const String _storageKey = 'consent_v1';

  late final ValueNotifier<ConsentState> notifier;
  bool _initialised = false;

  ConsentState get state => notifier.value;

  /// Reads the persisted consent state (or seeds [ConsentState.firstRun] if
  /// none exists). Safe to call multiple times; only the first call has effect.
  Future<void> init() async {
    if (_initialised) return;
    final box = Hive.box(boxName);
    final raw = box.get(_storageKey);

    ConsentState loaded;
    if (raw is String && raw.isNotEmpty) {
      try {
        loaded = ConsentState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // Corrupt or schema-mismatched payload: fall back to first-run defaults
        // and re-prompt the user. We deliberately do NOT throw here -- consent
        // must never be the reason the app fails to launch.
        loaded = const ConsentState.firstRun();
      }
    } else {
      loaded = const ConsentState.firstRun();
    }

    notifier = ValueNotifier<ConsentState>(loaded);
    _initialised = true;
  }

  /// Persists [next] and updates [notifier] so listeners re-evaluate.
  Future<void> update(ConsentState next) async {
    final stamped = next.copyWith(decidedAt: next.decidedAt ?? DateTime.now());
    final box = Hive.box(boxName);
    await box.put(_storageKey, jsonEncode(stamped.toJson()));
    notifier.value = stamped;
  }

  /// Convenience used by the consent modal "Accept all" / "Reject all" buttons.
  Future<void> recordDecision({
    required bool analytics,
    required bool replay,
    required bool crash,
  }) {
    return update(
      ConsentState(
        analytics: analytics,
        replay: replay,
        crash: crash,
        decidedAt: DateTime.now(),
      ),
    );
  }
}
