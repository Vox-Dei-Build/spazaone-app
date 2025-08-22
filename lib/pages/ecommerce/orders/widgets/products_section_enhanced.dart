// lib/features/orders/widgets/products_section_enhanced.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'product_card_enhanced.dart';
import 'section.dart';

class ProductsSectionEnhanced extends StatelessWidget {
  const ProductsSectionEnhanced({
    super.key,
    required this.items,
    required this.fallbackUserId,
  });

  final List items;
  final String fallbackUserId;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    if (items.isEmpty) {
      return const Section(
        title: 'Products',
        child: Text('No products associated with this order.'),
      );
    }

    return Section(
      title: 'Products',
      child: Column(
        children: items.map<Widget>((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final productId =
              (map['productId'] ?? map['id'] ?? map['productID'] ?? '')
                  .toString();
          final quantity = map['quantity'] ?? map['qty'] ?? 0;
          final lineTotal = (map['lineTotal'] ?? map['total'] ?? 0);
          final inlineName = (map['name'] ?? map['productName'])?.toString();
          final inlinePrice = map['price'] ?? map['sellingPrice'];

          if (productId.isEmpty) {
            return ProductCardEnhanced(
              productName: inlineName ?? 'Unknown product',
              quantity: quantity,
              unitPrice: _num(inlinePrice),
              imageUrl: null,
              lineTotal: lineTotal is num ? lineTotal.toDouble() : null,
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
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                );
              }
              String? imageUrl;
              String name = inlineName ?? 'Unnamed product';
              double unitPrice = 0;

              if (snap.hasData && snap.data!.exists) {
                final data = snap.data!.data() as Map<String, dynamic>;
                name = (data['name'] ?? name).toString();
                unitPrice = _num(data['sellingPrice'] ?? inlinePrice);
                final images = data['images'];
                if (data['imageUrl'] is String) {
                  imageUrl = data['imageUrl'];
                } else if (images is List &&
                    images.isNotEmpty &&
                    images.first is String) {
                  imageUrl = images.first as String;
                } else if (data['photoUrl'] is String) {
                  imageUrl = data['photoUrl'];
                } else if (data['thumbnail'] is String) {
                  imageUrl = data['thumbnail'];
                }
              } else {
                unitPrice = _num(inlinePrice);
              }

              return ProductCardEnhanced(
                productName: name,
                quantity: quantity,
                unitPrice: unitPrice,
                imageUrl: imageUrl,
                lineTotal: lineTotal is num ? lineTotal.toDouble() : null,
              );
            },
          );
        }).toList(),
      ),
    );
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
