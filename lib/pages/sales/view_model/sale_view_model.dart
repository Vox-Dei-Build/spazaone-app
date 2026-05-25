import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/review_prompt_service.dart';
import 'package:pasella/services/telemetry_service.dart';
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
    // PAS-SALES-SHIMMER: single-subscription controller so the very
    // first emission — which can fire before `SalesList`'s
    // StreamBuilder subscribes — is buffered and delivered the
    // moment the listener attaches. A broadcast controller drops
    // pre-subscription events, which left the shimmer stuck on
    // first render whenever the day had no sales (the empty-result
    // case the previous `onListen` replay explicitly skipped).
    // Originally introduced by 1677999; preserved here on the
    // assumption that only `SalesList` subscribes to `.sales`. Any
    // additional subscriber must use the `.listenable`/cached
    // surfaces instead, or this needs to flip back to broadcast
    // with a correct replay (cf. commit 1677999 follow-ups).
    _salesController = StreamController<List<Sale>>(sync: true);

    // Products feed the per-line cost/profit math used by
    // `_calculateSalesStats`; load them once on construction so
    // the page-driven `updateSelectedDate` call below sees a
    // populated catalog. The per-date Firestore fetch itself is
    // owned by the page (`_SalesPageState.initState` schedules a
    // post-frame `updateSelectedDate`) so we deliberately do NOT
    // also kick off `_getSalesByDate` here — doing so used to
    // race the page-driven fetch and let one emission land on a
    // controller with no listener.
    loadProducts().then((_) {
      productsLoaded = true;
      notifyListeners();
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
          .where(
            'dateAdded',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
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
            if ([
              'awaiting_collection',
              'pending_merchant_review',
              'accepted',
            ].contains(status) &&
                paymentStatus != 'paid') {
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
    } catch (e, stack) {
      // Surface to Crashlytics but always emit so the
      // `StreamBuilder` leaves `ConnectionState.waiting` — otherwise
      // a transient Firestore failure on first load pins the
      // shimmer up forever.
      CrashService.instance
          .recordNonFatal(e, stack, reason: 'sales: fetchByDate');
      _emitSales(const []);
      _calculateSalesStats(const []);
    }
  }

  Future<void> _getSalesByDateRange(DateTime start, DateTime end) async {
    try {
      QuerySnapshot snapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('sales')
          .where('type', isEqualTo: 'Cash')
          .where(
            'dateAdded',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start),
          )
          .where(
            'dateAdded',
            isLessThan: Timestamp.fromDate(
              end.add(const Duration(days: 1)),
            ),
          )
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
            if ([
              'awaiting_collection',
              'pending_merchant_review',
              'accepted',
            ].contains(status) &&
                paymentStatus != 'paid') {
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
    } catch (e, stack) {
      CrashService.instance
          .recordNonFatal(e, stack, reason: 'sales: fetchByDateRange');
      _emitSales(const []);
      _calculateSalesStats(const []);
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
          DateFormat("dd-MM-yyyy HH:mm").parse(salesSelectedDate),
        ),
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
            Colors.orange,
          );
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
        Product? product = products.firstWhere(
          (p) => p.id == productId,
          orElse: () => Product(),
        );
        if (product.quantity != null) {
          await firestore
              .collection('users')
              .doc(userId)
              .collection('products')
              .doc(productId)
              .update({
            'quantity': product.quantity! - selectedProducts[productId]!,
          });
        }
      }

      DocumentReference merchantRef =
          FirebaseFirestore.instance.collection('users').doc(userId);

      merchantRef.update({'lastSaleTransaction': salesData});

      // Cash sale committed. customerIsExisting is always false because the
      // cash-sale flow does not bind to a customer document; credit sales
      // (BNPL on ledger) fire the same event from add_credit_view_model with
      // customerIsExisting: true.
      await TelemetryService.instance.capture(
        SaleCompleted(
          amountBucket: amountBucketZAR(amountEntered),
          isCredit: false,
          customerIsExisting: false,
        ),
      );

      // PAS-GROWTH: a completed cash sale is the strongest "the app just
      // worked for me" moment in the ledger flow. Hand it to the review
      // service which decides whether to actually surface the OS prompt
      // (gated by a 3-trigger minimum, 2-day install age and 90-day
      // cooldown -- see ReviewPromptService for full rules). Fire-and-
      // forget so review logic can never block the navigator pop below.
      // ignore: unawaited_futures
      ReviewPromptService.instance.maybePrompt(
        ReviewTrigger.saleCompletedCash,
      );

      if (context.mounted) {
        final rootMessenger = ScaffoldMessenger.maybeOf(
              Navigator.of(context, rootNavigator: true).context,
            ) ??
            ScaffoldMessenger.maybeOf(context);
        resetForm();
        rootMessenger?.hideCurrentSnackBar();
        rootMessenger?.showSnackBar(
          const SnackBar(
            content: Text('Sale added successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (error, st) {
      await CrashService.instance.recordNonFatal(
        error,
        st,
        reason: 'addSalesTransaction failed',
      );
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
      selectedProducts = sale.products.map(
        (productId, quantity) => MapEntry(productId, quantity),
      );

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
            product,
          ); // Add to the list of available products for reference
        }
      }

      notifyListeners();
    } catch (e) {
      print("Error loading sale details: $e");
    } finally {
      isTransactionLoading = false;
      // Reset the dirty-tracking baseline so the unsaved-changes guard
      // doesn't fire just because we populated the form with the
      // existing sale's values after construction.
      markPristine(force: true);
      notifyListeners();
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
          DateFormat("dd-MM-yyyy HH:mm").parse(salesSelectedDate),
        ),
        'remarks': remarksController.text,
      };

      // Check connectivity and notify if offline
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          showSnackbar(
            context,
            'You\'re offline. Action queued and will complete when back online.',
            Colors.orange,
          );
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
          Product? product = products.firstWhere(
            (p) => p.id == productId,
            orElse: () => Product(),
          );
          if (product.quantity != null) {
            await firestore
                .collection('users')
                .doc(userId)
                .collection('products')
                .doc(productId)
                .update({'quantity': product.quantity! - quantityChange});
          }
        }
      }

      // Update last sale transaction on merchant document
      DocumentReference merchantRef = firestore.collection('users').doc(userId);
      await merchantRef.update({'lastSaleTransaction': salesData});
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

  /// Deletes a previously committed sale and rolls back the product
  /// stock that was decremented at the time of the sale. Caller (the
  /// form scaffold) handles the destructive confirmation prompt.
  Future<void> deleteSale(BuildContext context, Sale sale) async {
    if (isLoading) return;
    setLoading(true);
    try {
      // Roll stock back before deleting so the inventory adjustment
      // survives even if the delete write fails afterwards.
      for (final entry in sale.products.entries) {
        final productId = entry.key;
        final qty = entry.value;
        if (qty <= 0) continue;
        final product = products.firstWhere(
          (p) => p.id == productId,
          orElse: () => Product(),
        );
        if (product.quantity != null) {
          await firestore
              .collection('users')
              .doc(userId)
              .collection('products')
              .doc(productId)
              .update({'quantity': product.quantity! + qty});
        }
      }

      await firestore
          .collection('users')
          .doc(userId)
          .collection('sales')
          .doc(sale.id)
          .delete();

      refreshSales();

      if (context.mounted) {
        showSnackbar(context, 'Sale deleted.', Colors.green);
        SchedulerBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pop(true);
        });
      }
    } catch (error) {
      print("Error deleting sale: $error");
      if (context.mounted) {
        showSnackbar(context, 'Error deleting sale. Please retry.', Colors.red);
      }
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
      DateTime startOfQuarter = DateTime(
        now.year,
        (currentQuarter - 1) * 3 + 1,
        1,
      );
      DateTime endOfQuarter = DateTime(now.year, currentQuarter * 3 + 1, 1);

      if (period == 'Today') {
        snapshot = await firestore
            .collection('users')
            .doc(userId)
            .collection('sales')
            .where(
              'dateAdded',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
            )
            .where('dateAdded', isLessThan: Timestamp.fromDate(endOfDay))
            .orderBy('dateAdded', descending: true)
            .get();
      } else if (period == 'Week') {
        snapshot = await firestore
            .collection('users')
            .doc(userId)
            .collection('sales')
            .where(
              'dateAdded',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek),
            )
            .where('dateAdded', isLessThan: Timestamp.fromDate(endOfWeek))
            .orderBy('dateAdded', descending: true)
            .get();
      } else if (period == 'Month') {
        snapshot = await firestore
            .collection('users')
            .doc(userId)
            .collection('sales')
            .where(
              'dateAdded',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
            )
            .where('dateAdded', isLessThan: Timestamp.fromDate(endOfMonth))
            .orderBy('dateAdded', descending: true)
            .get();
      } else if (period == 'Quarter') {
        snapshot = await firestore
            .collection('users')
            .doc(userId)
            .collection('sales')
            .where(
              'dateAdded',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfQuarter),
            )
            .where(
              'dateAdded',
              isLessThan: Timestamp.fromDate(endOfQuarter),
            )
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
            (doc) => Sale.fromMap(doc.data() as Map<String, dynamic>, doc.id),
          )
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
        final product = products.firstWhere(
          (p) => p.id == entry.key,
          orElse: () => Product(),
        );
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
