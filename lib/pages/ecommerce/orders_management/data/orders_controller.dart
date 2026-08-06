// PAS-UX-14: single source of truth for the Customer Orders tab.
//
// The previous page wired three `FutureBuilder<List<OrderModel>>`s to
// the same future (chips row, summary bar, list body). Each rebuilt
// independently, and Flutter's microtask ordering meant the three
// skeletons could land out of step — e.g. chips loaded while the list
// was still showing six grey placeholders, then the summary popped a
// frame later. Worse, every `setState(_ordersFuture = …)` triggered
// three independent rebuilds even though all three rebuild from the
// same data.
//
// The redesign collapses that into one `ChangeNotifier` that owns
// `loading / error / orders` plus the filter inputs. Each sub-widget
// becomes a thin `Consumer` (or `Selector`) reading exactly the slice
// it needs:
//
//   * Chip row    → reads `filteredCounts` + `filter`.
//   * Summary bar → reads `filtered` + `rangeText`.
//   * List body   → reads `loading / error / filteredGrouped`.
//
// Caching strategy is preserved: the cloud function is hit once per
// page lifetime (or on explicit refresh), then client filters are
// applied synchronously on every input change.
//
// Why not Riverpod / Bloc?
//   The rest of the app uses `provider` + `ChangeNotifier` for view
//   models (see `CustomerManagementViewModel`,
//   `CustomerBalanceSummaryProvider`). Staying with the same primitive
//   keeps the page consistent with its neighbours.

import 'dart:async';

import 'package:pasella/services/store_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pasella/models/commerce/commerce_order.dart';
import 'package:pasella/models/sales/order_model.dart';
import 'package:pasella/pages/ecommerce/orders_management/data/order_filters.dart';
import 'package:pasella/pages/ecommerce/orders_management/data/orders_repository.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';

/// Pre-bucketed orders keyed by a normalised date (midnight in local
/// time). Insertion order is preserved (newest first) because we
/// construct it from a list already sorted by `createdAt desc`.
typedef OrdersByDate = LinkedHashMapEntries;

enum OrdersTruthSurface { loading, error, empty, content }

class CommerceOrdersCacheUnverified implements Exception {
  const CommerceOrdersCacheUnverified();
}

@visibleForTesting
Object? commerceOrdersSnapshotError({required bool isFromCache}) =>
    isFromCache ? const CommerceOrdersCacheUnverified() : null;

@visibleForTesting
OrdersTruthSurface resolveOrdersTruthSurface({
  required bool legacyLoading,
  required bool commerceLoading,
  required Object? legacyError,
  required Object? commerceError,
  required bool hasOrders,
}) {
  if (hasOrders) return OrdersTruthSurface.content;
  if (legacyError != null || commerceError != null) {
    return OrdersTruthSurface.error;
  }
  if (legacyLoading || commerceLoading) return OrdersTruthSurface.loading;
  return OrdersTruthSurface.empty;
}

@visibleForTesting
OrderModel commerceOrderListModel(CommerceOrder order) => OrderModel(
      id: order.id,
      status: order.status,
      total: order.amountDueMinor / 100,
      itemsCount: 1,
      createdAt: order.createdAt,
      type: 'Dropship',
      paymentMethod: order.paymentMethod,
      paymentStatus: order.paymentStatus,
      collected: order.status == 'delivered',
      source: 'commerce',
    );

class LinkedHashMapEntries {
  final List<MapEntry<DateTime, List<OrderModel>>> entries;
  const LinkedHashMapEntries(this.entries);
  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;
}

class OrdersController extends ChangeNotifier {
  OrdersController({
    required OrdersRepository repository,
    required String customerId,
    Duration searchDebounce = const Duration(milliseconds: 350),
  })  : _repo = repository,
        _customerId = customerId,
        _searchDebounceDuration = searchDebounce;

  final OrdersRepository _repo;
  final String _customerId;
  final Duration _searchDebounceDuration;

  // ---- inputs --------------------------------------------------------

  OrdersFilter _filter = OrdersFilter.all;
  OrdersFilter get filter => _filter;

  String _query = '';
  String get query => _query;

  DateTimeRange? _range;
  DateTimeRange? get range => _range;

  // ---- state ---------------------------------------------------------

  bool _loading = false;
  bool get loading => _loading;

  Object? _error;
  Object? get error => _error;

  bool _commerceLoading = true;
  bool get commerceLoading => _commerceLoading;

  Object? _commerceError;
  Object? get commerceError => _commerceError;

  bool get hasAnyError => _error != null || _commerceError != null;

  OrdersTruthSurface get truthSurface => resolveOrdersTruthSurface(
        legacyLoading: _loading,
        commerceLoading: _commerceLoading,
        legacyError: _error,
        commerceError: _commerceError,
        hasOrders: allOrders.isNotEmpty,
      );

  /// Unfiltered server result. We hold onto it so client-side filter
  /// changes don't require another round-trip.
  List<OrderModel> _legacyOrders = const [];
  List<OrderModel> _commerceOrderModels = const [];
  Map<String, CommerceOrder> _commerceOrdersById = const {};

  List<OrderModel> get allOrders => [
        ..._legacyOrders,
        ..._commerceOrderModels,
      ];

  CommerceOrder? commerceOrderFor(String orderId) =>
      _commerceOrdersById[orderId];

  void setCommerceOrders(
    List<CommerceOrder> orders, {
    bool isFromCache = false,
  }) {
    if (_disposed) return;
    _commerceLoading = false;
    _commerceError = commerceOrdersSnapshotError(isFromCache: isFromCache);
    _commerceOrdersById = {for (final order in orders) order.id: order};
    _commerceOrderModels =
        orders.map(commerceOrderListModel).toList(growable: false);
    notifyListeners();
  }

  void beginCommerceLoad() {
    if (_disposed) return;
    _commerceLoading = true;
    _commerceError = null;
    notifyListeners();
  }

  void completeCommerceLoad() {
    if (_disposed || !_commerceLoading) return;
    _commerceLoading = false;
    notifyListeners();
  }

  void setCommerceError(Object error) {
    if (_disposed) return;
    _commerceLoading = false;
    _commerceError = error;
    notifyListeners();
  }

  bool _disposed = false;
  Timer? _searchDebounce;

  // ---- derived (memoised on demand) ----------------------------------

  /// Filtered orders sorted by `createdAt` descending. Orders missing
  /// a date sink to the bottom in stable order.
  List<OrderModel> get filtered {
    final list = applyClientFilters(
      allOrders,
      filter: _filter,
      query: _query,
      range: _range,
    );
    list.sort((a, b) {
      final ad = a.createdAt;
      final bd = b.createdAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return list;
  }

  /// Same as [filtered] but bucketed by local calendar day. Used by
  /// the list body to render sticky "Today / Yesterday / Mon / 12 Mar"
  /// date headers above each cluster.
  LinkedHashMapEntries get filteredGrouped {
    final list = filtered;
    final buckets = <DateTime, List<OrderModel>>{};
    final order = <DateTime>[];
    for (final o in list) {
      final raw = o.createdAt;
      // Orders with no date land in a synthetic "Unknown" bucket at
      // the epoch — they sort last and the header renders as "Unknown".
      final key = raw == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime(raw.year, raw.month, raw.day);
      final existing = buckets[key];
      if (existing == null) {
        buckets[key] = [o];
        order.add(key);
      } else {
        existing.add(o);
      }
    }
    return LinkedHashMapEntries(
      order.map((k) => MapEntry(k, buckets[k]!)).toList(growable: false),
    );
  }

  /// Map of filter → match-count, computed once per cached order list.
  /// The chip row uses this to render small count badges next to each
  /// chip without re-walking the orders list per chip.
  Map<OrderFilterGroup, int> get groupCounts {
    final counts = <OrderFilterGroup, int>{
      OrderFilterGroup.all: 0,
      OrderFilterGroup.pending: 0,
      OrderFilterGroup.bnpl: 0,
      OrderFilterGroup.delivery: 0,
    };
    for (final o in allOrders) {
      counts[OrderFilterGroup.all] = counts[OrderFilterGroup.all]! + 1;
      final s = computeStatus(o);
      if (s == OrderStatus.pending) {
        counts[OrderFilterGroup.pending] =
            counts[OrderFilterGroup.pending]! + 1;
      }
      if (s == OrderStatus.bnplPending ||
          s == OrderStatus.bnplOutstanding ||
          s == OrderStatus.bnplRejected) {
        counts[OrderFilterGroup.bnpl] = counts[OrderFilterGroup.bnpl]! + 1;
      }
      if (s == OrderStatus.outForDelivery || s == OrderStatus.delivered) {
        counts[OrderFilterGroup.delivery] =
            counts[OrderFilterGroup.delivery]! + 1;
      }
    }
    return counts;
  }

  /// Sum of `total` over the currently-filtered list.
  double get filteredTotal => filtered.fold<double>(0.0, (a, b) => a + b.total);

  /// Count of the currently-filtered list — exposed separately so
  /// `Selector` consumers can rebuild on count without also rebuilding
  /// on every item shuffle.
  int get filteredCount => filtered.length;

  // ---- commands ------------------------------------------------------

  Future<void> load({bool forceServer = false}) async {
    if (_disposed) return;
    if (forceServer || _legacyOrders.isEmpty) {
      _loading = true;
      _error = null;
      notifyListeners();
      try {
        final uid = StoreSession.instance.storeId;
        if (uid.isEmpty) throw Exception('Not signed in');
        final fetched = await _repo.fetchCustomerOrders(
          merchantId: uid,
          customerId: _customerId,
        );
        if (_disposed) return;
        _legacyOrders = fetched;
        _error = null;
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('OrdersController.load failed: $e\n$st');
        }
        _error = e;
      } finally {
        _loading = false;
        if (!_disposed) notifyListeners();
      }
    } else {
      // Cache hit — nothing to do, derived getters re-filter on read.
      notifyListeners();
    }
  }

  Future<void> refresh() => load(forceServer: true);

  void setFilter(OrdersFilter f) {
    if (identical(f, _filter)) return;
    if (f.group != null && _filter.group != null && f.group == _filter.group) {
      return;
    }
    if (f.specific != null && _filter.specific == f.specific) return;
    _filter = f;
    notifyListeners();
  }

  /// Debounced search. The trailing edge wins so a fast typist only
  /// causes one rebuild.
  void onSearchChanged(String txt) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDuration, () {
      if (_disposed) return;
      final next = txt.trim();
      if (next == _query) return;
      _query = next;
      notifyListeners();
    });
  }

  void setDateRange(DateTimeRange? r) {
    _range = r;
    notifyListeners();
  }

  void clearDateRange() {
    if (_range == null) return;
    _range = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDebounce?.cancel();
    super.dispose();
  }
}
