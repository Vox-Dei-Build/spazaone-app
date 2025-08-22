import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/config/size_config.dart';

class OrderDetailPage extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> order;

  const OrderDetailPage({
    super.key,
    required this.orderId,
    required this.order,
  });

  Future<void> _confirmCancel(BuildContext context) async {
    final shouldCancel = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cancel Order'),
            content: const Text('Are you sure you want to cancel this order?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes'),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldCancel) {
      await _cancelOrder(context);
    }
  }

  Future<void> _cancelOrder(BuildContext context) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final orderRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('orders')
          .doc(orderId);

      await orderRef.update({'status': 'cancelled'});

      if (order['products'] != null && order['products'] is Map) {
        Map<String, dynamic> products =
            Map<String, dynamic>.from(order['products']);
        for (var entry in products.entries) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('products')
              .doc(entry.key)
              .update({'quantity': FieldValue.increment(entry.value)});
        }
      }

      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled successfully.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error cancelling order.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Order Details',
        trailing: IconButton(
          icon: const Icon(Icons.cancel),
          onPressed: () => _confirmCancel(context),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 5,
          vertical: SizeConfig.heightMultiplier * 2,
        ),
        child: ListView(
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildListTile('Amount',
                        CurrencyUtil.format(order['amount'] ?? 0)),
                    _buildListTile('Status', order['status'] ?? 'unknown'),
                    _buildListTile('Date', order['date'].toDate().toString()),
                    if (order['remarks'] != null)
                      _buildListTile('Remarks', order['remarks']),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile(String title, String subtitle) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

