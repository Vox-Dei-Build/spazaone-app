import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/commerce/commerce_order.dart';
import 'package:pasella/models/sales/order_model.dart';
import 'package:pasella/pages/contact/view_model/customer_management_view_model.dart';
import 'package:pasella/pages/ecommerce/orders_management/data/order_filters.dart';
import 'package:pasella/pages/ecommerce/orders_management/data/orders_controller.dart';
import 'package:pasella/pages/ecommerce/orders_management/data/orders_repository.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_date_header.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_filter_chips.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_row.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_search_field.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_shimmer.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/order_skeleton.dart';
import 'package:pasella/pages/ecommerce/orders_management/widgets/orders_summary_bar.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';
import 'package:pasella/pages/stock/dropship/commerce_orders_page.dart';
import 'package:pasella/services/commerce_service.dart';
import 'package:pasella/shared/widgets/empty_state_onboarding.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

import '../orders/order_detail_page.dart';

/// PAS-UX-14: Customer Orders tab.
///
/// State is owned by a single [OrdersController] provided to this
/// subtree. The previous implementation wired three independent
/// `FutureBuilder`s to the same future which produced out-of-sync
/// skeletons and three rebuilds per filter change. The controller
/// collapses that into one notifier.
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
  late final OrdersController _controller;
  late final StreamSubscription<List<CommerceOrder>> _commerceOrdersSub;
  final _searchCtl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vm =
          Provider.of<CustomerManagementViewModel>(context, listen: false);
      vm.clearOrdersUnread();
    });

    _controller = OrdersController(
      repository: OrdersRepository(
        auth: FirebaseAuth.instance,
        functions: FirebaseFunctions.instance,
      ),
      customerId: widget.customerId,
    );
    _commerceOrdersSub = CommerceService()
        .watchOrders(
      customerId: widget.customerId,
      customerPhone: widget.mobileNumber,
    )
        .listen(
      _controller.setCommerceOrders,
      onError: (Object error, StackTrace stack) {
        debugPrint('Customer supplier orders stream failed: $error');
      },
    );
    // Fire-and-forget initial load. The controller flips `loading` on
    // before the first frame is built so the skeleton renders.
    _controller.load();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _scroll.dispose();
    _commerceOrdersSub.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _controller.range,
      saveText: 'Apply',
    );
    if (picked == null) return;
    _controller.setDateRange(picked);
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return ChangeNotifierProvider<OrdersController>.value(
      value: _controller,
      child: Consumer<OrdersController>(
        builder: (context, ctrl, _) {
          final isFirstLoad = ctrl.loading && ctrl.allOrders.isEmpty;
          return Column(
            children: [
              // Filter chips
              if (isFirstLoad)
                const OrderFilterChipsSkeleton()
              else
                OrderFilterChips(
                  filter: ctrl.filter,
                  counts: ctrl.groupCounts,
                  onSelect: ctrl.setFilter,
                ),

              // Search + actions
              Padding(
                padding: EdgeInsets.fromLTRB(
                  SizeConfig.imageSizeMultiplier * 3,
                  SizeConfig.heightMultiplier * 0.4,
                  SizeConfig.imageSizeMultiplier * 3,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OrderSearchField(
                        controller: _searchCtl,
                        hint: 'Search by order #…',
                        onChanged: ctrl.onSearchChanged,
                      ),
                    ),
                    SizedBox(width: SizeConfig.imageSizeMultiplier * 1),
                    IconButton(
                      tooltip: 'Date range',
                      icon: const Icon(Icons.date_range_outlined),
                      onPressed: _pickDateRange,
                    ),
                    if (ctrl.range != null)
                      IconButton(
                        tooltip: 'Clear dates',
                        icon: const Icon(Icons.clear),
                        onPressed: ctrl.clearDateRange,
                      ),
                  ],
                ),
              ),

              // Summary bar
              if (isFirstLoad)
                const OrdersSummaryBarSkeleton()
              else
                OrdersSummaryBar(
                  count: ctrl.filteredCount,
                  totalText: CurrencyUtil.format(ctrl.filteredTotal),
                  rangeText: _rangeText(ctrl.range),
                ),

              const Divider(height: 1, color: kHighLightColor),

              // List body
              Expanded(
                child: RefreshIndicator(
                  onRefresh: ctrl.refresh,
                  child: _buildBody(context, ctrl),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, OrdersController ctrl) {
    if (ctrl.loading && ctrl.allOrders.isEmpty) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 6,
        itemBuilder: (_, __) => const OrderSkeleton(),
      );
    }
    if (ctrl.error != null && ctrl.allOrders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: SizeConfig.heightMultiplier * 4),
          const EmptyStateOnboarding(
            icon: Icons.cloud_off_outlined,
            headline: "Couldn't load orders",
            subtitle:
                'Check your connection and pull down to refresh, or try again in a moment.',
          ),
        ],
      );
    }

    final groups = ctrl.filteredGrouped;
    if (groups.isEmpty) {
      final hasFilters =
          !ctrl.filter.isAll || ctrl.query.isNotEmpty || ctrl.range != null;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: SizeConfig.heightMultiplier * 4),
          EmptyStateOnboarding(
            icon: hasFilters
                ? Icons.filter_alt_off_outlined
                : Icons.shopping_bag_outlined,
            headline: hasFilters ? 'No matching orders' : 'No orders yet',
            subtitle: hasFilters
                ? 'Try a different status, date range, or clear search.'
                : 'When this customer places an order, it shows up here.',
            ctaLabel: hasFilters ? 'Clear filters' : null,
            ctaIcon: Icons.refresh,
            onCtaTap: hasFilters
                ? () {
                    _searchCtl.clear();
                    ctrl.setFilter(OrdersFilter.all);
                    ctrl.onSearchChanged('');
                    ctrl.clearDateRange();
                  }
                : null,
          ),
        ],
      );
    }

    // Build a flat list of (header, row, row, header, row, …) entries.
    // `ListView.builder` is preferred over `ListView` so off-screen
    // tiles aren't constructed up-front.
    final items = <_ListEntry>[];
    for (final bucket in groups.entries) {
      items.add(_HeaderEntry(bucket.key));
      for (final o in bucket.value) {
        items.add(_RowEntry(o));
      }
    }

    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final entry = items[index];
        if (entry is _HeaderEntry) {
          return OrderDateHeader(date: entry.day);
        }
        if (entry is _RowEntry) {
          final o = entry.order;
          final status = computeStatus(o);
          final timeStr = o.createdAt != null
              ? DateFormat('HH:mm').format(o.createdAt!)
              : '';
          final collected = o.collected;
          final isCommerceOrder = o.source == 'commerce';
          final showCollectedBadge = !isCommerceOrder &&
              status != OrderStatus.collected &&
              status != OrderStatus.uncollected;
          return OrderRow(
            id: o.id,
            status: status,
            totalText: CurrencyUtil.format(o.total),
            itemsCount: o.itemsCount,
            relativeTime: timeStr,
            collectedBadge: isCommerceOrder
                ? const CollectedBadge(
                    text: 'Supplier order',
                    color: Colors.green,
                  )
                : showCollectedBadge
                    ? CollectedBadge(
                        text: collected ? 'Collected' : 'Uncollected',
                        color: collected
                            ? const Color(0xFF1B5E20)
                            : const Color(0xFFE65100),
                      )
                    : null,
            onTap: () async {
              if (isCommerceOrder) {
                final commerceOrder = ctrl.commerceOrderFor(o.id);
                if (commerceOrder != null) {
                  await showCommerceOrderDetails(context, commerceOrder);
                }
                return;
              }
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
              if (updated == true) _controller.refresh();
            },
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  String _rangeText(DateTimeRange? range) {
    if (range == null) return 'All time';
    return '${DateFormat('dd MMM').format(range.start)} – ${DateFormat('dd MMM').format(range.end)}';
  }
}

abstract class _ListEntry {
  const _ListEntry();
}

class _HeaderEntry extends _ListEntry {
  final DateTime day;
  const _HeaderEntry(this.day);
}

class _RowEntry extends _ListEntry {
  final OrderModel order;
  const _RowEntry(this.order);
}
