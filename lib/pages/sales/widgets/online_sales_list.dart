import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
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
    _future = _fetchSales();
  }

  Future<List<OrderModel>> _fetchSales() async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('getMerchantSales');
    final result = await callable.call({
      'merchantId': FirebaseAuth.instance.currentUser?.uid,
      'type': 'Online',
    });
    final List<dynamic> data = result.data['sales'] ?? [];
    return data
        .map((e) => OrderModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return FutureBuilder<List<OrderModel>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              'No online sales available.',
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
            ),
          );
        } else {
          final sales = snapshot.data!;
          return ListView.builder(
            itemCount: sales.length,
            itemBuilder: (context, index) {
              final s = sales[index];
              final dateStr = s.createdAt != null
                  ? DateFormat('dd-MM-yyyy HH:mm').format(s.createdAt!)
                  : '';
              return ListTile(
                title: Text('#${s.id} - ${s.status}'),
                subtitle: Text(
                    'Total: R${s.total.toStringAsFixed(2)} · Items: ${s.itemsCount}\n$dateStr'),
              );
            },
          );
        }
      },
    );
  }
}
