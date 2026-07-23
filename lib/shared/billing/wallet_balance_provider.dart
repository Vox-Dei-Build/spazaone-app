import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/services/store_session.dart';
import 'package:flutter/foundation.dart';

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
  WalletBalanceProvider({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance {
    StoreSession.instance.addListener(_onStoreChanged);
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
    // Kick off immediately if a user is already signed in at construction.
    _onAuthChanged(_auth.currentUser);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _storeWalletSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _campaignSub;
  User? _currentUser;
  String _boundStoreId = '';
  String _boundCampaignWalletId = '';
  bool _boundShared = false;
  bool _storeLoaded = false;
  bool _campaignLoaded = false;

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
  String get activeStoreName => StoreSession.instance.activeStoreName;

  /// Convenience: whether the user can afford a given action cost.
  bool canAfford(double cost) => _virtualBalance >= cost;

  void _onAuthChanged(User? user) {
    _currentUser = user;
    _subscribeToActiveStore();
  }

  void _onStoreChanged() {
    if (_currentUser != null &&
        (StoreSession.instance.storeId != _boundStoreId ||
            StoreSession.instance.campaignWalletStoreId !=
                _boundCampaignWalletId ||
            StoreSession.instance.usesSharedCampaignCredits != _boundShared)) {
      _subscribeToActiveStore();
    }
  }

  void _subscribeToActiveStore() {
    _storeWalletSub?.cancel();
    _campaignSub?.cancel();
    _storeWalletSub = null;
    _campaignSub = null;
    final user = _currentUser;

    if (user == null) {
      _boundStoreId = '';
      _boundCampaignWalletId = '';
      _boundShared = false;
      _virtualBalance = 0.0;
      _salesVirtualBalance = 0.0;
      _isLoading = false;
      _hasError = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _hasError = false;
    notifyListeners();

    final storeId = StoreSession.instance.storeId;
    final campaignWalletId = StoreSession.instance.campaignWalletStoreId;
    final shared = StoreSession.instance.usesSharedCampaignCredits;
    _boundStoreId = storeId;
    _boundCampaignWalletId = campaignWalletId;
    _boundShared = shared;
    _virtualBalance = 0.0;
    _salesVirtualBalance = 0.0;
    _storeLoaded = false;
    _campaignLoaded = !shared;
    _storeWalletSub = _firestore
        .collection('users')
        .doc(storeId)
        .collection('wallet')
        .doc('current')
        .snapshots()
        .listen(
      (snap) {
        final data = snap.data();
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
        _hasError = true;
        _isLoading = false;
        notifyListeners();
      },
    );
    if (shared) {
      _campaignSub = _firestore
          .collection('campaignWalletBalances')
          .doc(campaignWalletId)
          .snapshots()
          .listen(
        (snap) {
          final balance = snap.data()?['balance'];
          _virtualBalance = balance is num ? balance.toDouble() : 0.0;
          _campaignLoaded = true;
          _isLoading = !(_storeLoaded && _campaignLoaded);
          _hasError = false;
          notifyListeners();
        },
        onError: (Object _) {
          _hasError = true;
          _isLoading = false;
          notifyListeners();
        },
      );
    }
  }

  @override
  void dispose() {
    StoreSession.instance.removeListener(_onStoreChanged);
    _authSub?.cancel();
    _storeWalletSub?.cancel();
    _campaignSub?.cancel();
    super.dispose();
  }
}
