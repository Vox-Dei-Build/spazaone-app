import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/models/stock/product_model.dart';

class SalesViewModel extends ChangeNotifier {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  StreamController<List<Sale>>? _salesController;
  double totalSales = 0.0;
  double totalCost = 0.0;
  double totalProfit = 0.0;
  int totalNumberOfSales = 0;
  String selectedPeriod = 'Today';
  List<Product> products = [];
  bool productsLoaded = false;

  SalesViewModel() {
    _salesController = StreamController<List<Sale>>.broadcast(sync: true);
    _loadProducts().then((_) {
      productsLoaded = true;
      _getSales(selectedPeriod);
    });
  }

  Stream<List<Sale>> get sales => _salesController!.stream;

  void updateSelectedPeriod(String period) {
    selectedPeriod = period;
    if (productsLoaded) {
      _getSales(selectedPeriod);
    } else {
      _loadProducts().then((_) {
        productsLoaded = true;
        _getSales(selectedPeriod);
      });
    }
    notifyListeners();
  }

  Future<void> _loadProducts() async {
    try {
      QuerySnapshot snapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('products')
          .get();
      products = snapshot.docs
          .map((doc) =>
              Product.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
      notifyListeners();
    } catch (e) {
      print("Error loading products: $e");
    }
  }

  Future<void> updateProduct(String productId, double newPrice) async {
    try {
      await firestore
          .collection('users')
          .doc(userId)
          .collection('products')
          .doc(productId)
          .update({'sellingPrice': newPrice});
      // Update the local product list
      int productIndex = products.indexWhere((p) => p.id == productId);
      if (productIndex != -1) {
        products[productIndex].sellingPrice = newPrice;
        notifyListeners(); // Ensure the listeners are notified to recalculate totals
      }
    } catch (e) {
      print("Error updating product: $e");
    }
  }

  void _getSales(String period) async {
    try {
      QuerySnapshot snapshot;

      DateTime now = DateTime.now();
      DateTime startOfDay = DateTime(now.year, now.month, now.day);
      DateTime endOfDay = startOfDay.add(Duration(days: 1));
      DateTime startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      DateTime endOfWeek = startOfWeek.add(Duration(days: 7));
      DateTime startOfMonth = DateTime(now.year, now.month, 1);
      DateTime endOfMonth = DateTime(now.year, now.month + 1, 1);
      int currentQuarter = ((now.month - 1) ~/ 3) + 1;
      DateTime startOfQuarter =
          DateTime(now.year, (currentQuarter - 1) * 3 + 1, 1);
      DateTime endOfQuarter = DateTime(now.year, currentQuarter * 3 + 1, 1);

      if (period == 'Today') {
        snapshot = await firestore
            .collection('users')
            .doc(userId)
            .collection('sales')
            .where('dateAdded',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('dateAdded', isLessThan: Timestamp.fromDate(endOfDay))
            .orderBy('dateAdded', descending: true)
            .get();
      } else if (period == 'Week') {
        snapshot = await firestore
            .collection('users')
            .doc(userId)
            .collection('sales')
            .where('dateAdded',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
            .where('dateAdded', isLessThan: Timestamp.fromDate(endOfWeek))
            .orderBy('dateAdded', descending: true)
            .get();
      } else if (period == 'Month') {
        snapshot = await firestore
            .collection('users')
            .doc(userId)
            .collection('sales')
            .where('dateAdded',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
            .where('dateAdded', isLessThan: Timestamp.fromDate(endOfMonth))
            .orderBy('dateAdded', descending: true)
            .get();
      } else if (period == 'Quarter') {
        snapshot = await firestore
            .collection('users')
            .doc(userId)
            .collection('sales')
            .where('dateAdded',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfQuarter))
            .where('dateAdded', isLessThan: Timestamp.fromDate(endOfQuarter))
            .orderBy('dateAdded', descending: true)
            .get();
      } else {
        snapshot = await firestore
            .collection('users')
            .doc(userId)
            .collection('sales')
            .orderBy('dateAdded', descending: true)
            .get();
      }

      final sales = snapshot.docs
          .map(
              (doc) => Sale.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      _salesController!.add(sales);

      // Ensure products are loaded before calculating stats
      if (productsLoaded) {
        _calculateSalesStats(sales);
      } else {
        print("Products not loaded yet.");
      }
    } catch (e) {
      print("Error fetching sales: $e");
    }
  }

  void _calculateSalesStats(List<Sale> sales) {
    double totalSalesAmount = 0.0;
    double totalCostAmount = 0.0;
    int totalSalesCount = sales.length;

    for (var sale in sales) {
      totalSalesAmount += sale.amount;
      for (var entry in sale.products.entries) {
        final product = products.firstWhere((p) => p.id == entry.key,
            orElse: () => Product());
        totalCostAmount += (product.cost ?? 0) * entry.value;
      }
    }

    totalSales = totalSalesAmount;
    totalCost = totalCostAmount;
    totalProfit = totalSalesAmount - totalCostAmount;
    totalNumberOfSales = totalSalesCount;

    notifyListeners();
  }

  @override
  void dispose() {
    _salesController?.close();
    _salesController = null;
    super.dispose();
  }
}
