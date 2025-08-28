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
    _ordersFuture = _fetchOrders();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<List<OrderModel>> _fetchOrders() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');

    final list = await _repo.fetchCustomerOrders(
      merchantId: uid,
      customerId: widget.customerId,
    );

    return applyClientFilters(
      list,
      status: _status,
      query: _query,
      range: _range,
    );
  }

  Future<void> _refresh() async {
    final future = _fetchOrders(); // start async work
    setState(() {
      // update state synchronously
      _ordersFuture = future;
    });
    await future; // let RefreshIndicator wait correctly
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
    setState(() {
      _range = picked;
      _ordersFuture = _fetchOrders();
    });
  }

  void _clearDateRange() {
    setState(() {
      _range = null;
      _ordersFuture = _fetchOrders();
    });
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
                setState(() {
                  _status = s;
                  _ordersFuture = _fetchOrders();
                });
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
                  onChanged: (txt) {
                    _query = txt.trim();
                    _refresh();
                  },
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
