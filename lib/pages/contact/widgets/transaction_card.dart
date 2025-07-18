import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/utils/currency_util.dart';

class TransactionCard extends StatelessWidget {
  final Map<String, dynamic> transaction;

  TransactionCard(this.transaction);

  @override
  Widget build(BuildContext context) {
    bool isCredit = transaction['type'] == 'Credit';
    return Align(
      alignment: isCredit ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        width:
            SizeConfig.screenWidth * (SizeConfig.screenWidth > 360 ? 0.7 : 0.9),
        child: Card(
          margin: EdgeInsets.symmetric(
            vertical: SizeConfig.heightMultiplier * 1,
            horizontal: SizeConfig.imageSizeMultiplier * 1,
          ),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
          ),
          child: ListTile(
            leading: isCredit
                ? Icon(Icons.arrow_downward,
                    color: Colors.red, size: SizeConfig.textMultiplier * 1.8)
                : Icon(Icons.arrow_upward,
                    color: Colors.green, size: SizeConfig.textMultiplier * 1.8),
            title: Text(
              CurrencyUtil.format(transaction['amount']),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isCredit ? Colors.red : Colors.green,
                fontSize: SizeConfig.textMultiplier * 2, // Responsive font size
              ),
            ),
            subtitle: _ProductSummary(products: transaction['products']),
            trailing: Text(
              transaction['type'],
              style: TextStyle(
                color: Color(0xff9a9a9a),
                fontSize:
                    SizeConfig.textMultiplier * 1.3, // Responsive font size
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductSummary extends StatelessWidget {
  final Map<String, dynamic>? products;
  const _ProductSummary({this.products});

  @override
  Widget build(BuildContext context) {
    if (products == null || products!.isEmpty) {
      return const SizedBox.shrink();
    }

    final firstId = products!.keys.first;
    final count = products!.length;
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final future = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('products')
        .doc(firstId)
        .get();

    return FutureBuilder<DocumentSnapshot>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final name = data['name'] ?? 'Product';
        final text = count > 1 ? '$name + ${count - 1} more' : name;
        return Text(
          text,
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 1.6,
            color: Colors.black54,
          ),
        );
      },
    );
  }
}
