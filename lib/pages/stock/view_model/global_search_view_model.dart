import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/models/stock/product_model.dart';

class GlobalSearchViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String userId;
  String searchQuery = '';
  bool isGroupSearch = false;
  String? groupName;
  List<Product> searchResults = [];
  StreamSubscription<QuerySnapshot>? _subscription;

  GlobalSearchViewModel()
      : userId = FirebaseAuth.instance.currentUser?.uid ?? '';

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
      notifyListeners();
      _subscription?.cancel();
      return;
    }

    _subscription?.cancel();
    _subscription = _firestore
        .collection('users')
        .doc(userId)
        .collection('products')
        .snapshots()
        .listen((snapshot) {
      searchResults = snapshot.docs
          .map((doc) =>
              Product.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .where((product) =>
              (product.name?.toLowerCase().contains(searchQuery) ?? false))
          .toList();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
