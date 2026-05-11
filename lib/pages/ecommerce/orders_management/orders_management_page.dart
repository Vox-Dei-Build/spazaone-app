import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/sales/order_model.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/ecommerce/orders_management/data/order_filters.dart';
import 'package:pasella/pages/ecommerce/orders_management/data/orders_repository.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_search_field.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_shimmer.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_skeleton.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_status_chips.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_tile.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/orders_summary_bar.dart';
import 'package:pasella/pages/contact/view_model/customer_management_view_model.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

import '../orders/order_detail_page.dart';

// new local imports

class OrdersManagementPage extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String? mobileNumber;

  const OrdersManagementPage({
    super.key,
    required this.customerId,
    required this.customerName,
    this.mobileNumber,
  });

  @override
  State<OrdersManagementPage> createState() => _OrdersManagementPageState();
}

class _OrdersManagementPageState extends State<OrdersManagementPage> {
  late Future<List<OrderModel>> _ordersFuture;
  final _searchCtl = TextEditingController();
  final _scroll = ScrollController();

  String _query = '';
  OrderStatus _status = OrderStatus.all;
  DateTimeRange? _range;

  // PAS-UX-13: in-memory cache of the unfiltered server result.
  //
  // Audit found every keystroke in the search field re-invoked the
  // `getCustomerOrders` cloud function, even though status / range
  // / query filtering all happen client-side via applyClientFilters.
  // We now fetch from the server exactly once per page lifetime
  // (and on explicit refresh), then re-filter the cached list
  // synchronously on every input change.
  List<OrderModel>? _allOrders;

  // PAS-UX-13: 350ms debounce on search input. Even though
  // filtering is now local, debouncing keeps the chip/summary
  // re-render off the keystroke hot path so the keyboard stays
  // responsive on low-end Android.
  Timer? _searchDebounce;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 350);

  // dependencies
  late final OrdersRepository _repo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm =
          Provider.of<CustomerManagementViewModel>(context, listen: false);
      vm.clearOrdersUnread();
    });

    _repo = OrdersRepository(
      auth: FirebaseAuth.instance,
      functions: FirebaseFunctions.instance,
    );
    _ordersFuture = _loadOrders();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Returns a future of the filtered order list.
  ///
  /// When [forceServer] is true (pull-to-refresh), the cached
  /// [_allOrders] is discarded and the cloud function is hit again.
  /// Otherwise the cached list is reused and only the client-side
  /// filters are re-applied.
  Future<List<OrderModel>> _loadOrders({bool forceServer = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');

    if (forceServer || _allOrders == null) {
      _allOrders = await _repo.fetchCustomerOrders(
        merchantId: uid,
        customerId: widget.customerId,
      );
    }

    return applyClientFilters(
      _allOrders!,
      status: _status,
      query: _query,
      range: _range,
    );
  }

  /// Re-applies status/query/range filters against the cached list
  /// without touching the server. Cheap and synchronous in practice
  /// because applyClientFilters is in-memory.
  void _applyFilters() {
    setState(() {
      _ordersFuture = _loadOrders();
    });
  }

  Future<void> _refresh() async {
    final future = _loadOrders(forceServer: true);
    setState(() {
      _ordersFuture = future;
    });
    await future;
  }

  /// Debounced search handler.
  ///
  /// Cancels any in-flight debounce and schedules a new filter pass
  /// 350ms after the most recent keystroke. The trailing edge wins
  /// so a fast typist only causes one re-render.
  void _onSearchChanged(String txt) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDuration, () {
      _query = txt.trim();
      _applyFilters();
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _range,
      saveText: 'Apply',
    );
    if (picked == null) return;
    _range = picked;
    _applyFilters();
  }

  void _clearDateRange() {
    _range = null;
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Column(
      children: [
        // AFTER:
        FutureBuilder<List<OrderModel>>(
          future: _ordersFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !(snap.hasData && (snap.data?.isNotEmpty ?? false))) {
              return const OrderStatusChipsSkeleton();
            }
            return OrderStatusChips(
              selected: _status,
              onSelected: (s) {
                if (_status == s) return;
                _status = s;
                _applyFilters();
              },
            );
          },
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            SizeConfig.imageSizeMultiplier * 3,
            SizeConfig.heightMultiplier * 1.2,
            SizeConfig.imageSizeMultiplier * 3,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: OrderSearchField(
                  controller: _searchCtl,
                  hint: 'Search by order #…',
                  onChanged: _onSearchChanged,
                ),
              ),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: _refresh,
              ),
              IconButton(
                tooltip: 'Date range',
                icon: const Icon(Icons.date_range),
                onPressed: _pickDateRange,
              ),
              if (_range != null)
                IconButton(
                  tooltip: 'Clear dates',
                  icon: const Icon(Icons.clear),
                  onPressed: _clearDateRange,
                ),
            ],
          ),
        ),
        FutureBuilder<List<OrderModel>>(
          future: _ordersFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !(snap.hasData && (snap.data?.isNotEmpty ?? false))) {
              return const OrdersSummaryBarSkeleton();
            }

            final orders = snap.data ?? const <OrderModel>[];
            final total = orders.fold<double>(0.0, (a, b) => a + (b.total));
            final rangeText = _range == null
                ? 'All time'
                : '${DateFormat('dd MMM').format(_range!.start)} – ${DateFormat('dd MMM').format(_range!.end)}';
            return OrdersSummaryBar(
              count: orders.length,
              totalText: CurrencyUtil.format(total),
              rangeText: rangeText,
            );
          },
        ),

        const Divider(height: 1, color: kHighLightColor),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<OrderModel>>(
              future: _ordersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: 6,
                    itemBuilder: (_, __) => const OrderSkeleton(),
                  );
                } else if (snapshot.hasError) {
                  return _buildEmptyState(
                    asset: "assets/images/error.png",
                    text:
                        "Couldn't load orders.\nPull to refresh or try again later.",
                  );
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _buildEmptyState(
                    asset: "assets/images/empty.png",
                    text:
                        "No orders yet.\nTry adjusting filters or date range.",
                  );
                } else {
                  final orders = snapshot.data!;
                  return ListView.separated(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 0),
                    itemBuilder: (context, index) {
                      final o = orders[index];
                      final status = OrderStatusX.fromString(
                        o.status,
                        paymentMethod: o.paymentMethod,
                        type: o.type,
                        paymentStatus: o.paymentStatus,
                      );

                      final isCollected = o.collected;

                      final collectionPill = buildCollectionPill(
                        isCollected: isCollected,
                      );

                      final dateStr = o.createdAt != null
                          ? DateFormat('y MMM d, h:mm a').format(o.createdAt!)
                          : '';

                      return OrderTile(
                        id: o.id,
                        status: status,
                        totalText: CurrencyUtil.format(o.total),
                        itemsCount: o.itemsCount,
                        dateText: dateStr,
                        onTap: () async {
                          final updated = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OrderDetailPage(
                                customerId: widget.customerId,
                                customerName: widget.customerName,
                                orderId: o.id,
                              ),
                            ),
                          );
                          if (updated == true) _refresh();
                        },
                        secondPillText: collectionPill?.text ?? '',
                        secondPillColor: collectionPill?.color,
                      );
                    },
                  );
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({required String asset, required String text}) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              asset,
              width: SizeConfig.imageSizeMultiplier * 30,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: SizeConfig.textMultiplier * 2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
