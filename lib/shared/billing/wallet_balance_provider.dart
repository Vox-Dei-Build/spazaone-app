import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/services/store_session.dart';
import 'package:flutter/foundation.dart';

typedef WalletDataStreamFactory = Stream<Map<String, dynamic>?> Function(
  String documentId,
);

/// A lightweight global provider for the merchant's spendable wallet balance.
///
/// Subscribes to the selected store's wallet and exposes `virtualBalance`
/// (and the green "sales proceeds" indicator) as observable state. Enrolled
/// stores read campaign credits from a balance-only shared projection while
/// sales proceeds remain bound to the active store. This lets
/// every screen — page header pill, affordability footer, cost confirmation
/// sheet — read live balance without re-rolling its own Firestore stream.
///
/// Auth-aware: re-subscribes when the user logs in/out. Safe to register at
/// `MultiProvider` root.
class WalletBalanceProvider extends ChangeNotifier {
  WalletBalanceProvider({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    StoreSession? storeSession,
    @visibleForTesting Stream<String?>? authUserIds,
    @visibleForTesting String? initialAuthUserId,
    @visibleForTesting WalletDataStreamFactory? storeWalletStream,
    @visibleForTesting WalletDataStreamFactory? campaignWalletStream,
  })  : _auth = auth ??
            (authUserIds == null && initialAuthUserId == null
                ? FirebaseAuth.instance
                : null),
        _firestore = firestore ??
            (storeWalletStream == null && campaignWalletStream == null
                ? FirebaseFirestore.instance
                : null),
        _storeSession = storeSession ?? StoreSession.instance {
    _storeWalletStream = storeWalletStream ??
        (storeId) => _firestore!
            .collection('users')
            .doc(storeId)
            .collection('wallet')
            .doc('current')
            .snapshots()
            .map((snapshot) => snapshot.data());
    _campaignWalletStream = campaignWalletStream ??
        (walletId) => _firestore!
            .collection('campaignWalletBalances')
            .doc(walletId)
            .snapshots()
            .map((snapshot) => snapshot.data());

    _storeSession.addListener(_onStoreChanged);
    if (authUserIds != null) {
      _authSub = authUserIds.listen(_onAuthUserIdChanged);
      _onAuthUserIdChanged(initialAuthUserId);
    } else {
      _authSub = _auth!.authStateChanges().map((user) => user?.uid).listen(
            _onAuthUserIdChanged,
          );
      _onAuthUserIdChanged(_auth?.currentUser?.uid);
    }
  }

  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  final StoreSession _storeSession;
  late final WalletDataStreamFactory _storeWalletStream;
  late final WalletDataStreamFactory _campaignWalletStream;

  StreamSubscription<String?>? _authSub;
  StreamSubscription<Map<String, dynamic>?>? _storeWalletSub;
  StreamSubscription<Map<String, dynamic>?>? _campaignSub;
  String? _currentUserId;
  String _boundStoreId = '';
  String _boundCampaignWalletId = '';
  bool _boundShared = false;
  bool _storeLoaded = false;
  bool _campaignLoaded = false;
  int _subscriptionGeneration = 0;
  bool _disposed = false;

  double _virtualBalance = 0.0;
  double _salesVirtualBalance = 0.0;
  bool _isLoading = true;
  bool _hasError = false;

  /// Spendable wallet balance in ZAR. Used to gate sends/top-ups.
  double get virtualBalance => _virtualBalance;

  /// Pending sales proceeds in ZAR. Drives the green dot on the wallet pill.
  double get salesVirtualBalance => _salesVirtualBalance;

  /// True until the first wallet snapshot resolves (or fails). Drives shimmer.
  bool get isLoading => _isLoading;

  /// True if the wallet stream has errored. Falls back to last known values.
  bool get hasError => _hasError;

  bool get sharedCampaignCredits => _boundShared;
  String get activeStoreName => _storeSession.activeStoreName;

  /// Convenience: whether the user can afford a given action cost.
  bool canAfford(double cost) => _virtualBalance >= cost;

  void _onAuthUserIdChanged(String? userId) {
    final trimmed = userId?.trim() ?? '';
    _currentUserId = trimmed.isEmpty ? null : trimmed;
    _subscribeToActiveStore();
  }

  void _onStoreChanged() {
    if (_currentUserId == null) {
      _subscribeToActiveStore();
      return;
    }
    if (_storeSession.storeId != _boundStoreId ||
        _storeSession.campaignWalletStoreId != _boundCampaignWalletId ||
        _storeSession.usesSharedCampaignCredits != _boundShared) {
      _subscribeToActiveStore();
    }
  }

  void _subscribeToActiveStore() {
    final generation = ++_subscriptionGeneration;
    _storeWalletSub?.cancel();
    _campaignSub?.cancel();
    _storeWalletSub = null;
    _campaignSub = null;
    final userId = _currentUserId;
    final storeId = _storeSession.storeId.trim();
    final shared = _storeSession.usesSharedCampaignCredits;
    final campaignWalletId =
        shared ? _storeSession.campaignWalletStoreId.trim() : storeId;

    if (userId == null ||
        storeId.isEmpty ||
        (shared && campaignWalletId.isEmpty)) {
      _resetUnboundState();
      return;
    }

    _isLoading = true;
    _hasError = false;
    notifyListeners();

    _boundStoreId = storeId;
    _boundCampaignWalletId = campaignWalletId;
    _boundShared = shared;
    _virtualBalance = 0.0;
    _salesVirtualBalance = 0.0;
    _storeLoaded = false;
    _campaignLoaded = !shared;
    _storeWalletSub = _storeWalletStream(storeId).listen(
      (data) {
        if (!_accepts(generation, storeId, campaignWalletId, shared)) return;
        final vb = data?['virtualBalance'];
        final sb = data?['salesVirtualBalance'];
        if (!shared) {
          _virtualBalance = vb is num ? vb.toDouble() : 0.0;
        }
        _salesVirtualBalance = sb is num ? sb.toDouble() : 0.0;
        _storeLoaded = true;
        _isLoading = !(_storeLoaded && _campaignLoaded);
        _hasError = false;
        notifyListeners();
      },
      onError: (Object _) {
        if (!_accepts(generation, storeId, campaignWalletId, shared)) return;
        _hasError = true;
        _isLoading = false;
        notifyListeners();
      },
    );
    if (shared) {
      _campaignSub = _campaignWalletStream(campaignWalletId).listen(
        (data) {
          if (!_accepts(generation, storeId, campaignWalletId, shared)) return;
          final balance = data?['balance'];
          _virtualBalance = balance is num ? balance.toDouble() : 0.0;
          _campaignLoaded = true;
          _isLoading = !(_storeLoaded && _campaignLoaded);
          _hasError = false;
          notifyListeners();
        },
        onError: (Object _) {
          if (!_accepts(generation, storeId, campaignWalletId, shared)) return;
          _hasError = true;
          _isLoading = false;
          notifyListeners();
        },
      );
    }
  }

  bool _accepts(
    int generation,
    String storeId,
    String campaignWalletId,
    bool shared,
  ) {
    return !_disposed &&
        generation == _subscriptionGeneration &&
        storeId == _boundStoreId &&
        campaignWalletId == _boundCampaignWalletId &&
        shared == _boundShared;
  }

  void _resetUnboundState() {
    _boundStoreId = '';
    _boundCampaignWalletId = '';
    _boundShared = false;
    _storeLoaded = false;
    _campaignLoaded = false;
    _virtualBalance = 0.0;
    _salesVirtualBalance = 0.0;
    _isLoading = false;
    _hasError = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscriptionGeneration++;
    _storeSession.removeListener(_onStoreChanged);
    _authSub?.cancel();
    _storeWalletSub?.cancel();
    _campaignSub?.cancel();
    super.dispose();
  }
}
