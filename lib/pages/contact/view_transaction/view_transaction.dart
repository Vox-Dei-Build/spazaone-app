import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/pages/contact/edit_transaction/edit_transaction.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';
import 'package:pasella/config/size_config.dart';

class TransactionDetailScreen extends StatefulWidget {
  final String customerName;
  final String customerId;
  final String transactionId;
  final Map<String, dynamic> transaction;
  final String? mobileNumber;

  const TransactionDetailScreen({
    super.key,
    required this.customerName,
    required this.customerId,
    required this.transactionId,
    required this.transaction,
    this.mobileNumber,
  });

  @override
  _TransactionDetailScreenState createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  late Future<DocumentSnapshot> _transactionFuture;

  @override
  void initState() {
    super.initState();
    // Load transaction details from Firestore
    _transactionFuture = loadTransactionDetails();
  }

  Future<DocumentSnapshot> loadTransactionDetails() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser?.uid)
        .collection('customers')
        .doc(widget.customerId)
        .collection('transactions')
        .doc(widget.transactionId)
        .get();
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final shouldCancel = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cancel Order'),
            content: const Text(
                'Are you sure you want to cancel this order?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('No')),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Yes')),
            ],
          ),
        ) ??
        false;

    if (shouldCancel) {
      await _cancelTransaction(context);
    }
  }

  Future<void> _cancelTransaction(BuildContext context) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('customers')
          .doc(widget.customerId)
          .collection('transactions')
          .doc(widget.transactionId);

      await docRef.delete();

      if (widget.transaction['products'] != null &&
          widget.transaction['products'] is Map) {
        Map<String, dynamic> products =
            Map<String, dynamic>.from(widget.transaction['products']);
        for (var entry in products.entries) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('products')
              .doc(entry.key)
              .update({'quantity': FieldValue.increment(entry.value)});
        }
      }

      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled successfully.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error cancelling order.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Transaction Details for ${widget.customerName}',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => EditTransactionScreen(
                      customerName: widget.customerName,
                      customerId: widget.customerId,
                      transactionId: widget.transactionId,
                      transaction: widget.transaction,
                      mobileNumber: widget.mobileNumber,
                    ),
                  ),
                );
                setState(() {
                  _transactionFuture = loadTransactionDetails();
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.cancel),
              onPressed: () => _confirmCancel(context),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 5,
            vertical: SizeConfig.heightMultiplier * 2,
          ),
          child: FutureBuilder<DocumentSnapshot>(
            future: _transactionFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.hasError) {
                return Center(
                    child: Text(
                  'Error loading transaction data.',
                  style: TextStyle(fontSize: SizeConfig.textMultiplier * 3),
                ));
              }

              // Get the transaction data from Firestore
              var transaction = snapshot.data!.data() as Map<String, dynamic>;

              bool hasProducts = transaction.containsKey('products');
              bool isMap = hasProducts &&
                  transaction['products'] is Map<String, dynamic>;
              bool isNotEmpty = isMap &&
                  (transaction['products'] as Map<String, dynamic>).isNotEmpty;
              bool hasRemarks = transaction.containsKey('remarks') &&
                  (transaction['remarks'] is String) &&
                  transaction['remarks'] != '';
              String remarks =
                  hasRemarks ? transaction['remarks'] : 'No remarks';

              return ListView(
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
                          buildListTile('Amount',
                              CurrencyUtil.format(transaction['amount'] ?? 0)),
                          buildListTile(
                              'Date', transaction['date'].toDate().toString()),
                          if (transaction['type'] == 'Credit')
                            buildListTile(
                                'Repayment Date',
                                transaction['repaymentDate']
                                    .toDate()
                                    .toString()),
                          buildListTile('Status', transaction['status']),
                          buildListTile('Type', transaction['type']),
                          buildListTile('Remarks', remarks),
                          buildProductListTile(context, hasProducts, isMap,
                              isNotEmpty, transaction)
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
    );
  }

  ListTile buildListTile(String title, String subtitle) {
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

  Widget buildProductListTile(BuildContext context, bool hasProducts,
      bool isMap, bool isNotEmpty, Map<String, dynamic> transaction) {
    return ListTile(
      title: Text(
        'Products',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: SizeConfig.textMultiplier * 2,
        ),
      ),
      subtitle: hasProducts && isMap && isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: (transaction['products'] as Map<String, dynamic>)
                  .entries
                  .map((entry) {
                final productId = entry.key;
                final quantity = entry.value as int;

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
                    if (snapshot.hasError) {
                      return Text('Error fetching product with ID: $productId',
                          style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 3));
                    }
                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return Text('Unknown product with ID: $productId',
                          style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 3));
                    }
                    final productData =
                        snapshot.data!.data() as Map<String, dynamic>;
                    final productName =
                        productData['name'] ?? 'Unnamed product';
                    final sellingPrice = productData['sellingPrice'];

                    return buildProductCard(
                        productName, quantity, sellingPrice);
                  },
                );
              }).toList(),
            )
          : Text(
              'No products associated with this transaction.',
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.8),
            ),
    );
  }

  Widget buildProductCard(
      String productName, int quantity, dynamic sellingPrice) {
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
