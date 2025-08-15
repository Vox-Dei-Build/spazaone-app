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

  Future<Map<String, dynamic>> _fetchOrder() async {
    final callable = FirebaseFunctions.instance.httpsCallable('getOrderById');
    final result = await callable.call({
      'merchantId': FirebaseAuth.instance.currentUser?.uid,
      'orderId': widget.orderId,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> _markCollected() async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('updateOrderPayment');
    await callable.call({
      'merchantId': FirebaseAuth.instance.currentUser?.uid,
      'orderId': widget.orderId,
      'paymentAction': 'MARK_COLLECTED',
    });
    setState(() {
      _updated = true;
      _orderFuture = _fetchOrder();
    });
  }

  Future<void> _settleBnpl() async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('updateOrderPayment');
    await callable.call({
      'merchantId': FirebaseAuth.instance.currentUser?.uid,
      'orderId': widget.orderId,
      'paymentAction': 'SETTLE_BNPL',
    });
    setState(() {
      _updated = true;
      _orderFuture = _fetchOrder();
    });
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
        appBar: CustomAppBar(
          title: 'Order #${widget.orderId}',
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 5,
              vertical: SizeConfig.heightMultiplier * 2,
            ),
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
                final createdAt = order['createdAt'] != null
                    ? DateFormat('dd-MM-yyyy HH:mm')
                        .format(DateTime.parse(order['createdAt'].toString()))
                    : '';

                return ListView(
                  children: [
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding:
                            EdgeInsets.all(SizeConfig.heightMultiplier * 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTile('Total',
                                CurrencyUtil.format(order['total'] ?? 0)),
                            _buildTile('Date', createdAt),
                            _buildTile('Status', order['status'] ?? ''),
                            _buildTile(
                                'Payment Method', order['paymentMethod'] ?? ''),
                            _buildTile(
                                'Payment Status', order['paymentStatus'] ?? ''),
                            _buildTile('Collected',
                                (order['collected'] == true) ? 'Yes' : 'No'),
                            _buildProducts(order),
                            if (order['paymentMethod'] == 'BNPL' &&
                                order['status'] != 'paid')
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _settleBnpl,
                                  child: const Text('Mark as Paid'),
                                ),
                              ),
                            if (order['collected'] != true)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _markCollected,
                                  child: const Text('Mark Collected'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  ListTile _buildTile(String title, String subtitle) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: SizeConfig.textMultiplier * 2,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: SizeConfig.textMultiplier * 1.8,
        ),
      ),
    );
  }

  Widget _buildProducts(Map<String, dynamic> order) {
    final items = order['items'];
    if (items is! List || items.isEmpty) {
      return _buildTile('Products', 'No products associated with this order.');
    }

    return ListTile(
      title: Text(
        'Products',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: SizeConfig.textMultiplier * 2,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map<Widget>((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final productId =
              map['productId'] ?? map['id'] ?? map['productID'] ?? '';
          final quantity = map['quantity'] ?? map['qty'] ?? 0;

          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
                .collection('products')
                .doc(productId)
                .get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return Text('Unknown product: $productId');
              }
              final productData = snapshot.data!.data() as Map<String, dynamic>;
              final productName = productData['name'] ?? 'Unnamed product';
              final sellingPrice = productData['sellingPrice'];
              return _buildProductCard(productName, quantity, sellingPrice);
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProductCard(
      String productName, dynamic quantity, dynamic sellingPrice) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory,
                  size: SizeConfig.imageSizeMultiplier * 4,
                ),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                Expanded(
                  child: Text(
                    formatStringToCamelCase(productName),
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
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.8,
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 0.5),
            Text(
              'Selling Price: ${CurrencyUtil.format(sellingPrice)}',
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
