import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/models/stock/product_model.dart';

class GlobalSearchViewModel extends ChangeNotifier {
  final String userId;
  final Stream<List<Product>>? _productsStreamOverride;
  String searchQuery = '';
  bool isGroupSearch = false;
  String? groupName;
  List<Product> searchResults = [];
  StreamSubscription<List<Product>>? _productsSubscription;
  List<Product> _allProducts = const [];
  bool _disposed = false;

  GlobalSearchViewModel({
    Stream<List<Product>>? productsStream,
    String? userId,
  })  : userId = userId ?? StoreSession.instance.storeId,
        _productsStreamOverride = productsStream;

  void updateSearchQuery(String query,
      {bool isGroupSearch = false, String? groupName}) {
    searchQuery = query.toLowerCase();
    this.isGroupSearch = isGroupSearch;
    this.groupName = groupName;
    searchProducts();
  }

  void searchProducts() {
    if (searchQuery.isEmpty) {
      searchResults = [];
      if (!_disposed) notifyListeners();
      return;
    }

    if (_productsSubscription != null) {
      _applySearch();
      return;
    }

    final productsStream = _productsStreamOverride ??
        FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('products')
            .snapshots()
            .map(
              (snapshot) => snapshot.docs
                  .map((doc) => Product.fromMap(doc.data(), doc.id))
                  .toList(growable: false),
            );
    _productsSubscription = productsStream.listen((products) {
      if (_disposed) return;
      _allProducts = products;
      _applySearch();
    });
  }

  void _applySearch() {
    if (_disposed) return;
    searchResults = _allProducts.where((product) {
      final matchesName =
          product.name?.toLowerCase().contains(searchQuery) ?? false;
      final matchesGroup = !isGroupSearch || product.group == groupName;
      return matchesName && matchesGroup;
    }).toList(growable: false);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _productsSubscription?.cancel();
    super.dispose();
  }
}
