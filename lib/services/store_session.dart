import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/utils/feature_flags.dart';

typedef StoreUserIdProvider = String? Function();
typedef StoreBootstrapLoader = Future<Map<Object?, Object?>> Function();

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

  Map<String, Object?> toMap() => {
        'storeId': storeId,
        'storeName': storeName,
        'role': role.name,
        if (campaignWalletStoreId != null)
          'campaignWalletStoreId': campaignWalletStoreId,
        'sharedCampaignCredits': sharedCampaignCredits,
      };

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

/// Small persistence boundary for the last store-access response that was
/// verified by the backend. The cache only keeps display/session continuity;
/// Firestore rules and callable checks remain authoritative for every read or
/// mutation.
abstract class StoreSessionStorage {
  List<StoreMembership> readStores(String uid);
  Future<void> writeStores(String uid, List<StoreMembership> stores);
  Future<void> clearStores(String uid);
  String? readActiveStore(String uid);
  Future<void> writeActiveStore(String uid, String storeId);
}

class HiveStoreSessionStorage implements StoreSessionStorage {
  const HiveStoreSessionStorage();

  static String _storesKey(String uid) => 'store_memberships:v1:$uid';
  static String _activeKey(String uid) => 'active_store:$uid';

  @override
  List<StoreMembership> readStores(String uid) {
    if (!Hive.isBoxOpen('appBox')) return const [];
    final raw = Hive.box('appBox').get(_storesKey(uid));
    if (raw is! List) return const [];

    final byId = <String, StoreMembership>{};
    for (final item in raw.whereType<Map>()) {
      final membership = StoreMembership.fromMap(
        Map<Object?, Object?>.from(item),
      );
      if (membership.storeId.isNotEmpty) {
        byId[membership.storeId] = membership;
      }
    }
    return byId.values.toList(growable: false);
  }

  @override
  Future<void> writeStores(
    String uid,
    List<StoreMembership> stores,
  ) async {
    if (!Hive.isBoxOpen('appBox') || stores.isEmpty) return;
    await Hive.box('appBox').put(
      _storesKey(uid),
      stores.map((store) => store.toMap()).toList(growable: false),
    );
  }

  @override
  Future<void> clearStores(String uid) async {
    if (!Hive.isBoxOpen('appBox')) return;
    await Hive.box('appBox').delete(_storesKey(uid));
  }

  @override
  String? readActiveStore(String uid) {
    if (!Hive.isBoxOpen('appBox')) return null;
    final value = Hive.box('appBox').get(_activeKey(uid));
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  @override
  Future<void> writeActiveStore(String uid, String storeId) async {
    if (!Hive.isBoxOpen('appBox')) return;
    await Hive.box('appBox').put(_activeKey(uid), storeId);
  }
}

/// Authenticated operator -> active store boundary.
///
/// Existing releases use the auth uid as the store id. [storeId] deliberately
/// keeps that fallback until bootstrap returns, so a transient Functions error
/// can never lock a legacy owner out of their existing data.
class StoreSession extends ChangeNotifier {
  StoreSession._()
      : _auth = FirebaseAuth.instance,
        _functions = FirebaseFunctions.instance,
        _userIdProvider = null,
        _bootstrapLoader = null,
        _storage = const HiveStoreSessionStorage(),
        _multiStoreEnabled = (() => FeatureFlags.enableMultiStoreOperators);

  @visibleForTesting
  StoreSession.testing({
    required StoreUserIdProvider userIdProvider,
    required StoreBootstrapLoader bootstrapLoader,
    required StoreSessionStorage storage,
    bool multiStoreEnabled = true,
  })  : _auth = null,
        _functions = null,
        _userIdProvider = userIdProvider,
        _bootstrapLoader = bootstrapLoader,
        _storage = storage,
        _multiStoreEnabled = (() => multiStoreEnabled);

  static final StoreSession instance = StoreSession._();

  final FirebaseAuth? _auth;
  final FirebaseFunctions? _functions;
  final StoreUserIdProvider? _userIdProvider;
  final StoreBootstrapLoader? _bootstrapLoader;
  final StoreSessionStorage _storage;
  final bool Function() _multiStoreEnabled;

  List<StoreMembership> _stores = const [];
  String? _activeStoreId;
  String? _boundUserId;
  int _bootstrapEpoch = 0;
  int _selectionRevision = 0;
  Future<void> _activeStoreWrite = Future<void>.value();
  bool _loading = false;
  Object? _lastError;
  bool _storeAccessResolved = false;
  bool _sharedCampaignCreditsEnrollmentAllowed = false;

  List<StoreMembership> get stores => List.unmodifiable(_stores);
  bool get loading => _loading;
  Object? get lastError => _lastError;
  bool get storeAccessResolved => _storeAccessResolved;
  bool get canEnrollSharedCampaignCredits =>
      FeatureFlags.enableSharedCampaignCreditsEnrollment &&
      _sharedCampaignCreditsEnrollmentAllowed;

  String? get _currentUserId {
    final value = _userIdProvider?.call() ?? _auth?.currentUser?.uid;
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  String get storeId => _activeStoreId ?? _currentUserId ?? '';

  StoreMembership? get activeStore {
    final id = storeId;
    for (final store in _stores) {
      if (store.storeId == id) return store;
    }
    return null;
  }

  String get activeStoreName {
    final name = activeStore?.storeName.trim() ?? '';
    if (name.isNotEmpty) return name;
    if (_loading) return 'Loading stores…';
    if (_lastError != null) return 'Stores unavailable';
    if (_storeAccessResolved) return 'No stores available';
    return 'Your store';
  }

  bool get canManageOperators => activeStore?.canManageOperators ?? false;
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
    final uid = _currentUserId;
    if (uid == null) {
      clear();
      return;
    }

    _restoreCachedState(uid);

    if (!_multiStoreEnabled()) {
      _bootstrapEpoch++;
      _activeStoreId = uid;
      final cachedPrimary = membershipForStore(uid);
      _stores = [
        cachedPrimary ??
            StoreMembership(
              storeId: uid,
              storeName: 'My Store',
              role: StoreRole.owner,
            ),
      ];
      _loading = false;
      _lastError = null;
      _storeAccessResolved = true;
      _sharedCampaignCreditsEnrollmentAllowed = false;
      notifyListeners();
      return;
    }
    if (_loading) return;
    final activeStoreWasVerified = activeStore != null;
    final selectionRevisionAtRequestStart = _selectionRevision;
    final requestEpoch = ++_bootstrapEpoch;
    _loading = true;
    _lastError = null;
    notifyListeners();

    try {
      final payload =
          await _loadBootstrapPayload().timeout(const Duration(seconds: 12));
      if (!_isCurrentRequest(uid, requestEpoch)) return;
      _sharedCampaignCreditsEnrollmentAllowed =
          payload['sharedCampaignCreditsEnrollmentAllowed'] == true;
      final rawStores = payload['stores'];
      if (rawStores is! List) {
        throw StateError('The store access response was invalid.');
      }
      final parsed = rawStores
          .whereType<Map>()
          .map((item) => StoreMembership.fromMap(item))
          .where((item) => item.storeId.isNotEmpty)
          .toList(growable: false);

      if (parsed.isEmpty) {
        // An explicit empty list is an authoritative access response (for
        // example, an operator removed from their last store). Do not retain
        // stale names or roles after the backend has confirmed revocation.
        _stores = const [];
        if (_activeStoreId != uid) {
          _activeStoreId = uid;
          _selectionRevision++;
        }
        _storeAccessResolved = true;
        await _clearVerifiedState(uid, requestEpoch);
        return;
      }

      _stores = parsed;
      _selectAvailableStore(
        uid,
        preferCurrent: activeStoreWasVerified ||
            _selectionRevision != selectionRevisionAtRequestStart,
      );
      _storeAccessResolved = true;
      final selectionRevision = _selectionRevision;
      final selectedStoreId = storeId;
      await _persistVerifiedState(
        uid,
        requestEpoch,
        selectionRevision,
        selectedStoreId,
      );
    } catch (error) {
      if (!_isCurrentRequest(uid, requestEpoch)) return;
      _lastError = error;
      _sharedCampaignCreditsEnrollmentAllowed = false;
      // Keep the cached names and selection. The uid fallback preserves the
      // legacy data path without pretending that the store is named My Store.
      _activeStoreId ??= uid;
    } finally {
      if (_isCurrentRequest(uid, requestEpoch)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> selectStore(String nextStoreId) async {
    final uid = _currentUserId;
    if (uid == null || !_stores.any((s) => s.storeId == nextStoreId)) {
      throw StateError('Store access is unavailable.');
    }
    if (_activeStoreId == nextStoreId) return;
    _activeStoreId = nextStoreId;
    _selectionRevision++;
    await _queueActiveStoreWrite(uid, nextStoreId);
    notifyListeners();
  }

  Future<StoreMembership> createStore({
    required String name,
    required String operatorName,
  }) async {
    final callable = _functions!.httpsCallable('createStore');
    final result = await callable.call<Map<Object?, Object?>>({
      'name': name.trim(),
      'operatorName': operatorName.trim(),
      // The explicit capability lets the backend reject clients that predate
      // shared wallet support instead of creating an unusable isolated store.
      'campaignCreditsMode': 'shared-v1',
      // Keep this during the staged backend rollout. The previous callable
      // understands this field and fails closed when enrollment is disabled.
      'shareCampaignCredits': true,
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
    final result = await _functions!
        .httpsCallable('inviteStoreOperator')
        .call<Map<Object?, Object?>>({
      'storeId': storeId,
      'phone': phone.trim(),
      'role': role.name,
    });
    return result.data['status']?.toString() ?? 'invited';
  }

  Future<Map<String, dynamic>> loadOperators() async {
    final result = await _functions!
        .httpsCallable('listStoreOperators')
        .call<Map<Object?, Object?>>({'storeId': storeId});
    return Map<String, dynamic>.from(result.data);
  }

  Future<void> removeOperator(String operatorUid) async {
    await _functions!.httpsCallable('removeStoreOperator').call({
      'storeId': storeId,
      'operatorUid': operatorUid,
    });
  }

  Future<void> cancelInvite(String inviteId) async {
    await _functions!.httpsCallable('cancelStoreOperatorInvite').call({
      'storeId': storeId,
      'inviteId': inviteId,
    });
  }

  void clear() {
    _bootstrapEpoch++;
    _selectionRevision++;
    _stores = const [];
    _activeStoreId = null;
    _boundUserId = null;
    _loading = false;
    _lastError = null;
    _storeAccessResolved = false;
    _sharedCampaignCreditsEnrollmentAllowed = false;
    notifyListeners();
  }

  Future<Map<Object?, Object?>> _loadBootstrapPayload() async {
    final loader = _bootstrapLoader;
    if (loader != null) return loader();
    final result = await _functions!
        .httpsCallable('bootstrapStoreAccess')
        .call<Map<Object?, Object?>>();
    return result.data;
  }

  void _restoreCachedState(String uid) {
    if (_boundUserId == uid) return;
    _bootstrapEpoch++;
    _selectionRevision++;
    _boundUserId = uid;
    _loading = false;
    _lastError = null;
    try {
      _stores = _storage.readStores(uid);
    } catch (error) {
      debugPrint('Could not restore cached store access: $error');
      _stores = const [];
    }
    _storeAccessResolved = _stores.isNotEmpty;
    _activeStoreId = null;
    _selectAvailableStore(uid);
  }

  void _selectAvailableStore(String uid, {bool preferCurrent = true}) {
    if (_stores.isEmpty) {
      if (_activeStoreId != uid) {
        _activeStoreId = uid;
        _selectionRevision++;
      }
      return;
    }
    final current = _activeStoreId;
    final saved = _readActiveStore(uid);
    final selected = preferCurrent && current != null && _containsStore(current)
        ? current
        : saved != null && _containsStore(saved)
            ? saved
            : current != null && _containsStore(current)
                ? current
                : _stores.first.storeId;
    if (_activeStoreId != selected) _selectionRevision++;
    _activeStoreId = selected;
  }

  bool _containsStore(String id) =>
      _stores.any((membership) => membership.storeId == id);

  String? _readActiveStore(String uid) {
    try {
      return _storage.readActiveStore(uid);
    } catch (error) {
      debugPrint('Could not restore the active store: $error');
      return null;
    }
  }

  Future<void> _persistVerifiedState(
    String uid,
    int requestEpoch,
    int selectionRevision,
    String selectedStoreId,
  ) async {
    final snapshot = List<StoreMembership>.of(_stores);
    try {
      await _storage.writeStores(uid, snapshot);
    } catch (error) {
      debugPrint('Could not cache verified store access: $error');
    }
    if (!_isCurrentRequest(uid, requestEpoch) ||
        _selectionRevision != selectionRevision) {
      return;
    }
    await _queueActiveStoreWrite(uid, selectedStoreId);
  }

  Future<void> _clearVerifiedState(String uid, int requestEpoch) async {
    try {
      await _storage.clearStores(uid);
    } catch (error) {
      debugPrint('Could not clear cached store access: $error');
    }
    if (!_isCurrentRequest(uid, requestEpoch)) return;
    await _queueActiveStoreWrite(uid, uid);
  }

  Future<void> _queueActiveStoreWrite(String uid, String storeId) {
    _activeStoreWrite = _activeStoreWrite.then((_) async {
      await _storage.writeActiveStore(uid, storeId);
    }).catchError((Object error) {
      debugPrint('Could not cache active store: $error');
    });
    return _activeStoreWrite;
  }

  bool _isCurrentRequest(String uid, int requestEpoch) =>
      _bootstrapEpoch == requestEpoch &&
      _boundUserId == uid &&
      _currentUserId == uid;
}
