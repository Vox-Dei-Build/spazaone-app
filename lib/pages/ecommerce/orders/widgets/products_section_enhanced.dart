// lib/features/orders/widgets/products_section_enhanced.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/spaza_shimmer.dart';
import 'product_card_enhanced.dart';
import 'section.dart';

typedef OrderProductsLoader = Future<Map<String, Map<String, dynamic>>>
    Function(
  String storeId,
  List<String> productIds,
);

class ProductsSectionEnhanced extends StatefulWidget {
  const ProductsSectionEnhanced({
    super.key,
    required this.items,
    required this.fallbackUserId,
    this.productsLoader,
  });

  final List items;
  final String fallbackUserId;
  final OrderProductsLoader? productsLoader;

  @override
  State<ProductsSectionEnhanced> createState() =>
      _ProductsSectionEnhancedState();
}

class _ProductsSectionEnhancedState extends State<ProductsSectionEnhanced> {
  late List<String> _productIds;
  late Future<Map<String, Map<String, dynamic>>> _productsFuture;

  @override
  void initState() {
    super.initState();
    _productIds = _idsFrom(widget.items);
    _productsFuture = _loadProducts();
  }

  @override
  void didUpdateWidget(covariant ProductsSectionEnhanced oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIds = _idsFrom(widget.items);
    if (oldWidget.fallbackUserId != widget.fallbackUserId ||
        oldWidget.productsLoader != widget.productsLoader ||
        !listEquals(_productIds, nextIds)) {
      _productIds = nextIds;
      _productsFuture = _loadProducts();
    }
  }

  List<String> _idsFrom(List items) {
    final ids = items
        .whereType<Map>()
        .map((item) =>
            (item['productId'] ?? item['id'] ?? item['productID'] ?? '')
                .toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    return ids;
  }

  Future<Map<String, Map<String, dynamic>>> _loadProducts() {
    final override = widget.productsLoader;
    if (override != null) {
      return override(widget.fallbackUserId, _productIds);
    }
    return _fetchProducts(widget.fallbackUserId, _productIds);
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProducts(
    String storeId,
    List<String> productIds,
  ) async {
    if (storeId.isEmpty || productIds.isEmpty) return const {};
    final products = <String, Map<String, dynamic>>{};
    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(storeId)
        .collection('products');
    const chunkSize = 30;
    for (var start = 0; start < productIds.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, productIds.length);
      final chunk = productIds.sublist(start, end);
      final snapshot =
          await collection.where(FieldPath.documentId, whereIn: chunk).get();
      for (final document in snapshot.docs) {
        products[document.id] = document.data();
      }
    }
    return products;
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    if (widget.items.isEmpty) {
      return const Section(
        title: 'Products',
        child: Text('No products associated with this order.'),
      );
    }

    return Section(
      title: 'Products',
      child: FutureBuilder<Map<String, Map<String, dynamic>>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _productIds.isNotEmpty) {
            return const SpazaShimmer(
              semanticsLabel: 'Loading order products',
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SpazaSkeletonLine(widthFactor: .58, height: 14),
                    SizedBox(height: 10),
                    SpazaSkeletonLine(widthFactor: .34, height: 11),
                    SizedBox(height: 18),
                    SpazaSkeletonLine(widthFactor: .66, height: 14),
                    SizedBox(height: 10),
                    SpazaSkeletonLine(widthFactor: .40, height: 11),
                  ],
                ),
              ),
            );
          }
          final products = snapshot.data ?? const {};
          return Column(
            children: widget.items.map<Widget>((item) {
              final map = Map<String, dynamic>.from(item as Map);
              final productId =
                  (map['productId'] ?? map['id'] ?? map['productID'] ?? '')
                      .toString();
              final quantity = map['quantity'] ?? map['qty'] ?? 0;
              final rawLineTotal = map['lineTotal'] ?? map['total'];
              final inlineName =
                  (map['name'] ?? map['productName'])?.toString();
              final inlinePrice = map['price'] ?? map['sellingPrice'];

              if (productId.isEmpty) {
                final unitPrice = _num(inlinePrice);
                return ProductCardEnhanced(
                  productName: inlineName ?? 'Unknown product',
                  quantity: quantity,
                  unitPrice: unitPrice,
                  imageUrl: null,
                  lineTotal: _lineTotal(rawLineTotal, unitPrice, quantity),
                );
              }

              String? imageUrl;
              String name = inlineName ?? 'Unnamed product';
              double unitPrice = _num(inlinePrice);
              final data = products[productId];
              if (data != null) {
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
              }

              return ProductCardEnhanced(
                productName: name,
                quantity: quantity,
                unitPrice: unitPrice,
                imageUrl: imageUrl,
                lineTotal: _lineTotal(rawLineTotal, unitPrice, quantity),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  double _lineTotal(dynamic rawLineTotal, double unitPrice, dynamic quantity) {
    final explicit = _num(rawLineTotal);
    if (explicit > 0) return explicit;
    final qty = quantity is num ? quantity.toDouble() : _num(quantity);
    return unitPrice * qty;
  }
}
