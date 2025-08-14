import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/sales/order_model.dart';

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

  @override
  void initState() {
    super.initState();
    _ordersFuture = _fetchOrders();
  }

  Future<List<OrderModel>> _fetchOrders() async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('getCustomerOrders');
    final result = await callable.call({
      'merchantId': FirebaseAuth.instance.currentUser?.uid,
      'customerId': widget.customerId,
    });
    final List<dynamic> data = result.data['orders'] ?? [];
    return data
        .map((e) => OrderModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return FutureBuilder<List<OrderModel>>(
      future: _ordersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              'No orders available.',
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
            ),
          );
        } else {
          final orders = snapshot.data!;
          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final o = orders[index];
              final dateStr = o.createdAt != null
                  ? DateFormat('dd-MM-yyyy HH:mm').format(o.createdAt!)
                  : '';
              return ListTile(
                title: Text('#${o.id} - ${o.status}'),
                subtitle: Text(
                    'Total: R${o.total.toStringAsFixed(2)} · Items: ${o.itemsCount}\n$dateStr'),
              );
            },
          );
        }
      },
    );
  }
}
