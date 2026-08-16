import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/models/commerce/commerce_order.dart';
import 'package:pasella/models/orders/canonical_order_status.dart';
import 'package:pasella/pages/sales/widgets/online_sale_detail_page.dart';
import 'package:pasella/pages/sales/widgets/online_sales_list.dart';
import 'package:pasella/pages/stock/dropship/commerce_orders_page.dart';
import 'package:pasella/services/commerce_service.dart';
import 'package:pasella/shared/widgets/workspace_context_header.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:shimmer/shimmer.dart';

enum OnlineOrderSourceFilter { all, owned, supplier }

enum OnlineOrderProgressFilter {
  all,
  awaitingPayment,
  inProgress,
  completed,
  needsAttention,
  refunded,
}

typedef OwnedOnlineOrdersLoader = Future<List<LedgerSale>> Function({
  DateTime? selectedDay,
  DateTime? startDate,
  DateTime? endDate,
});

typedef SupplierOnlineOrdersStream = Stream<List<CommerceOrder>> Function();

Stream<List<CommerceOrder>> watchSupplierOnlineOrders() =>
    CommerceService().watchOrders();

class CombinedOnlineOrders extends StatefulWidget {
  const CombinedOnlineOrders({
    super.key,
    required this.selectedDay,
    required this.startDate,
    required this.endDate,
    required this.onDaySelect,
    required this.onRangeSelect,
    required this.onClearDates,
    required this.onSetup,
    required this.onShareShop,
    this.onOrderOptions,
    this.setupRequired = false,
    this.canShareShop = true,
    this.readinessUnavailable = false,
    this.onRetryReadiness,
    this.ownedLoader = fetchOnlineLedgerSales,
    this.supplierStream = watchSupplierOnlineOrders,
  });

  final DateTime? selectedDay;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<DateTime> onDaySelect;
  final void Function(DateTime start, DateTime end) onRangeSelect;
  final VoidCallback onClearDates;
  final VoidCallback onSetup;
  final VoidCallback onShareShop;
  final VoidCallback? onOrderOptions;
  final bool setupRequired;
  final bool canShareShop;
  final bool readinessUnavailable;
  final VoidCallback? onRetryReadiness;
  final OwnedOnlineOrdersLoader ownedLoader;
  final SupplierOnlineOrdersStream supplierStream;

  @override
  State<CombinedOnlineOrders> createState() => _CombinedOnlineOrdersState();
}

class _CombinedOnlineOrdersState extends State<CombinedOnlineOrders> {
  late Future<List<LedgerSale>> _ownedOrders;
  late Stream<List<CommerceOrder>> _supplierOrders;
  OnlineOrderSourceFilter _source = OnlineOrderSourceFilter.all;
  OnlineOrderProgressFilter _progress = OnlineOrderProgressFilter.all;

  @override
  void initState() {
    super.initState();
    _reloadOwned();
    _supplierOrders = widget.supplierStream();
  }

  @override
  void didUpdateWidget(covariant CombinedOnlineOrders oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDay != widget.selectedDay ||
        oldWidget.startDate != widget.startDate ||
        oldWidget.endDate != widget.endDate) {
      _reloadOwned();
    }
  }

  void _reloadOwned() {
    _ownedOrders = widget.ownedLoader(
      selectedDay: widget.selectedDay,
      startDate: widget.startDate,
      endDate: widget.endDate,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _reloadOwned();
      _supplierOrders = widget.supplierStream();
    });
    await _ownedOrders;
  }

  bool _sameDate(DateTime? left, DateTime? right) {
    if (left == null || right == null) return left == right;
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  bool _supplierMatchesDate(CommerceOrder order) {
    final createdAt = order.createdAt;
    if (createdAt == null) {
      return widget.selectedDay == null && widget.startDate == null;
    }
    if (widget.selectedDay != null) {
      return _sameDate(createdAt, widget.selectedDay);
    }
    if (widget.startDate != null && widget.endDate != null) {
      final start = DateTime(
        widget.startDate!.year,
        widget.startDate!.month,
        widget.startDate!.day,
      );
      final end = DateTime(
        widget.endDate!.year,
        widget.endDate!.month,
        widget.endDate!.day + 1,
      );
      return !createdAt.isBefore(start) && createdAt.isBefore(end);
    }
    return true;
  }

  List<_OnlineOrderSummary> _combine(
    List<LedgerSale> owned,
    List<CommerceOrder> supplier,
  ) {
    final combined = <_OnlineOrderSummary>[
      ...owned.map(_OnlineOrderSummary.owned),
      ...supplier.where(_supplierMatchesDate).map(_OnlineOrderSummary.supplier),
    ];
    combined.sort((left, right) {
      final leftMs = left.createdAt?.millisecondsSinceEpoch ?? 0;
      final rightMs = right.createdAt?.millisecondsSinceEpoch ?? 0;
      return rightMs.compareTo(leftMs);
    });
    return combined.where((order) {
      if (_source == OnlineOrderSourceFilter.owned && !order.isOwned) {
        return false;
      }
      if (_source == OnlineOrderSourceFilter.supplier && order.isOwned) {
        return false;
      }
      return _progress == OnlineOrderProgressFilter.all ||
          order.progress == _progress;
    }).toList(growable: false);
  }

  int get _secondaryFilterCount {
    var count = 0;
    if (_source != OnlineOrderSourceFilter.all) count++;
    if (widget.selectedDay != null || widget.startDate != null) count++;
    return count;
  }

  String get _dateLabel {
    final format = DateFormat('dd MMM');
    if (widget.selectedDay != null) return format.format(widget.selectedDay!);
    if (widget.startDate != null && widget.endDate != null) {
      return '${format.format(widget.startDate!)}–${format.format(widget.endDate!)}';
    }
    return 'All time';
  }

  Future<void> _showFilters() async {
    var source = _source;
    var dateMode = widget.selectedDay != null
        ? _DateMode.today
        : widget.startDate != null
            ? _DateMode.range
            : _DateMode.all;
    DateTimeRange? range = widget.startDate != null && widget.endDate != null
        ? DateTimeRange(start: widget.startDate!, end: widget.endDate!)
        : null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'More order filters',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 20),
                const Text('Order source',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: OnlineOrderSourceFilter.values
                      .map(
                        (value) => ChoiceChip(
                          label: Text(_sourceLabel(value)),
                          selected: source == value,
                          onSelected: (_) =>
                              setSheetState(() => source = value),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 20),
                const Text('Date',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All time'),
                      selected: dateMode == _DateMode.all,
                      onSelected: (_) =>
                          setSheetState(() => dateMode = _DateMode.all),
                    ),
                    ChoiceChip(
                      label: const Text('Today'),
                      selected: dateMode == _DateMode.today,
                      onSelected: (_) =>
                          setSheetState(() => dateMode = _DateMode.today),
                    ),
                    ChoiceChip(
                      label: Text(range == null
                          ? 'Choose dates'
                          : '${DateFormat('dd MMM').format(range!.start)}–${DateFormat('dd MMM').format(range!.end)}'),
                      selected: dateMode == _DateMode.range,
                      onSelected: (_) async {
                        final picked = await showDateRangePicker(
                          context: sheetContext,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: range,
                        );
                        if (picked != null) {
                          setSheetState(() {
                            range = picked;
                            dateMode = _DateMode.range;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _source = source;
                    });
                    switch (dateMode) {
                      case _DateMode.all:
                        widget.onClearDates();
                      case _DateMode.today:
                        widget.onDaySelect(DateTime.now());
                      case _DateMode.range:
                        final selectedRange = range;
                        if (selectedRange != null) {
                          widget.onRangeSelect(
                            selectedRange.start,
                            selectedRange.end,
                          );
                        }
                    }
                    Navigator.pop(sheetContext);
                  },
                  child: const Text('Show orders'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CommerceOrder>>(
      stream: _supplierOrders,
      builder: (context, supplierSnapshot) {
        return FutureBuilder<List<LedgerSale>>(
          future: _ownedOrders,
          builder: (context, ownedSnapshot) {
            final owned = ownedSnapshot.data ?? const <LedgerSale>[];
            final supplier = supplierSnapshot.data ?? const <CommerceOrder>[];
            final isInitialLoading =
                (ownedSnapshot.connectionState == ConnectionState.waiting ||
                        supplierSnapshot.connectionState ==
                            ConnectionState.waiting) &&
                    owned.isEmpty &&
                    supplier.isEmpty;
            final orders = _combine(owned, supplier);
            final partialError = ownedSnapshot.hasError ||
                supplierSnapshot.hasError ||
                widget.readinessUnavailable;

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                key: const ValueKey('combined-online-orders-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                children: [
                  _OrdersHeader(
                    progress: _progress,
                    onProgress: (value) => setState(() => _progress = value),
                    filterCount: _secondaryFilterCount,
                    onFilter: _showFilters,
                    onOrderOptions: widget.onOrderOptions,
                  ),
                  if (widget.setupRequired && orders.isNotEmpty)
                    _SetupNotice(onPressed: widget.onSetup),
                  if (partialError)
                    _PartialErrorNotice(
                      onRetry: () {
                        setState(_reloadOwned);
                        widget.onRetryReadiness?.call();
                      },
                    ),
                  if (_secondaryFilterCount > 0)
                    _ActiveFilters(
                      source: _source,
                      dateLabel: _dateLabel,
                      hasDate: widget.selectedDay != null ||
                          widget.startDate != null,
                      onClear: () {
                        setState(() {
                          _source = OnlineOrderSourceFilter.all;
                        });
                        widget.onClearDates();
                      },
                    ),
                  if (isInitialLoading)
                    const _OnlineOrdersLoading()
                  else if (orders.isEmpty)
                    _OrdersEmpty(
                      setupRequired: widget.setupRequired,
                      onPressed: widget.setupRequired
                          ? widget.onSetup
                          : widget.canShareShop
                              ? widget.onShareShop
                              : null,
                    )
                  else
                    ...orders.map(
                      (order) => _OrderRow(
                        order: order,
                        onTap: () {
                          if (order.owned != null) {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => OnlineSaleDetailPage(
                                  orderId: order.owned!.id,
                                ),
                              ),
                            );
                          } else if (order.supplierOrder != null) {
                            showCommerceOrderDetails(
                              context,
                              order.supplierOrder!,
                            );
                          }
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

enum _DateMode { all, today, range }

class _OnlineOrderSummary {
  const _OnlineOrderSummary({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amountMinor,
    required this.statusLabel,
    required this.progress,
    required this.createdAt,
    this.owned,
    this.supplierOrder,
  });

  factory _OnlineOrderSummary.owned(LedgerSale sale) {
    final status = sale.status.toLowerCase();
    return _OnlineOrderSummary(
      id: sale.reference.isEmpty ? sale.id : sale.reference,
      title: sale.itemsCount == 1 ? '1 item' : '${sale.itemsCount} items',
      subtitle: 'Your stock',
      amountMinor:
          ((sale.amountPaid > 0 ? sale.amountPaid : sale.orderTotal) * 100)
              .round(),
      statusLabel: _ownedStatusLabel(status),
      progress: switch (status) {
        'pending' ||
        'pending_payment' ||
        'awaiting_payment' =>
          OnlineOrderProgressFilter.awaitingPayment,
        'collected' || 'delivered' => OnlineOrderProgressFilter.completed,
        'failed' ||
        'cancelled' ||
        'needs_review' ||
        'refund_pending' =>
          OnlineOrderProgressFilter.needsAttention,
        'refunded' => OnlineOrderProgressFilter.refunded,
        _ => OnlineOrderProgressFilter.inProgress,
      },
      createdAt: sale.createdAt ?? sale.ledgerCreatedAt,
      owned: sale,
    );
  }

  factory _OnlineOrderSummary.supplier(CommerceOrder order) {
    final canonical = order.canonicalStatus;
    return _OnlineOrderSummary(
      id: order.id,
      title: order.productTitle,
      subtitle: 'Supplier product · ${order.buyerName}',
      amountMinor: order.amountDueMinor,
      statusLabel: canonical.label,
      progress: switch (canonical) {
        CanonicalOrderStatus.awaitingPayment =>
          OnlineOrderProgressFilter.awaitingPayment,
        CanonicalOrderStatus.delivered => OnlineOrderProgressFilter.completed,
        CanonicalOrderStatus.cancelled =>
          OnlineOrderProgressFilter.needsAttention,
        CanonicalOrderStatus.refunded => OnlineOrderProgressFilter.refunded,
        _ => OnlineOrderProgressFilter.inProgress,
      },
      createdAt: order.createdAt,
      supplierOrder: order,
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final int amountMinor;
  final String statusLabel;
  final OnlineOrderProgressFilter progress;
  final DateTime? createdAt;
  final LedgerSale? owned;
  final CommerceOrder? supplierOrder;

  bool get isOwned => owned != null;
}

class _OrdersHeader extends StatelessWidget {
  const _OrdersHeader({
    required this.progress,
    required this.onProgress,
    required this.filterCount,
    required this.onFilter,
    this.onOrderOptions,
  });

  final OnlineOrderProgressFilter progress;
  final ValueChanged<OnlineOrderProgressFilter> onProgress;
  final int filterCount;
  final VoidCallback onFilter;
  final VoidCallback? onOrderOptions;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceContextHeader(
            title: 'Online orders',
            subtitle: 'Your stock and supplier-delivered orders',
            action: onOrderOptions == null
                ? null
                : IconButton.outlined(
                    key: const ValueKey('online-orders-order-options'),
                    onPressed: onOrderOptions,
                    tooltip: 'Order options',
                    icon: const Icon(Icons.tune_outlined, size: 20),
                  ),
          ),
          SingleChildScrollView(
            key: const ValueKey('online-order-status-filters'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                for (final value in OnlineOrderProgressFilter.values) ...[
                  ChoiceChip(
                    label: Text(_shortProgressLabel(value)),
                    selected: progress == value,
                    onSelected: (_) => onProgress(value),
                    showCheckmark: false,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onFilter,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(
                filterCount == 0
                    ? 'Source and date'
                    : 'Source and date · $filterCount',
              ),
            ),
          ),
        ],
      );
}

class _OnlineOrdersLoading extends StatelessWidget {
  const _OnlineOrdersLoading();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, {double height = 12}) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
        );

    return Shimmer.fromColors(
      key: const ValueKey('online-orders-loading-shimmer'),
      baseColor: Colors.black12,
      highlightColor: Colors.black26,
      child: Column(
        children: [
          for (var index = 0; index < 5; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            bar(150, height: 14),
                            const SizedBox(height: 8),
                            bar(100),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      bar(70, height: 16),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SetupNotice extends StatelessWidget {
  const _SetupNotice({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.storefront_outlined),
          title: const Text('Finish setting up online selling'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onPressed,
        ),
      );
}

class _PartialErrorNotice extends StatelessWidget {
  const _PartialErrorNotice({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Some online order information could not be refreshed.',
                maxLines: 2,
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      );
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({
    required this.source,
    required this.dateLabel,
    required this.hasDate,
    required this.onClear,
  });

  final OnlineOrderSourceFilter source;
  final String dateLabel;
  final bool hasDate;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (source != OnlineOrderSourceFilter.all)
              Chip(label: Text(_sourceLabel(source))),
            if (hasDate) Chip(label: Text(dateLabel)),
            TextButton(onPressed: onClear, child: const Text('Clear')),
          ],
        ),
      );
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order, required this.onTap});

  final _OnlineOrderSummary order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = order.createdAt == null
        ? ''
        : DateFormat('dd MMM yyyy · HH:mm').format(order.createdAt!);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  order.isOwned
                      ? Icons.inventory_2_outlined
                      : Icons.local_shipping_outlined,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      order.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (date.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(date, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyUtil.format(order.amountMinor / 100),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    order.statusLabel,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrdersEmpty extends StatelessWidget {
  const _OrdersEmpty({required this.setupRequired, required this.onPressed});

  final bool setupRequired;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 42, 20, 24),
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text(
              'No online orders yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (onPressed != null)
              FilledButton(
                onPressed: onPressed,
                child: Text(setupRequired ? 'Finish setup' : 'Share shop link'),
              )
            else
              Text(
                'Pull down to check again.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      );
}

String _sourceLabel(OnlineOrderSourceFilter value) => switch (value) {
      OnlineOrderSourceFilter.all => 'All orders',
      OnlineOrderSourceFilter.owned => 'Your stock',
      OnlineOrderSourceFilter.supplier => 'Supplier products',
    };

String _shortProgressLabel(OnlineOrderProgressFilter value) => switch (value) {
      OnlineOrderProgressFilter.all => 'All',
      OnlineOrderProgressFilter.awaitingPayment => 'Awaiting payment',
      OnlineOrderProgressFilter.inProgress => 'In progress',
      OnlineOrderProgressFilter.completed => 'Completed',
      OnlineOrderProgressFilter.needsAttention => 'Needs attention',
      OnlineOrderProgressFilter.refunded => 'Refunded',
    };

String _titleCase(String value) => value
    .replaceAll('_', ' ')
    .split(' ')
    .map((part) => part.isEmpty
        ? part
        : '${part.substring(0, 1).toUpperCase()}${part.substring(1)}')
    .join(' ');

String _ownedStatusLabel(String value) => switch (value) {
      'pending' ||
      'pending_payment' ||
      'awaiting_payment' =>
        'Awaiting payment',
      'refund_pending' => 'Refund pending',
      _ => _titleCase(value),
    };
