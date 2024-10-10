import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';
import 'package:pasella/config/size_config.dart';

class TransactionDetailScreen extends StatelessWidget {
  final String customerName;
  final String customerId;
  final String transactionId;
  final Map<String, dynamic> transaction;

  const TransactionDetailScreen({
    super.key,
    required this.customerName,
    required this.customerId,
    required this.transactionId,
    required this.transaction,
  });

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    bool hasProducts = transaction.containsKey('products');
    bool isMap = hasProducts && transaction['products'] is Map<String, dynamic>;
    bool isNotEmpty =
        isMap && (transaction['products'] as Map<String, dynamic>).isNotEmpty;

    return Scaffold(
      appBar: CustomAppBar(title: 'Transaction Details for $customerName'),
      body: SafeArea(
        child: Padding(
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
                      buildListTile('Amount',
                          CurrencyUtil.format(transaction['amount'] ?? 0)),
                      buildListTile('Date', transaction['date'].toString()),
                      if (transaction['type'] == 'Credit')
                        buildListTile('Repayment Date',
                            transaction['repaymentDate'].toDate().toString()),
                      buildListTile('Status', transaction['status']),
                      buildListTile('Type', transaction['type']),
                      buildProductListTile(
                          context, hasProducts, isMap, isNotEmpty)
                    ],
                  ),
                ),
              ),
            ],
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

  Widget buildProductListTile(
      BuildContext context, bool hasProducts, bool isMap, bool isNotEmpty) {
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
                      return Text('Error fetching product with ID: $productId');
                    }
                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return Text('Unknown product with ID: $productId');
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
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier *
            2), // Add padding to avoid overflow
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
            SizedBox(
                height: SizeConfig.heightMultiplier * 1), // Add some spacing
            Text(
              'Quantity: $quantity',
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.8,
              ),
            ),
            SizedBox(
                height: SizeConfig.heightMultiplier * 0.5), // Add some spacing
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
