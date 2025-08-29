import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:pasella/utils/show_toast.dart';

class SalesViewModel extends TransactionViewModel {
  late final StreamController<List<Sale>> _salesController;
  List<Sale> _lastEmittedSales = const [];
  double totalSales = 0.0;
  double totalCost = 0.0;
  double totalProfit = 0.0;
  int totalNumberOfSales = 0;
  String selectedPeriod = 'Today';
  bool productsLoaded = false;
  bool isTransactionLoading = false;

  SalesViewModel() {
    _salesController = StreamController<List<Sale>>.broadcast(
      sync: true,
      onListen: () {
        if (_lastEmittedSales.isNotEmpty) {
          _salesController.add(_lastEmittedSales);
        }
      },
    );

    loadProducts().then((_) {
      productsLoaded = true;
      _getSalesByDate(
          DateTime.now()); // Ensure only today's sales load initially
    });
  }

  Stream<List<Sale>> get sales => _salesController.stream;
  List<Sale> get cachedSales => _lastEmittedSales;

  void _emitSales(List<Sale> sales) {
    _lastEmittedSales = sales;
    if (!_salesController.isClosed) {
      _salesController.add(sales);
    }
  }

  Future<void> updateSelectedDate(DateTime date) async {
    selectedPeriod = DateFormat('yyyy-MM-dd').format(date);
    await _getSalesByDate(date);
    notifyListeners();
  }

  Future<void> updateSelectedDateRange(DateTime start, DateTime end) async {
    selectedPeriod = "Custom";
    await _getSalesByDateRange(start, end);
    notifyListeners();
  }

  Future<void> _getSalesByDate(DateTime date) async {
    try {
      DateTime startOfDay = DateTime(date.year, date.month, date.day);
      DateTime endOfDay = startOfDay.add(const Duration(days: 1));

      QuerySnapshot snapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('sales')
          .where('type', isEqualTo: 'Cash')
          .where('dateAdded',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('dateAdded', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('dateAdded', descending: true)
          .get();

      final sales = snapshot.docs
          .where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = (data['status'] ?? '').toString().toLowerCase();
            final paymentStatus =
                (data['paymentStatus'] ?? '').toString().toLowerCase();
            final paymentMethod =
                (data['paymentMethod'] ?? '').toString().toLowerCase();

            if (['cancelled', 'rejected'].contains(status)) {
              return false;
            }
            if (paymentMethod == 'bnpl' && paymentStatus != 'paid') {
              return false;
            }
            if (paymentMethod == 'cash' &&
                paymentStatus != '' &&
                paymentStatus != 'paid') {
              return false;
            }
            if (paymentStatus != '' && paymentStatus != 'paid') {
              return false;
            }
            return true;
          })
          .map(
            (doc) => Sale.fromMap(doc.data() as Map<String, dynamic>, doc.id),
          )
          .toList();

      // _salesController.add(sales);
      _emitSales(sales);
      _calculateSalesStats(sales);
    } catch (e) {
      print("Error fetching sales for selected date: $e");
    }
  }

  Future<void> _getSalesByDateRange(DateTime start, DateTime end) async {
    try {
      QuerySnapshot snapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('sales')
          .where('type', isEqualTo: 'Cash')
          .where('dateAdded', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('dateAdded',
              isLessThan: Timestamp.fromDate(end.add(const Duration(days: 1))))
          .orderBy('dateAdded', descending: true)
          .get();

      final sales = snapshot.docs
          .where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = (data['status'] ?? '').toString().toLowerCase();
            final paymentStatus =
                (data['paymentStatus'] ?? '').toString().toLowerCase();
            final paymentMethod =
                (data['paymentMethod'] ?? '').toString().toLowerCase();

            if (['cancelled', 'rejected'].contains(status)) {
              return false;
            }
            if (paymentMethod == 'bnpl' && paymentStatus != 'paid') {
              return false;
            }
            if (paymentMethod == 'cash' &&
                paymentStatus != '' &&
                paymentStatus != 'paid') {
              return false;
            }
            if (paymentStatus != '' && paymentStatus != 'paid') {
              return false;
            }
            return true;
          })
          .map(
            (doc) => Sale.fromMap(doc.data() as Map<String, dynamic>, doc.id),
          )
          .toList();

      _emitSales(sales);
      _calculateSalesStats(sales);
    } catch (e) {
      print("Error fetching sales by date range: $e");
    }
  }

  void refreshSales() {
    loadProducts().then((_) {
      productsLoaded = true;
      _getSales(selectedPeriod);
    });
  }

  Future<void> addSalesTransaction(BuildContext context) async {
    setLoading(true);

    if (!await isAnonymousGate(context)) {
      setLoading(false);
      return;
    }

    try {
      final amountEntered = double.tryParse(amountController.text);
      if (amountEntered == null || amountEntered <= 0) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          showSnackbar(context, 'Please check the amount entered.', Colors.red);
        });
        setLoading(false);
        return;
      }

      final salesData = {
        'amount': amountEntered,
        'type': 'Cash',
        'dateAdded': Timestamp.fromDate(
            DateFormat("dd-MM-yyyy HH:mm").parse(salesSelectedDate)),
        'products': selectedProducts,
        'remarks': remarksController.text,
        'status': 'paid',
        'paymentMethod': 'Cash',
        'paymentStatus': 'paid',
      };

      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          showSnackbar(
              context,
              'You\'re offline. Action queued and will complete when back online.',
              Colors.orange);
        });
      }

      final docRef = await firestore
          .collection('users')
          .doc(userId)
          .collection('sales')
          .add(salesData);

      currentSale = Sale(
        id: docRef.id,
        amount: amountEntered,
        type: 'Cash',
        products: selectedProducts,
        dateAdded: DateFormat("dd-MM-yyyy HH:mm").parse(salesSelectedDate),
      );

      for (var productId in selectedProducts.keys) {
        Product? product = products.firstWhere((p) => p.id == productId,
            orElse: () => Product());
        if (product.quantity != null) {
          await firestore
              .collection('users')
              .doc(userId)
              .collection('products')
              .doc(productId)
              .update({
            'quantity': product.quantity! - selectedProducts[productId]!
          });
        }
      }

      DocumentReference merchantRef =
          FirebaseFirestore.instance.collection('users').doc(userId);

      merchantRef.update({
        'lastSaleTransaction': salesData,
      });

      // Reset the form and navigate back
      resetFormAndNavigateAway(context);
    } catch (error) {
      print(error);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        showSnackbar(context, 'Error adding sale. Please retry.', Colors.red);
      });
    } finally {
      setLoading(false);
    }
  }

  Future<void> loadSaleDetails(Sale sale) async {
    isTransactionLoading = true;
    try {
      // Preload the amount for editing
      amountController.text = sale.amount.toString();

      // Preload the sale date for editing
      salesSelectedDate = DateFormat("dd-MM-yyyy HH:mm").format(sale.dateAdded);

      // Preload the selected products for editing
      selectedProducts = sale.products
          .map((productId, quantity) => MapEntry(productId, quantity));

      remarksController.text = sale.remarks ?? '';

      // Load product details for each selected product (optional, for displaying in the UI)
      for (var productId in sale.products.keys) {
        DocumentSnapshot productSnapshot = await firestore
            .collection('users')
            .doc(userId)
            .collection('products')
            .doc(productId)
            .get();

        if (productSnapshot.exists) {
          var productData = productSnapshot.data() as Map<String, dynamic>;
          Product product = Product.fromMap(productData, productId);
          products.add(
              product); // Add to the list of available products for reference
        }
      }

      notifyListeners();
    } catch (e) {
      print("Error loading sale details: $e");
    } finally {
      isTransactionLoading = false;
    }
  }

  Future<void> updateSale(
    Sale sale,
    double updatedAmount,
    Map<String, int> updatedProducts,
    BuildContext context,
  ) async {
    setLoading(true);

    if (!await isAnonymousGate(context)) {
      setLoading(false);
      return;
    }

    try {
      // Prepare the sale update data
      final salesData = {
        'amount': updatedAmount,
        'products': updatedProducts,
        'dateAdded': Timestamp.fromDate(
            DateFormat("dd-MM-yyyy HH:mm").parse(salesSelectedDate)),
        'remarks': remarksController.text,
      };

      // Check connectivity and notify if offline
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          showSnackbar(
              context,
              'You\'re offline. Action queued and will complete when back online.',
              Colors.orange);
        });
      }

      // Update sale in Firestore
      await firestore
          .collection('users')
          .doc(userId)
          .collection('sales')
          .doc(sale.id)
          .update(salesData);

      // Update product quantities by comparing original and updated values
      for (var productId in sale.products.keys) {
        final originalQuantity = sale.products[productId] ?? 0;
        final updatedQuantity = updatedProducts[productId] ?? 0;
        final quantityChange = updatedQuantity - originalQuantity;

        if (quantityChange != 0) {
          // Update product stock
          Product? product = products.firstWhere((p) => p.id == productId,
              orElse: () => Product());
          if (product.quantity != null) {
            await firestore
                .collection('users')
                .doc(userId)
                .collection('products')
                .doc(productId)
                .update({
              'quantity': product.quantity! - quantityChange,
            });
          }
        }
      }

      // Update last sale transaction on merchant document
      DocumentReference merchantRef = firestore.collection('users').doc(userId);
      await merchantRef.update({
        'lastSaleTransaction': salesData,
      });
      // Show success message and navigate back
      showSnackbar(context, 'Sale updated successfully!', Colors.green);

      refreshSales();

      // Reset the form and navigate back
      resetFormAndNavigateAway(context);
      Navigator.pop(context, true);
    } catch (error) {
      print("Error updating sale: $error");
      showSnackbar(context, 'Error updating sale. Please retry.', Colors.red);
    } finally {
      setLoading(false);
    }
  }

  Future<void> _getSales(String period) async {
    try {
      QuerySnapshot snapshot;

      DateTime now = DateTime.now();
      DateTime startOfDay = DateTime(now.year, now.month, now.day);
      DateTime endOfDay = startOfDay.add(const Duration(days: 1));
      DateTime startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      DateTime endOfWeek = startOfWeek.add(const Duration(days: 7));
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

      _salesController.add(sales);

      // Ensure products are loaded before calculating stats
      if (productsLoaded) {
        _emitSales(sales);
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
    _salesController.close();
    super.dispose();
  }
}
