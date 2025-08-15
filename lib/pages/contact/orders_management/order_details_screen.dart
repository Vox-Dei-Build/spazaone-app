import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';

class OrderDetailScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String orderId;

  const OrderDetailScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.orderId,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Future<Map<String, dynamic>> _orderFuture;
  bool _updated = false;

  @override
  void initState() {
    super.initState();
    _orderFuture = _fetchOrder();
  }

  DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is Map && v['_seconds'] is num) {
      final sec = (v['_seconds'] as num).toInt();
      final nanos = (v['_nanoseconds'] as num?)?.toInt() ?? 0;
      return DateTime.fromMillisecondsSinceEpoch(sec * 1000 + nanos ~/ 1000000);
    }
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  double _asNum(dynamic v) {
    if (v is double) return v;
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  Future<Map<String, dynamic>> _fetchOrder() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    final callable = FirebaseFunctions.instance.httpsCallable('getOrderById');
    final result =
        await callable.call({'merchantId': uid, 'orderId': widget.orderId});
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> _callPayment(String action) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in.')),
      );
      return;
    }
    final fn = FirebaseFunctions.instance.httpsCallable('updateOrderPayment');
    await fn.call({
      'merchantId': uid,
      'orderId': widget.orderId,
      'paymentAction': action
    });
    if (!mounted) return;
    setState(() {
      _updated = true;
      _orderFuture = _fetchOrder();
    });
    final labels = {
      'ACCEPT_BNPL': 'BNPL approved',
      'MARK_CASH_RECEIVED': 'Cash received',
      'MARK_COLLECTED': 'Marked as collected',
      'SETTLE_BNPL': 'Marked as paid',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(labels[action] ?? 'Updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _updated);
        return false;
      },
      child: Scaffold(
        appBar: CustomAppBar(title: 'Order #${widget.orderId}'),
        body: SafeArea(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _orderFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.hasError) {
                return Center(
                  child: Text(
                    'Error loading order.',
                    style: TextStyle(fontSize: SizeConfig.textMultiplier * 3),
                  ),
                );
              }

              final order = snapshot.data!;
              final createdAtDt = _parseTs(order['createdAt']);
              final createdAt = createdAtDt != null
                  ? DateFormat('dd-MM-yyyy HH:mm').format(createdAtDt)
                  : '';

              // derive flags
              final paymentMethod = (order['paymentMethod'] ?? '').toString();
              final paymentStatus = (order['paymentStatus'] ?? '').toString();
              final status = (order['status'] ?? '').toString();
              final isPaid = paymentStatus == 'paid' || status == 'paid';
              final isCollected = order['collected'] == true;

              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: SizeConfig.imageSizeMultiplier * 5,
                      vertical: SizeConfig.heightMultiplier * 2,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: Padding(
                            padding:
                                EdgeInsets.all(SizeConfig.heightMultiplier * 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _KV(
                                    title: 'Total',
                                    value: CurrencyUtil.format(
                                        _asNum(order['total']))),
                                _KV(title: 'Date', value: createdAt),
                                _KV(title: 'Status', value: status),
                                _KV(
                                    title: 'Payment Method',
                                    value: paymentMethod.isEmpty
                                        ? '—'
                                        : paymentMethod),
                                _KV(
                                    title: 'Payment Status',
                                    value: paymentStatus.isEmpty
                                        ? '—'
                                        : paymentStatus),
                                _KV(
                                    title: 'Collected',
                                    value: isCollected ? 'Yes' : 'No'),
                                const SizedBox(height: 8),
                                _ProductsSection(
                                    items: order['items'] as List?,
                                    fallbackUserId: FirebaseAuth
                                            .instance.currentUser?.uid ??
                                        ''),
                                const SizedBox(height: 16),
                                // ==== ACTIONS (always outside ListTile to avoid gesture conflicts)
                                if (!isPaid && paymentMethod != 'BNPL') ...[
                                  _ActionBtn(
                                    label: 'Accept BNPL',
                                    icon: Icons.account_balance_wallet_outlined,
                                    onTap: () => _callPayment('ACCEPT_BNPL'),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if (!isPaid) ...[
                                  _ActionBtn(
                                    label: 'Mark Cash Received',
                                    icon: Icons.payments_outlined,
                                    onTap: () =>
                                        _callPayment('MARK_CASH_RECEIVED'),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if (paymentMethod == 'BNPL' && !isPaid) ...[
                                  _ActionBtn(
                                    label: 'Mark as Paid (Settle BNPL)',
                                    icon: Icons.done_all_outlined,
                                    onTap: () => _callPayment('SETTLE_BNPL'),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if (!isCollected) ...[
                                  _ActionBtn(
                                    label: 'Mark Collected',
                                    icon: Icons.inventory_2_outlined,
                                    onTap: () => _callPayment('MARK_COLLECTED'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Simple key/value row (replaces ListTile to prevent touch conflicts)
class _KV extends StatelessWidget {
  const _KV({required this.title, required this.value});
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: SizeConfig.textMultiplier * 2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// Actions button with full-width tap target
class _ActionBtn extends StatelessWidget {
  const _ActionBtn(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

/// Products as a non-interfering section (no ListTile wrapper)
class _ProductsSection extends StatelessWidget {
  const _ProductsSection({required this.items, required this.fallbackUserId});
  final List? items;
  final String fallbackUserId;

  @override
  Widget build(BuildContext context) {
    if (items == null || items!.isEmpty) {
      return _Section(
        title: 'Products',
        child: Text(
          'No products associated with this order.',
          style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.8),
        ),
      );
    }

    return _Section(
      title: 'Products',
      child: Column(
        children: items!.map<Widget>((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final productId =
              (map['productId'] ?? map['id'] ?? map['productID'] ?? '')
                  .toString();
          final quantity = map['quantity'] ?? map['qty'] ?? 0;

          if (productId.isEmpty) {
            return const Align(
              alignment: Alignment.centerLeft,
              child: Text('Unknown product'),
            );
          }

          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(fallbackUserId)
                .collection('products')
                .doc(productId)
                .get(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (!snap.hasData || !snap.data!.exists) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Unknown product: $productId'),
                );
              }
              final data = snap.data!.data() as Map<String, dynamic>;
              final name = (data['name'] ?? 'Unnamed product').toString();
              final sellingPrice = (data['sellingPrice']);
              return _ProductCard(
                productName: formatStringToCamelCase(name),
                quantity: quantity,
                sellingPrice: sellingPrice,
              );
            },
          );
        }).toList(),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: SizeConfig.textMultiplier * 2,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard(
      {required this.productName,
      required this.quantity,
      required this.sellingPrice});
  final String productName;
  final dynamic quantity;
  final dynamic sellingPrice;

  double _asNum(dynamic v) {
    if (v is double) return v;
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory, size: SizeConfig.imageSizeMultiplier * 4),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                Expanded(
                  child: Text(
                    productName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: SizeConfig.textMultiplier * 2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            Text(
              'Quantity: $quantity',
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.8),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 0.5),
            Text(
              'Selling Price: ${CurrencyUtil.format(_asNum(sellingPrice))}',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: SizeConfig.textMultiplier * 1.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
