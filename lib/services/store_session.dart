import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/utils/feature_flags.dart';

enum StoreRole { owner, admin, operator }

StoreRole _parseRole(Object? value) {
  switch (value?.toString()) {
    case 'owner':
      return StoreRole.owner;
    case 'admin':
      return StoreRole.admin;
    default:
      return StoreRole.operator;
  }
}

class StoreMembership {
  const StoreMembership({
    required this.storeId,
    required this.storeName,
    required this.role,
    this.campaignWalletStoreId,
    this.sharedCampaignCredits = false,
  });

  final String storeId;
  final String storeName;
  final StoreRole role;
  final String? campaignWalletStoreId;
  final bool sharedCampaignCredits;

  String get resolvedCampaignWalletStoreId {
    final configured = campaignWalletStoreId?.trim() ?? '';
    return sharedCampaignCredits && configured.isNotEmpty
        ? configured
        : storeId;
  }

  bool get canManageOperators =>
      role == StoreRole.owner || role == StoreRole.admin;

  factory StoreMembership.fromMap(Map<Object?, Object?> data) {
    return StoreMembership(
      storeId: data['storeId']?.toString().trim() ?? '',
      storeName: data['storeName']?.toString().trim().isNotEmpty == true
          ? data['storeName'].toString().trim()
          : 'Store',
      role: _parseRole(data['role']),
      campaignWalletStoreId: data['campaignWalletStoreId']?.toString().trim(),
      sharedCampaignCredits: data['sharedCampaignCredits'] == true,
    );
  }
}

/// Authenticated operator -> active store boundary.
///
/// Existing releases use the auth uid as the store id. [storeId] deliberately
/// keeps that fallback until bootstrap returns, so a transient Functions error
/// can never lock a legacy owner out of their existing data.
class StoreSession extends ChangeNotifier {
  StoreSession._();

  static final StoreSession instance = StoreSession._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  List<StoreMembership> _stores = const [];
  String? _activeStoreId;
  bool _loading = false;
  Object? _lastError;
  bool _sharedCampaignCreditsEnrollmentAllowed = false;

  List<StoreMembership> get stores => List.unmodifiable(_stores);
  bool get loading => _loading;
  Object? get lastError => _lastError;
  bool get canEnrollSharedCampaignCredits =>
      FeatureFlags.enableSharedCampaignCreditsEnrollment &&
      _sharedCampaignCreditsEnrollmentAllowed;

  String get storeId => _activeStoreId ?? _auth.currentUser?.uid.trim() ?? '';

  StoreMembership? get activeStore {
    final id = storeId;
    for (final store in _stores) {
      if (store.storeId == id) return store;
    }
    return null;
  }

  String get activeStoreName => activeStore?.storeName ?? 'My Store';
  bool get canManageOperators => activeStore?.canManageOperators ?? true;
  bool get usesSharedCampaignCredits =>
      activeStore?.sharedCampaignCredits ?? false;
  String get campaignWalletStoreId =>
      activeStore?.resolvedCampaignWalletStoreId ?? storeId;

  StoreMembership? membershipForStore(String id) {
    for (final store in _stores) {
      if (store.storeId == id) return store;
    }
    return null;
  }

  String campaignWalletStoreIdFor(String id) =>
      membershipForStore(id)?.resolvedCampaignWalletStoreId ?? id;

  bool usesSharedCampaignCreditsFor(String id) =>
      membershipForStore(id)?.sharedCampaignCredits ?? false;

  Future<void> bootstrap() async {
    final user = _auth.currentUser;
    if (user == null) {
      clear();
      return;
    }
    if (!FeatureFlags.enableMultiStoreOperators) {
      _activeStoreId = user.uid;
      _stores = [
        StoreMembership(
          storeId: user.uid,
          storeName: 'My Store',
          role: StoreRole.owner,
        ),
      ];
      _loading = false;
      _lastError = null;
      _sharedCampaignCreditsEnrollmentAllowed = false;
      notifyListeners();
      return;
    }
    if (_loading) return;
    _loading = true;
    _lastError = null;
    notifyListeners();

    try {
      final result = await _functions
          .httpsCallable('bootstrapStoreAccess')
          .call<Map<Object?, Object?>>()
          .timeout(const Duration(seconds: 12));
      final payload = result.data;
      _sharedCampaignCreditsEnrollmentAllowed =
          payload['sharedCampaignCreditsEnrollmentAllowed'] == true;
      final rawStores = payload['stores'] as List? ?? const [];
      final parsed = rawStores
          .whereType<Map>()
          .map((item) => StoreMembership.fromMap(item))
          .where((item) => item.storeId.isNotEmpty)
          .toList(growable: false);

      if (parsed.isEmpty) {
        // Compatibility fallback for an old backend or a temporary outage.
        _stores = [
          StoreMembership(
            storeId: user.uid,
            storeName: 'My Store',
            role: StoreRole.owner,
          ),
        ];
      } else {
        _stores = parsed;
      }

      final saved = _readSavedStore(user.uid);
      final selected =
          saved != null && _stores.any((item) => item.storeId == saved)
              ? saved
              : _stores.first.storeId;
      _activeStoreId = selected;
      await _saveActiveStore(user.uid, selected);
    } catch (error) {
      _lastError = error;
      _sharedCampaignCreditsEnrollmentAllowed = false;
      _activeStoreId ??= user.uid;
      if (_stores.isEmpty) {
        _stores = [
          StoreMembership(
            storeId: user.uid,
            storeName: 'My Store',
            role: StoreRole.owner,
          ),
        ];
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> selectStore(String nextStoreId) async {
    final user = _auth.currentUser;
    if (user == null || !_stores.any((s) => s.storeId == nextStoreId)) {
      throw StateError('Store access is unavailable.');
    }
    if (_activeStoreId == nextStoreId) return;
    _activeStoreId = nextStoreId;
    await _saveActiveStore(user.uid, nextStoreId);
    notifyListeners();
  }

  Future<StoreMembership> createStore({
    required String name,
    required String operatorName,
  }) async {
    final callable = _functions.httpsCallable('createStore');
    final result = await callable.call<Map<Object?, Object?>>({
      'name': name.trim(),
      'operatorName': operatorName.trim(),
      'shareCampaignCredits': canEnrollSharedCampaignCredits,
    });
    final created = StoreMembership.fromMap(result.data);
    await bootstrap();
    await selectStore(created.storeId);
    return created;
  }

  Future<String> inviteOperator({
    required String phone,
    required StoreRole role,
  }) async {
    if (role == StoreRole.owner) {
      throw ArgumentError('Owner cannot be assigned through an invitation.');
    }
    final result = await _functions
        .httpsCallable('inviteStoreOperator')
        .call<Map<Object?, Object?>>({
      'storeId': storeId,
      'phone': phone.trim(),
      'role': role.name,
    });
    return result.data['status']?.toString() ?? 'invited';
  }

  Future<Map<String, dynamic>> loadOperators() async {
    final result = await _functions
        .httpsCallable('listStoreOperators')
        .call<Map<Object?, Object?>>({'storeId': storeId});
    return Map<String, dynamic>.from(result.data);
  }

  Future<void> removeOperator(String operatorUid) async {
    await _functions.httpsCallable('removeStoreOperator').call({
      'storeId': storeId,
      'operatorUid': operatorUid,
    });
  }

  Future<void> cancelInvite(String inviteId) async {
    await _functions.httpsCallable('cancelStoreOperatorInvite').call({
      'storeId': storeId,
      'inviteId': inviteId,
    });
  }

  void clear() {
    _stores = const [];
    _activeStoreId = null;
    _loading = false;
    _lastError = null;
    _sharedCampaignCreditsEnrollmentAllowed = false;
    notifyListeners();
  }

  String? _readSavedStore(String uid) {
    if (!Hive.isBoxOpen('appBox')) return null;
    return Hive.box('appBox').get('active_store:$uid') as String?;
  }

  Future<void> _saveActiveStore(String uid, String storeId) async {
    if (!Hive.isBoxOpen('appBox')) return;
    await Hive.box('appBox').put('active_store:$uid', storeId);
  }
}
