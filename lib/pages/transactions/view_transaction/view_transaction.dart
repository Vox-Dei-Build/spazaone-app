import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/pages/transactions/edit_transaction/edit_transaction.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/string_utils.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/utils/transaction_util.dart';

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
    _transactionFuture = loadTransactionDetails();
  }

  Future<DocumentSnapshot> loadTransactionDetails() {
    final uid = StoreSession.instance.storeId;
    // If uid is null, this will still return a future and be handled in builder
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('customers')
        .doc(widget.customerId)
        .collection('transactions')
        .doc(widget.transactionId)
        .get();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final hm = sizeConfigUtil(SizeConfig.heightMultiplier);
    final im = sizeConfigUtil(SizeConfig.imageSizeMultiplier);
    final tm = sizeConfigUtil(SizeConfig.textMultiplier);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Transaction Details for ${widget.customerName}',
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () async {
            final result = await Navigator.of(context).push<bool>(
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
            // EditTransactionScreen returns `true` when the user
            // deleted the transaction — there's nothing left to view,
            // so close this details screen too.
            if (result == true && context.mounted) {
              Navigator.of(context).pop(true);
              return;
            }
            if (!context.mounted) return;
            setState(() {
              _transactionFuture = loadTransactionDetails();
            });
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: im * 5.0,
            vertical: hm * 2.0,
          ),
          child: FutureBuilder<DocumentSnapshot>(
            future: _transactionFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData ||
                  snapshot.hasError ||
                  !snapshot.data!.exists) {
                return Center(
                  child: Text(
                    'Error loading transaction data.',
                    style: TextStyle(fontSize: tm * 3.0),
                  ),
                );
              }

              final raw = snapshot.data!.data();
              final Map<String, dynamic> transaction =
                  (raw is Map<String, dynamic>) ? raw : <String, dynamic>{};

              final hasProducts =
                  transaction['products'] is Map<String, dynamic>;
              final Map<String, dynamic> products = hasProducts
                  ? (transaction['products'] as Map<String, dynamic>)
                  : <String, dynamic>{};

              final hasRemarks = transaction['remarks'] is String &&
                  (transaction['remarks'] as String).isNotEmpty;
              final String remarks =
                  hasRemarks ? transaction['remarks'] as String : 'No remarks';
              final paymentMethod = _paymentMethodLabel(
                transaction['paymentMethod']?.toString(),
              );
              final rawType = (transaction['type'] ?? '—').toString();
              final displayType = rawType == 'Credit' ? 'Transaction' : rawType;

              return ListView(
                children: [
                  Card(
                    elevation: 4.0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(hm * 2.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          buildListTile(
                              'Amount', formatMoney(transaction['amount']), tm),
                          buildListTile(
                              'Date', formatDateish(transaction['date']), tm),
                          if (transaction['type'] == 'Credit')
                            buildListTile(
                                'Repayment Date',
                                formatDateish(transaction['repaymentDate']),
                                tm),
                          buildListTile('Status',
                              (transaction['status'] ?? '—').toString(), tm),
                          buildListTile('Type', displayType, tm),
                          buildListTile('Remarks', remarks, tm),
                          if (transaction['type'] == 'Payment')
                            buildListTile('Payment method', paymentMethod, tm),
                          buildProductListTile(context, products, tm, hm, im),
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

  String _paymentMethodLabel(String? value) {
    switch (value) {
      case 'cash':
        return 'Cash';
      case 'bank_transfer':
        return 'Bank transfer';
      case 'other':
        return 'Other';
      default:
        return 'Not recorded';
    }
  }

  ListTile buildListTile(String title, String subtitle, double tm) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: tm * 2.0,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: tm * 1.8,
        ),
      ),
    );
  }

  Widget buildProductListTile(
    BuildContext context,
    Map<String, dynamic> products,
    double tm,
    double hm,
    double im,
  ) {
    final uid = StoreSession.instance.storeId;
    return ListTile(
      title: Text(
        'Products',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: tm * 2.0,
        ),
      ),
      subtitle: products.isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: products.entries.map((entry) {
                final productId = entry.key;
                final quantity = toInt(entry.value, fallback: 0);

                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('products')
                      .doc(productId)
                      .get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: LinearProgressIndicator(),
                      );
                    }
                    if (snapshot.hasError) {
                      return Text(
                        'Error fetching product with ID: $productId',
                        style: TextStyle(fontSize: tm * 1.8),
                      );
                    }
                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return Text(
                        'Unknown product with ID: $productId',
                        style: TextStyle(fontSize: tm * 1.8),
                      );
                    }
                    final data =
                        snapshot.data!.data() as Map<String, dynamic>? ?? {};
                    final productName =
                        (data['name'] ?? 'Unnamed product').toString();
                    final sellingPrice =
                        data['sellingPrice']; // num | String | null

                    return buildProductCard(
                      productName: productName,
                      quantity: quantity,
                      sellingPrice: sellingPrice,
                      tm: tm,
                      hm: hm,
                      im: im,
                    );
                  },
                );
              }).toList(),
            )
          : Text(
              'No products associated with this transaction.',
              style: TextStyle(fontSize: tm * 1.8),
            ),
    );
  }

  Widget buildProductCard({
    required String productName,
    required int quantity,
    required dynamic sellingPrice,
    required double tm,
    required double hm,
    required double im,
  }) {
    return Card(
      elevation: 2.0,
      margin: EdgeInsets.symmetric(
        vertical: hm * 1.0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Padding(
        padding: EdgeInsets.all(im * 2.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory,
                  size: im * 4.0,
                ),
                SizedBox(width: im * 2.0),
                Expanded(
                  child: Text(
                    formatStringToCamelCase(productName),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: tm * 2.0,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: hm * 1.0),
            Text(
              'Quantity: $quantity',
              style: TextStyle(
                fontSize: tm * 1.8,
              ),
            ),
            SizedBox(height: hm * 0.5),
            Text(
              'Selling Price: ${formatMoney(sellingPrice)}',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: tm * 1.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
