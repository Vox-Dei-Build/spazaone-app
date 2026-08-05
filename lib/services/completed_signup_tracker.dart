import 'package:hive_local_storage/hive_local_storage.dart';

import 'analytics_event.dart';
import 'consent_service.dart';
import 'telemetry_service.dart';

typedef CompletedSignupEmitter = Future<void> Function(
    {required String merchantId, required String method});

/// Records the acquisition-quality signup signal once, after consent.
///
/// Phone authentication can complete before the deferred consent sheet is
/// shown. Sending the event at the auth callback would therefore drop it while
/// analytics is disabled. This tracker persists a PII-free pending marker and
/// flushes it after the merchant has made a consent choice.
///
/// A marker is also retained after a successful send so retries, app resumes,
/// and duplicate Firebase auth callbacks cannot count the same account twice.
/// Rejected consent is terminal too: a later opt-in must not backdate signup.
class CompletedSignupTracker {
  CompletedSignupTracker({
    Box<dynamic>? box,
    ConsentState Function()? consentState,
    CompletedSignupEmitter? emit,
  })  : _boxOverride = box,
        _consentStateOverride = consentState,
        _emitOverride = emit;

  static final CompletedSignupTracker instance = CompletedSignupTracker();

  static const _pendingPrefix = 'measurement.completed_signup.pending.';
  static const _resolutionPrefix = 'measurement.completed_signup.resolution.';

  final Box<dynamic>? _boxOverride;
  final ConsentState Function()? _consentStateOverride;
  final CompletedSignupEmitter? _emitOverride;
  final Map<String, Future<void>> _operations = {};

  Box<dynamic> get _box => _boxOverride ?? Hive.box('appBox');

  ConsentState get _consentState =>
      _consentStateOverride?.call() ?? ConsentService.instance.state;

  String _pendingKey(String merchantId) => '$_pendingPrefix$merchantId';

  String _resolutionKey(String merchantId) => '$_resolutionPrefix$merchantId';

  bool _isResolved(String merchantId) =>
      _box.get(_resolutionKey(merchantId)) != null;

  /// Records a completed phone signup or defers it until consent is resolved.
  Future<void> recordPhoneSignup({required String merchantId}) {
    if (merchantId.isEmpty) return Future<void>.value();
    return _enqueue(
      merchantId,
      () => _recordPhoneSignup(merchantId: merchantId),
    );
  }

  Future<void> _recordPhoneSignup({required String merchantId}) async {
    if (_isResolved(merchantId)) return;

    final consent = _consentState;
    if (!consent.hasDecided) {
      await _box.put(_pendingKey(merchantId), 'phone');
      return;
    }

    if (!consent.effectiveAnalytics) {
      await _discard(merchantId);
      return;
    }

    await _emit(merchantId: merchantId, method: 'phone');
    await _box.put(_resolutionKey(merchantId), 'sent');
    await _box.delete(_pendingKey(merchantId));
  }

  /// Resolves a pending signup after the consent surface has completed.
  ///
  /// Rejecting analytics discards the pending marker. A later opt-in must not
  /// backdate an acquisition event into a different attribution window.
  Future<void> resolveAfterConsent({required String merchantId}) {
    if (merchantId.isEmpty) return Future<void>.value();
    return _enqueue(
      merchantId,
      () => _resolveAfterConsent(merchantId: merchantId),
    );
  }

  Future<void> _resolveAfterConsent({required String merchantId}) async {
    if (_isResolved(merchantId)) return;

    final pending = _box.get(_pendingKey(merchantId));
    if (pending != 'phone') return;

    final consent = _consentState;
    if (!consent.hasDecided) return;
    if (!consent.effectiveAnalytics) {
      await _discard(merchantId);
      return;
    }

    await _recordPhoneSignup(merchantId: merchantId);
  }

  Future<void> _discard(String merchantId) async {
    await _box.put(_resolutionKey(merchantId), 'discarded');
    await _box.delete(_pendingKey(merchantId));
  }

  Future<void> _enqueue(
    String merchantId,
    Future<void> Function() operation,
  ) {
    final previous = _operations[merchantId];
    late final Future<void> queued;
    queued = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // A later callback may safely retry a failed telemetry operation.
        }
      }
      try {
        await operation();
      } finally {
        if (identical(_operations[merchantId], queued)) {
          _operations.remove(merchantId);
        }
      }
    }();
    _operations[merchantId] = queued;
    return queued;
  }

  Future<void> _emit({
    required String merchantId,
    required String method,
  }) async {
    final override = _emitOverride;
    if (override != null) {
      await override(merchantId: merchantId, method: method);
      return;
    }

    await TelemetryService.instance.identify(merchantId: merchantId);
    await TelemetryService.instance.capture(SignupCompleted(method: method));
  }
}
