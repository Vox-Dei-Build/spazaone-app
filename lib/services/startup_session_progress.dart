import 'dart:async';

import 'package:flutter/foundation.dart';

/// An optional first-use guide can finish normally or be skipped for this
/// session (for example, offline or for an operator). Neither outcome grants
/// consent or writes a durable "seen" marker.
enum StartupOutcome { completed, skipped }

class StartupSessionToken {
  StartupSessionToken._(this.userId, this.storeId);

  final String userId;
  final String storeId;
}

/// Coordinates post-auth surfaces with notification permission. Identity is
/// in-memory and generation-bound: an old async result cannot release a new
/// login or a different store's startup queue.
class StartupSessionProgress extends ChangeNotifier {
  static final instance = StartupSessionProgress();

  StartupSessionToken? _current;
  bool _running = false;
  bool _consentSurfaceCompleted = false;
  StartupOutcome? _outcome;

  StartupSessionToken? get current => _current;
  StartupOutcome? get outcome => _outcome;
  bool get ready => _consentSurfaceCompleted && _outcome != null;

  StartupSessionToken? bind(
      {required String? userId, required String? storeId}) {
    final user = userId?.trim() ?? '';
    final store = storeId?.trim() ?? '';
    if (user.isEmpty || store.isEmpty) {
      reset();
      return null;
    }
    if (_current?.userId == user && _current?.storeId == store) return _current;
    _current = StartupSessionToken._(user, store);
    _running = false;
    _consentSurfaceCompleted = false;
    _outcome = null;
    notifyListeners();
    return _current;
  }

  bool isCurrent(StartupSessionToken token) => identical(_current, token);

  bool tryBegin(StartupSessionToken token) {
    if (!isCurrent(token) || _running || _outcome != null) return false;
    _running = true;
    return true;
  }

  void consentSurfaceClosed(StartupSessionToken token,
      {required bool consentDecided}) {
    if (!isCurrent(token) || !consentDecided || _consentSurfaceCompleted) {
      return;
    }
    _consentSurfaceCompleted = true;
    notifyListeners();
  }

  void complete(StartupSessionToken token, StartupOutcome outcome) {
    if (!isCurrent(token)) return;
    _running = false;
    _outcome = outcome;
    notifyListeners();
  }

  void abandon(StartupSessionToken token) {
    if (!isCurrent(token) || !_running) return;
    _running = false;
    notifyListeners();
  }

  Future<bool> waitUntilReady(StartupSessionToken token) {
    if (!isCurrent(token)) return Future.value(false);
    if (ready) return Future.value(true);
    final completion = Completer<bool>();
    void changed() {
      if (!isCurrent(token) || ready) {
        removeListener(changed);
        completion.complete(isCurrent(token) && ready);
      }
    }

    addListener(changed);
    return completion.future;
  }

  void reset() {
    if (_current == null) return;
    _current = null;
    _running = false;
    _consentSurfaceCompleted = false;
    _outcome = null;
    notifyListeners();
  }

  @override
  void dispose() {
    reset();
    super.dispose();
  }
}
