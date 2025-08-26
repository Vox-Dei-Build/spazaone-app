import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/pages/ecommerce/orders/data/order_repository.dart';
import 'package:pasella/utils/currency_util.dart';

class OnlineSaleDetailPage extends StatelessWidget {
  final String orderId;
  const OnlineSaleDetailPage({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
        locale: 'en_ZA', symbol: 'R', decimalDigits: 2);
    return Scaffold(
      appBar: AppBar(title: Text('Order #$orderId')),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: OrderRepository.orderStream(orderId: orderId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Order not found'));
          }
          final order = snapshot.data!;
          final items = (order['items'] as List?) ?? [];
          final total =
              currency.format(OrderRepository.asNum(order['total']));
          final status = (order['status'] ?? '').toString();
          final date = OrderRepository.parseTs(order['createdAt']);
          final dateStr = date != null
              ? DateFormat('dd MMM yyyy · HH:mm').format(date)
              : '—';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Status: $status'),
              const SizedBox(height: 4),
              Text('Date: $dateStr'),
              const SizedBox(height: 4),
              Text('Total: $total',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('Items', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...items.map<Widget>((i) {
                final name = (i['name'] ?? '').toString();
                final qty = OrderRepository.asNum(i['quantity']).toInt();
                final price = currency
                    .format(OrderRepository.asNum(i['price'] ?? i['unit']));
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(name),
                  trailing: Text('$qty x $price'),
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }
}
