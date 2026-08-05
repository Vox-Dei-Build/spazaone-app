import 'package:hive_local_storage/hive_local_storage.dart';

import 'analytics_event.dart';
import 'consent_service.dart';
import 'telemetry_service.dart';

typedef PaymentReceiptEmitter = Future<void> Function(PaymentReceived event);

/// Hands each confirmed payment to analytics once within a bounded retry
/// window on this app install.
///
/// GA4 does not deduplicate transaction IDs for app streams. The stable ID is
/// still sent for reconciliation, while a capped 180-day local receipt set
/// protects the normal retry/resume path without growing storage forever.
class PaymentReceiptTracker {
  PaymentReceiptTracker({
    Box<dynamic>? box,
    ConsentState Function()? consentState,
    PaymentReceiptEmitter? emit,
    DateTime Function()? now,
  })  : _boxOverride = box,
        _consentStateOverride = consentState,
        _emitOverride = emit,
        _nowOverride = now;

  static final PaymentReceiptTracker instance = PaymentReceiptTracker();

  static const _resolutionsKey = 'measurement.payment_received.resolutions.v1';
  static const _retention = Duration(days: 180);
  static const _maxResolutions = 2048;

  final Box<dynamic>? _boxOverride;
  final ConsentState Function()? _consentStateOverride;
  final PaymentReceiptEmitter? _emitOverride;
  final DateTime Function()? _nowOverride;
  Future<void>? _tail;

  Box<dynamic> get _box => _boxOverride ?? Hive.box('appBox');

  ConsentState get _consentState =>
      _consentStateOverride?.call() ?? ConsentService.instance.state;

  DateTime get _now => _nowOverride?.call() ?? DateTime.now();

  Future<void> capture(PaymentReceived event) {
    final transactionId = event.transactionId.trim();
    if (transactionId.isEmpty) return Future<void>.value();
    return _enqueue(() => _capture(event, transactionId: transactionId));
  }

  Future<void> _capture(
    PaymentReceived event, {
    required String transactionId,
  }) async {
    final resolutions = _readResolutions();
    final pruned = _prune(resolutions);
    if (resolutions.containsKey(transactionId)) {
      if (pruned) await _box.put(_resolutionsKey, resolutions);
      return;
    }

    final consent = _consentState;
    if (!consent.hasDecided || !consent.effectiveAnalytics) {
      // Payment reporting never bypasses or backdates analytics consent.
      resolutions[transactionId] = _now.millisecondsSinceEpoch;
      _prune(resolutions);
      await _box.put(_resolutionsKey, resolutions);
      return;
    }

    final emit = _emitOverride ?? TelemetryService.instance.capture;
    await emit(event);
    // This records successful hand-off to the SDK, not provider delivery.
    resolutions[transactionId] = _now.millisecondsSinceEpoch;
    _prune(resolutions);
    await _box.put(_resolutionsKey, resolutions);
  }

  Map<String, int> _readResolutions() {
    final stored = _box.get(_resolutionsKey);
    if (stored is! Map) return {};
    return {
      for (final entry in stored.entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).toInt(),
    };
  }

  bool _prune(Map<String, int> resolutions) {
    var changed = false;
    final cutoff = _now.subtract(_retention).millisecondsSinceEpoch;
    resolutions.removeWhere((_, recordedAt) {
      final remove = recordedAt < cutoff;
      changed = changed || remove;
      return remove;
    });

    if (resolutions.length > _maxResolutions) {
      final oldestFirst = resolutions.entries.toList()
        ..sort((left, right) => left.value.compareTo(right.value));
      final overflow = resolutions.length - _maxResolutions;
      for (final entry in oldestFirst.take(overflow)) {
        resolutions.remove(entry.key);
      }
      changed = true;
    }
    return changed;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final previous = _tail;
    late final Future<void> queued;
    queued = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // A later callback may safely retry a failed hand-off.
        }
      }
      await operation();
    }();
    _tail = queued;
    return queued;
  }
}
