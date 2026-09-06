import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/models/stock/whatsapp_catalog_status.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/utils/feature_flags.dart';

typedef WhatsAppCatalogPageLoader = Future<Map<String, dynamic>> Function({
  required String storeId,
  required int pageSize,
  String? pageToken,
});

class WhatsAppCatalogChangedException implements Exception {
  const WhatsAppCatalogChangedException();
}

class WhatsAppCatalogStatusService {
  WhatsAppCatalogStatusService({
    WhatsAppCatalogPageLoader? pageLoader,
    Box<dynamic>? cache,
    String Function()? userIdProvider,
  })  : _pageLoader = pageLoader ?? _loadPage,
        _cacheOverride = cache,
        _userIdProvider = userIdProvider ??
            (() => FirebaseAuth.instance.currentUser?.uid ?? '');

  static const freshFor = Duration(minutes: 5);
  static const retainFor = Duration(hours: 24);
  static const _cachePrefix = 'whatsapp_catalog_status_v2::';

  final WhatsAppCatalogPageLoader _pageLoader;
  final Box<dynamic>? _cacheOverride;
  final String Function() _userIdProvider;

  Box<dynamic>? get _cache {
    if (_cacheOverride != null) return _cacheOverride;
    return Hive.isBoxOpen('appBox') ? Hive.box('appBox') : null;
  }

  Future<WhatsAppCatalogSnapshot> fetch(String storeId) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _fetchPages(storeId);
      } on WhatsAppCatalogChangedException {
        if (attempt == 1) rethrow;
      }
    }
    throw const WhatsAppCatalogChangedException();
  }

  Future<WhatsAppCatalogSnapshot> _fetchPages(String storeId) async {
    String? token;
    String? catalogVersion;
    Map<String, dynamic>? firstPage;
    final products = <dynamic>[];
    final seenTokens = <String>{};
    do {
      late final Map<String, dynamic> page;
      try {
        page = await _pageLoader(
          storeId: storeId,
          pageSize: 100,
          pageToken: token,
        ).timeout(const Duration(seconds: 12));
      } on FirebaseFunctionsException catch (error) {
        final details = error.details;
        if (error.code == 'failed-precondition' &&
            details is Map &&
            details['reason'] == 'CATALOG_CHANGED') {
          throw const WhatsAppCatalogChangedException();
        }
        rethrow;
      }
      if (page['schemaVersion'] != 2) {
        throw const FormatException('Unsupported catalogue status response.');
      }
      firstPage ??= page;
      final pageVersion = page['catalogVersion']?.toString() ?? '';
      catalogVersion ??= pageVersion;
      if (pageVersion.isEmpty || pageVersion != catalogVersion) {
        throw const WhatsAppCatalogChangedException();
      }
      products.addAll(page['products'] as List? ?? const []);
      token = page['nextPageToken']?.toString();
      if (token?.isEmpty == true) token = null;
      if (token != null && !seenTokens.add(token)) {
        throw const FormatException('Catalogue pagination repeated a page.');
      }
      if (seenTokens.length > 1000) {
        throw const FormatException('Catalogue pagination exceeded its limit.');
      }
    } while (token != null);

    final complete = <String, dynamic>{
      ...firstPage,
      'products': products,
      'nextPageToken': null,
    };
    final snapshot = WhatsAppCatalogSnapshot.fromMap(complete);
    await writeCache(storeId, snapshot);
    return snapshot;
  }

  Future<WhatsAppCatalogSnapshot?> readCache(
    String storeId, {
    DateTime? now,
  }) async {
    final cache = _cache;
    final userId = _userIdProvider().trim();
    if (cache == null || userId.isEmpty || storeId.isEmpty) return null;
    final value = cache.get(_cacheKey(userId, storeId));
    if (value is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(value);
      final cachedAtMs = int.tryParse('${map.remove('cachedAtMs')}') ?? 0;
      final age = (now ?? DateTime.now()).difference(
        DateTime.fromMillisecondsSinceEpoch(cachedAtMs),
      );
      if (cachedAtMs <= 0 || age > retainFor || age.isNegative) {
        await cache.delete(_cacheKey(userId, storeId));
        return null;
      }
      return WhatsAppCatalogSnapshot.fromMap(map, fromCache: true);
    } catch (_) {
      await cache.delete(_cacheKey(userId, storeId));
      return null;
    }
  }

  Future<void> writeCache(
    String storeId,
    WhatsAppCatalogSnapshot snapshot,
  ) async {
    final cache = _cache;
    final userId = _userIdProvider().trim();
    if (cache == null || userId.isEmpty || storeId.isEmpty) return;
    await cache.put(
      _cacheKey(userId, storeId),
      {
        ...snapshot.toMap(),
        'cachedAtMs': DateTime.now().millisecondsSinceEpoch
      },
    );
  }

  static Future<void> clearAllCachedStatus() async {
    if (!Hive.isBoxOpen('appBox')) return;
    final cache = Hive.box('appBox');
    final keys = cache.keys
        .where((key) => key.toString().startsWith(_cachePrefix))
        .toList();
    await cache.deleteAll(keys);
  }

  static String _cacheKey(String userId, String storeId) =>
      '$_cachePrefix$userId::$storeId';

  static Future<Map<String, dynamic>> _loadPage({
    required String storeId,
    required int pageSize,
    String? pageToken,
  }) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'getWhatsAppCatalogSyncStatusV2',
    );
    final result = await callable.call(<String, dynamic>{
      'storeId': storeId,
      'pageSize': pageSize,
      if (pageToken != null) 'pageToken': pageToken,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }
}

class WhatsAppCatalogStatusController extends ChangeNotifier
    with WidgetsBindingObserver {
  WhatsAppCatalogStatusController({
    WhatsAppCatalogStatusService? service,
    StoreSession? storeSession,
    bool Function()? enabled,
    DateTime Function()? now,
  })  : _service = service ?? WhatsAppCatalogStatusService(),
        _storeSession = storeSession ?? StoreSession.instance,
        _enabled = enabled ?? (() => FeatureFlags.enableWhatsAppCatalogStatus),
        _now = now ?? DateTime.now;

  final WhatsAppCatalogStatusService _service;
  final StoreSession _storeSession;
  final bool Function() _enabled;
  final DateTime Function() _now;
  WhatsAppCatalogSnapshot? snapshot;
  bool loading = false;
  String? errorMessage;
  int _epoch = 0;
  String _storeId = '';
  DateTime? _lastManualRefresh;
  Timer? _pollTimer;
  Duration _pollElapsed = Duration.zero;
  int _pollIndex = 0;
  bool _started = false;
  bool _disposed = false;
  bool _isForeground = true;

  bool get enabled => _enabled();
  bool get isStale => snapshot?.isStaleAt(_now()) ?? false;
  bool get canManualRefresh =>
      _lastManualRefresh == null ||
      _now().difference(_lastManualRefresh!) >= const Duration(seconds: 15);

  WhatsAppCatalogProductState? statusFor(String? productId) =>
      productId == null ? null : snapshot?.productsById[productId];

  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _storeSession.addListener(_handleStoreChanged);
    FeatureFlags.whatsAppCatalogStatusEnabled.addListener(_handleFlagChanged);
    _handleStoreChanged();
  }

  void _handleFlagChanged() {
    if (!enabled) {
      _epoch += 1;
      _pollTimer?.cancel();
      snapshot = null;
      loading = false;
      errorMessage = null;
      notifyListeners();
      return;
    }
    unawaited(refresh());
  }

  void _handleStoreChanged() {
    final nextStoreId = _storeSession.storeId.trim();
    if (nextStoreId == _storeId) return;
    _storeId = nextStoreId;
    _epoch += 1;
    _pollTimer?.cancel();
    _pollElapsed = Duration.zero;
    _pollIndex = 0;
    snapshot = null;
    errorMessage = null;
    notifyListeners();
    if (_storeId.isNotEmpty && enabled) unawaited(_loadForStore(_storeId));
  }

  Future<void> refresh({bool resetPolling = false}) async {
    if (_disposed || _storeId.isEmpty || !enabled) return;
    if (resetPolling) {
      _pollElapsed = Duration.zero;
      _pollIndex = 0;
    }
    await _loadForStore(_storeId, readCache: false);
  }

  Future<void> manualRefresh() async {
    if (!canManualRefresh) return;
    _lastManualRefresh = _now();
    await refresh(resetPolling: true);
  }

  Future<void> _loadForStore(
    String storeId, {
    bool readCache = true,
  }) async {
    final requestEpoch = ++_epoch;
    loading = snapshot == null;
    errorMessage = null;
    notifyListeners();
    if (readCache) {
      final cached = await _service.readCache(storeId, now: _now());
      if (!_isCurrent(requestEpoch, storeId)) return;
      if (cached != null) {
        snapshot = cached;
        loading = false;
        notifyListeners();
        unawaited(_captureLoaded(cached, Duration.zero));
      }
    }
    final stopwatch = Stopwatch()..start();
    try {
      final fresh = await _service.fetch(storeId);
      stopwatch.stop();
      if (!_isCurrent(requestEpoch, storeId)) return;
      snapshot = fresh;
      loading = false;
      errorMessage = null;
      notifyListeners();
      unawaited(_captureLoaded(fresh, stopwatch.elapsed));
      _schedulePolling();
    } catch (error) {
      stopwatch.stop();
      if (!_isCurrent(requestEpoch, storeId)) return;
      loading = false;
      errorMessage = snapshot == null
          ? 'Catalogue status is unavailable. Pull to refresh and try again.'
          : 'Showing the last checked catalogue status.';
      notifyListeners();
      unawaited(
        TelemetryService.instance.capture(
          WhatsAppCatalogStatusLoadFailed(
            failure: _failureCategory(error),
            latencyBucket: stopwatch.elapsedMilliseconds < 500
                ? 'under_500ms'
                : stopwatch.elapsedMilliseconds < 2000
                    ? '500ms_2s'
                    : 'over_2s',
            cacheAvailable: snapshot != null,
          ),
        ),
      );
    }
  }

  bool _isCurrent(int requestEpoch, String storeId) =>
      !_disposed && requestEpoch == _epoch && storeId == _storeId;

  void _schedulePolling() {
    _pollTimer?.cancel();
    if (!_isForeground ||
        snapshot?.hasPendingWork != true ||
        _pollElapsed >= const Duration(minutes: 2)) {
      return;
    }
    const intervals = [
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 30),
    ];
    final requestedDelay = intervals[_pollIndex.clamp(0, intervals.length - 1)];
    final remaining = const Duration(minutes: 2) - _pollElapsed;
    final delay = requestedDelay <= remaining ? requestedDelay : remaining;
    _pollIndex += 1;
    _pollElapsed += delay;
    _pollTimer = Timer(delay, () => unawaited(refresh()));
  }

  Future<void> _captureLoaded(
    WhatsAppCatalogSnapshot value,
    Duration latency,
  ) {
    return TelemetryService.instance.capture(
      WhatsAppCatalogStatusLoaded(
        rollout: value.rollout == WhatsAppCatalogRollout.enabled
            ? 'enabled'
            : 'not_enabled',
        liveBucket: _countBucket(value.summary.live),
        needsAttentionBucket: _countBucket(value.summary.needsAttention),
        source: value.fromCache ? 'cache' : 'network',
        latencyBucket: latency.inMilliseconds < 500
            ? 'under_500ms'
            : latency.inMilliseconds < 2000
                ? '500ms_2s'
                : 'over_2s',
        cacheAgeBucket: value.fromCache
            ? _cacheAgeBucket(_now().millisecondsSinceEpoch - value.checkedAtMs)
            : 'fresh',
      ),
    );
  }

  static String _countBucket(int count) => count < 5
      ? '0_4'
      : count < 10
          ? '5_9'
          : '10_plus';

  static String _cacheAgeBucket(int ageMs) {
    if (ageMs <= WhatsAppCatalogStatusService.freshFor.inMilliseconds) {
      return 'under_5m';
    }
    return ageMs <= const Duration(hours: 1).inMilliseconds
        ? '5m_1h'
        : '1h_24h';
  }

  static String _failureCategory(Object error) {
    if (error is TimeoutException) return 'timeout';
    if (error is WhatsAppCatalogChangedException) return 'catalog_changed';
    if (error is FormatException) return 'invalid_response';
    if (error is FirebaseFunctionsException) {
      return switch (error.code) {
        'permission-denied' || 'unauthenticated' => 'denied',
        'unavailable' || 'deadline-exceeded' => 'offline',
        _ => 'unavailable',
      };
    }
    return 'unavailable';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) {
      unawaited(refresh(resetPolling: true));
    } else {
      _pollTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch += 1;
    _pollTimer?.cancel();
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _storeSession.removeListener(_handleStoreChanged);
      FeatureFlags.whatsAppCatalogStatusEnabled
          .removeListener(_handleFlagChanged);
    }
    super.dispose();
  }
}
