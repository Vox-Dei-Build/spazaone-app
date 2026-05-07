import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// A lightweight global provider for the merchant's spendable wallet balance.
///
/// Subscribes to `users/{uid}/wallet/current` and exposes `virtualBalance`
/// (and the green "sales proceeds" indicator) as observable state. This lets
/// every screen — page header pill, affordability footer, cost confirmation
/// sheet — read live balance without re-rolling its own Firestore stream.
///
/// Auth-aware: re-subscribes when the user logs in/out. Safe to register at
/// `MultiProvider` root.
class WalletBalanceProvider extends ChangeNotifier {
  WalletBalanceProvider({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance {
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
    // Kick off immediately if a user is already signed in at construction.
    _onAuthChanged(_auth.currentUser);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _walletSub;

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

  /// Convenience: whether the user can afford a given action cost.
  bool canAfford(double cost) => _virtualBalance >= cost;

  void _onAuthChanged(User? user) {
    _walletSub?.cancel();
    _walletSub = null;

    if (user == null) {
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

    _walletSub = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('wallet')
        .doc('current')
        .snapshots()
        .listen(
      (snap) {
        final data = snap.data();
        final vb = data?['virtualBalance'];
        final sb = data?['salesVirtualBalance'];
        _virtualBalance = vb is num ? vb.toDouble() : 0.0;
        _salesVirtualBalance = sb is num ? sb.toDouble() : 0.0;
        _isLoading = false;
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

  @override
  void dispose() {
    _authSub?.cancel();
    _walletSub?.cancel();
    super.dispose();
  }
}
