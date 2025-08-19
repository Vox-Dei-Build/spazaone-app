// UPDATED IMPORTS
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/sales/order_model.dart';
import 'package:pasella/pages/contact/orders_management/order_details_screen.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/utils/currency_util.dart';

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

    return Column(
      children: [
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
                child: _SearchField(
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
            final orders = snap.data ?? const <OrderModel>[];
            final total = orders.fold<double>(0.0, (a, b) => a + (b.total));
            final rangeText = _range == null
                ? 'All time'
                : '${DateFormat('dd MMM').format(_range!.start)} – ${DateFormat('dd MMM').format(_range!.end)}';
            return _SummaryBar(
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
                    itemBuilder: (_, __) => const _OrderSkeleton(),
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
                      final status = _OrderStatusX.fromString(o.status);
                      final dateStr = o.createdAt != null
                          ? DateFormat('y MMM d, h:mm a').format(o.createdAt!)
                          : '';

                      return _OrderTile(
                        id: o.id,
                        status: status,
                        totalText: CurrencyUtil.format(o.total),
                        itemsCount: o.itemsCount,
                        dateText: dateStr,
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
      style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.7),
      decoration: InputDecoration(
        hintText: hint ?? 'Search…',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 3,
          vertical: SizeConfig.heightMultiplier * 1.6,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

enum _OrderStatus {
  all,
  pending,
  paid,
  fulfilled,
  cancelled,
  refunded,
  uncollected,
  collected,
  bnplPending,
  bnplOutstanding,
}

extension _OrderStatusLabel on _OrderStatus {
  String get label => switch (this) {
        _OrderStatus.all => 'All',
        _OrderStatus.pending => 'Pending',
        _OrderStatus.paid => 'Paid',
        _OrderStatus.fulfilled => 'Fulfilled',
        _OrderStatus.cancelled => 'Cancelled',
        _OrderStatus.refunded => 'Refunded',
        _OrderStatus.uncollected => 'Uncollected',
        _OrderStatus.collected => 'Collected',
        _OrderStatus.bnplPending => 'BNPL Pending',
        _OrderStatus.bnplOutstanding => 'BNPL Outstanding',
      };
}

extension _OrderStatusX on _OrderStatus {
  Color color(BuildContext c) => switch (this) {
        _OrderStatus.pending => Colors.amber,
        _OrderStatus.paid => Colors.green,
        _OrderStatus.fulfilled => Colors.blue,
        _OrderStatus.cancelled => Colors.red,
        _OrderStatus.refunded => Colors.purple,
        _OrderStatus.uncollected => Colors.orange,
        _OrderStatus.collected => Colors.teal,
        _OrderStatus.bnplPending => Colors.deepOrange,
        _OrderStatus.bnplOutstanding => Colors.brown,
        _OrderStatus.all => Theme.of(c).colorScheme.outline,
      };

  static _OrderStatus fromString(String v,
      {String? paymentMethod, String? type}) {
    final x = (v ?? '').toLowerCase();
    final pm = (paymentMethod ?? '').toLowerCase();
    final t = (type ?? '').toLowerCase();

    // BNPL detection
    final isBnpl = pm == 'bnpl' || t == 'bnpl' || x.contains('bnpl');
    if (isBnpl) {
      if (x.contains('outstanding') || x.contains('approved')) {
        return _OrderStatus.bnplOutstanding;
      }
      return _OrderStatus.bnplPending;
    }

    if (x.contains('uncollected')) return _OrderStatus.uncollected;
    if (x.contains('collected')) return _OrderStatus.collected;
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
    final selColor = Theme.of(context).colorScheme.primary;
    final unSelBg =
        Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 1.2,
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 0.8,
      ),
      child: Row(
        children: [
          for (final s in statuses)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  s.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: SizeConfig.textMultiplier * 1.6,
                    color: s == selected ? Colors.white : Colors.black87,
                  ),
                ),
                selected: s == selected,
                selectedColor: selColor,
                backgroundColor: unSelBg,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: s == selected ? selColor : Colors.white,
                    width: 0.5,
                  ),
                ),
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
    return Container(
      padding: EdgeInsets.fromLTRB(
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 1.2,
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 1.2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count order(s)',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: SizeConfig.textMultiplier * 1.8,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                totalText,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: SizeConfig.textMultiplier * 2,
                ),
              ),
              Text(
                rangeText,
                style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.4,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.id,
    required this.status,
    required this.totalText,
    required this.itemsCount,
    required this.dateText,
    required this.onTap,
  });

  final String id;
  final _OrderStatus status;
  final String totalText;
  final int? itemsCount;
  final String dateText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 3,
              vertical: SizeConfig.heightMultiplier * 1.2,
            ),
            visualDensity: const VisualDensity(horizontal: -2),
            leading: _OrderAvatar(color: status.color(context)),
            title: _buildTitle(context),
            subtitle: _buildSubtitle(context),
            trailing: const Icon(Icons.chevron_right),
          ),
          const Divider(color: kHighLightColor, height: 5),
        ],
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Order id + status pill
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    '#$id',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: SizeConfig.textMultiplier * 1.8,
                    ),
                  ),
                ),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                _StatusPill(
                  text: status.label,
                  color: status.color(context),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            totalText,
            style: TextStyle(
              color: kPrimaryColor,
              fontWeight: FontWeight.bold,
              fontSize: SizeConfig.textMultiplier * 1.8,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitle(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                color: status == _OrderStatus.paid ||
                        status == _OrderStatus.fulfilled
                    ? kPrimaryColor
                    : Colors.red,
                fontWeight: FontWeight.w500,
                fontSize: SizeConfig.textMultiplier * 1.5,
              ),
              children: [
                TextSpan(text: totalText),
                TextSpan(
                  text: ' · ${itemsCount ?? 0} items · ',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                TextSpan(
                  text: dateText,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _OrderAvatar extends StatelessWidget {
  const _OrderAvatar({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: SizeConfig.imageSizeMultiplier * 4.5,
      backgroundColor: color.withOpacity(0.12),
      child: Icon(Icons.shopping_bag_rounded, color: color),
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
      child: Text(text,
          style:
              TextStyle(color: fg, fontSize: SizeConfig.textMultiplier * 1.5)),
    );
  }
}
