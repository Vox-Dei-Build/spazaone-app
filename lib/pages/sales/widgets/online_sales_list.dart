import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/models/sales/order_model.dart';

class OnlineSalesList extends StatefulWidget {
  const OnlineSalesList({super.key});
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

  Future<List<OrderModel>> _fetch() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    final callable =
        FirebaseFunctions.instance.httpsCallable('getMerchantSales');
    final res = await callable.call({'merchantId': uid, 'type': 'Online'});
    final list = (res.data['sales'] as List<dynamic>? ?? []);

    // Adapt if backend not yet normalized
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

    return adapted;
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
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == 0) {
              return _buildSummaryCard(summary, currency);
            }
            final o = items[i - 1];
            final dateStr = o.createdAt != null
                ? DateFormat('dd MMM yyyy · HH:mm').format(o.createdAt!)
                : '—';
            return ListTile(
              title: Text('#${o.id}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  'Total ${currency.format(o.total)} · ${o.itemsCount} items\n$dateStr'),
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
