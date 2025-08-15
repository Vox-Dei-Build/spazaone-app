import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/sales/order_model.dart';
import 'package:pasella/pages/contact/orders_management/order_details_screen.dart';

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
  _OrderStatus _status = _OrderStatus.all;
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
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
    final callable =
        FirebaseFunctions.instance.httpsCallable('getCustomerOrders');
    final result = await callable
        .call({'merchantId': uid, 'customerId': widget.customerId});
    final List<dynamic> data = result.data['orders'] ?? [];
    final list = data
        .map((e) => OrderModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    return _applyClientFilters(list);
  }

  List<OrderModel> _applyClientFilters(List<OrderModel> source) {
    bool matchesStatus(OrderModel o) {
      if (_status == _OrderStatus.all) return true;
      return _OrderStatusX.fromString(o.status) == _status;
    }

    bool matchesQuery(OrderModel o) {
      if (_query.isEmpty) return true;
      return o.id.toLowerCase().contains(_query.toLowerCase());
    }

    bool matchesDate(OrderModel o) {
      if (_range == null || o.createdAt == null) return true;
      final d = o.createdAt!;
      return !d.isBefore(_range!.start) && !d.isAfter(_range!.end);
    }

    return source
        .where((o) => matchesStatus(o) && matchesQuery(o) && matchesDate(o))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() => _ordersFuture = _fetchOrders());
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
    final currency =
        NumberFormat.currency(locale: 'en_ZA', symbol: 'R', decimalDigits: 2);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _SearchField(
                  controller: _searchCtl,
                  hint: 'Search by order #...',
                  onChanged: (txt) {
                    _query = txt.trim();
                    _refresh();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                  tooltip: 'Date range',
                  icon: const Icon(Icons.date_range),
                  onPressed: _pickDateRange),
              if (_range != null)
                IconButton(
                    tooltip: 'Clear dates',
                    icon: const Icon(Icons.clear),
                    onPressed: _clearDateRange),
            ],
          ),
        ),
        _StatusChips(
          selected: _status,
          onSelected: (s) {
            if (_status == s) return;
            setState(() {
              _status = s;
              _ordersFuture = _fetchOrders();
            });
          },
        ),
        FutureBuilder<List<OrderModel>>(
          future: _ordersFuture,
          builder: (context, snap) {
            final orders = snap.data ?? const <OrderModel>[];
            final total =
                orders.fold<double>(0.0, (a, b) => a + (b.total ?? 0));
            final rangeText = _range == null
                ? 'All time'
                : '${DateFormat('dd MMM').format(_range!.start)} – ${DateFormat('dd MMM').format(_range!.end)}';
            return _SummaryBar(
                count: orders.length,
                totalText: currency.format(total),
                rangeText: rangeText);
          },
        ),
        const Divider(height: 1),
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
                    itemBuilder: (_, __) => const _OrderSkeleton(),
                  );
                } else if (snapshot.hasError) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 48),
                      _StateMessage(
                        icon: Icons.error_outline,
                        title: "Couldn't load orders",
                        subtitle: 'Please pull to refresh or try again later.',
                        primaryLabel: 'Retry',
                      ),
                    ],
                  );
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 48),
                      _StateMessage(
                        icon: Icons.inbox_outlined,
                        title: 'No orders here (yet)',
                        subtitle: 'Try adjusting filters or date range.',
                        primaryLabel: 'Clear filters',
                      ),
                    ],
                  );
                } else {
                  final orders = snapshot.data!;
                  return ListView.separated(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final o = orders[index];
                      final status = _OrderStatusX.fromString(o.status);
                      final dateStr = o.createdAt != null
                          ? DateFormat('dd MMM yyyy · HH:mm')
                              .format(o.createdAt!)
                          : '—';

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        title: Row(
                          children: [
                            Text('#${o.id}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            _StatusPill(
                                text: status.label,
                                color: status.color(context)),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(
                            'Total ${currency.format(o.total ?? 0)} · ${o.itemsCount} items\n$dateStr',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final updated = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OrderDetailScreen(
                                customerId: widget.customerId,
                                customerName: widget.customerName,
                                orderId: o.id,
                              ),
                            ),
                          );
                          if (updated == true) _refresh();
                        },
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
}

class _SearchField extends StatelessWidget {
  const _SearchField(
      {required this.controller, required this.onChanged, this.hint});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hint;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint ?? 'Search…',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

enum _OrderStatus { all, pending, paid, fulfilled, cancelled, refunded }

extension _OrderStatusLabel on _OrderStatus {
  String get label => switch (this) {
        _OrderStatus.all => 'All',
        _OrderStatus.pending => 'Pending',
        _OrderStatus.paid => 'Paid',
        _OrderStatus.fulfilled => 'Fulfilled',
        _OrderStatus.cancelled => 'Cancelled',
        _OrderStatus.refunded => 'Refunded',
      };
}

extension _OrderStatusX on _OrderStatus {
  Color color(BuildContext c) => switch (this) {
        _OrderStatus.pending => Colors.amber,
        _OrderStatus.paid => Colors.green,
        _OrderStatus.fulfilled => Colors.blue,
        _OrderStatus.cancelled => Colors.red,
        _OrderStatus.refunded => Colors.purple,
        _OrderStatus.all => Theme.of(c).colorScheme.outline,
      };
  static _OrderStatus fromString(String v) {
    final x = v.toLowerCase();
    if (x.contains('refund')) return _OrderStatus.refunded;
    if (x.contains('cancel')) return _OrderStatus.cancelled;
    if (x.contains('fulfill')) return _OrderStatus.fulfilled;
    if (x.contains('paid') || x.contains('complete')) return _OrderStatus.paid;
    if (x.contains('pending') || x.isEmpty) return _OrderStatus.pending;
    return _OrderStatus.pending;
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.selected, required this.onSelected});
  final _OrderStatus selected;
  final ValueChanged<_OrderStatus> onSelected;
  @override
  Widget build(BuildContext context) {
    const statuses = _OrderStatus.values;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          for (final s in statuses)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(s.label),
                selected: s == selected,
                onSelected: (_) => onSelected(s),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar(
      {required this.count, required this.totalText, required this.rangeText});
  final int count;
  final String totalText;
  final String rangeText;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        Expanded(child: Text('$count orders', style: t.titleMedium)),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(totalText,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(rangeText, style: t.bodySmall),
        ]),
      ]),
    );
  }
}

class _OrderSkeleton extends StatelessWidget {
  const _OrderSkeleton();
  @override
  Widget build(BuildContext context) {
    Widget box({double h = 12, double w = double.infinity}) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
            borderRadius: BorderRadius.circular(8),
          ),
        );
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      title: Row(
          children: [box(w: 80), const SizedBox(width: 8), box(w: 56, h: 20)]),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          box(w: 180),
          const SizedBox(height: 8),
          box(w: 120),
        ]),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.primaryLabel});
  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(title, style: t.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(subtitle, style: t.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: () => Navigator.maybePop(context),
            child: Text(primaryLabel)),
      ]),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) {
    const fg = Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: const TextStyle(color: fg, fontSize: 12)),
    );
  }
}
