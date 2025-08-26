import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/models/sales/order_model.dart';
import 'package:pasella/pages/sales/widgets/online_sale_detail_page.dart';

class OnlineSalesList extends StatefulWidget {
  final DateTime? selectedDay;
  final DateTime? startDate;
  final DateTime? endDate;
  const OnlineSalesList({super.key, this.selectedDay, this.startDate, this.endDate});
  @override
  State<OnlineSalesList> createState() => _OnlineSalesListState();
}

class _OnlineSalesListState extends State<OnlineSalesList> {
  late Future<List<OrderModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant OnlineSalesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDay != widget.selectedDay ||
        oldWidget.startDate != widget.startDate ||
        oldWidget.endDate != widget.endDate) {
      _future = _fetch();
    }
  }

  Future<List<OrderModel>> _fetch() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    final callable =
        FirebaseFunctions.instance.httpsCallable('getMerchantSales');
    final res = await callable.call({'merchantId': uid, 'type': 'Online'});
    final list = (res.data['sales'] as List<dynamic>? ?? []);

    final adapted = list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      if (!m.containsKey('total') && m.containsKey('amount')) {
        m['total'] = m['amount'];
      }
      if (!m.containsKey('createdAt') && m.containsKey('dateAdded')) {
        m['createdAt'] = m['dateAdded'];
      }
      return OrderModel.fromMap(m);
    }).toList();

    return _filterByDate(adapted);
  }

  List<OrderModel> _filterByDate(List<OrderModel> items) {
    if (widget.startDate != null && widget.endDate != null) {
      final start = DateTime(widget.startDate!.year, widget.startDate!.month,
          widget.startDate!.day);
      final end = DateTime(widget.endDate!.year, widget.endDate!.month,
          widget.endDate!.day + 1);
      return items
          .where((o) => o.createdAt != null &&
              o.createdAt!.isAfter(start) && o.createdAt!.isBefore(end))
          .toList();
    } else if (widget.selectedDay != null) {
      final start = DateTime(widget.selectedDay!.year,
          widget.selectedDay!.month, widget.selectedDay!.day);
      final end = start.add(const Duration(days: 1));
      return items
          .where((o) => o.createdAt != null &&
              o.createdAt!.isAfter(start) && o.createdAt!.isBefore(end))
          .toList();
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        NumberFormat.currency(locale: 'en_ZA', symbol: 'R', decimalDigits: 2);
    return FutureBuilder<List<OrderModel>>(
      future: _future,
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return Center(child: Text('Failed to load online sales: ${s.error}'));
        }
        final items = s.data ?? const <OrderModel>[];
        if (items.isEmpty) {
          return const Center(child: Text('No online sales'));
        }

        final summary = <String, _StatusSummary>{};
        for (final o in items) {
          final agg = summary.putIfAbsent(o.status, () => _StatusSummary());
          agg.count++;
          agg.total += o.total;
        }

        return ListView.separated(
          itemCount: items.length + 1,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            if (i == 0) {
              return _buildSummaryCard(summary, currency);
            }
            final o = items[i - 1];
            final dateStr = o.createdAt != null
                ? DateFormat('dd MMM yyyy · HH:mm').format(o.createdAt!)
                : '—';
            return Card(
              child: ListTile(
                title: Text('#${o.id}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Total ${currency.format(o.total)} · ${o.itemsCount} items\n$dateStr'),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => OnlineSaleDetailPage(orderId: o.id)));
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSummaryCard(
      Map<String, _StatusSummary> summary, NumberFormat currency) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: summary.entries.map((e) {
            final status = _formatStatus(e.key);
            final count = e.value.count;
            final total = currency.format(e.value.total);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(status,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('$count · $total'),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _formatStatus(String status) {
    return status
        .split('_')
        .map((s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' ');
  }
}

class _StatusSummary {
  int count = 0;
  double total = 0;
}
