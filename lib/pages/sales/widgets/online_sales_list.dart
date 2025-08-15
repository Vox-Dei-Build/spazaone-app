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
      if (!m.containsKey('total') && m.containsKey('amount'))
        m['total'] = m['amount'];
      if (!m.containsKey('createdAt') && m.containsKey('dateAdded'))
        m['createdAt'] = m['dateAdded'];
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
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final o = items[i];
            final dateStr = o.createdAt != null
                ? DateFormat('dd MMM yyyy · HH:mm').format(o.createdAt!)
                : '—';
            return ListTile(
              title: Text('#${o.id}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  'Total ${currency.format(o.total ?? 0)} · ${o.itemsCount} items\n$dateStr'),
            );
          },
        );
      },
    );
  }
}
