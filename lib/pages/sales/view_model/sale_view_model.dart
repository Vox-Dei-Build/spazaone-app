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
import 'package:pasella/services/payment_receipt_tracker.dart';
import 'package:pasella/services/review_prompt_service.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:pasella/utils/show_toast.dart';

class SalesViewModel extends TransactionViewModel {
  late final StreamController<List<Sale>> _salesController;
  List<Sale> _lastEmittedSales = const [];
  // Tracks whether at least one [_emitSales] has occurred so that
  // [onListen] only replays after we actually have data. Without this,
  // the very first cold-start subscriber would receive the default
  // empty list and the shimmer would flicker into an empty-state
  // before the first Firestore fetch resolved.
  bool _hasEmitted = false;
  double totalSales = 0.0;
  double totalStockAmount = 0.0;
  double totalCost = 0.0;
  double totalProfit = 0.0;
  int totalNumberOfSales = 0;
  String selectedPeriod = 'Today';
  bool productsLoaded = false;
  bool isTransactionLoading = false;

  SalesViewModel() {
    // PAS-SALES-SHIMMER: broadcast controller so the StreamBuilder in
    // SalesList can be unmounted (toggling the Cash/Online segmented
    // button on SalesPage) and re-subscribed without throwing
    // "Bad state: Stream has already been listened to.". A
    // single-subscription controller crashes the second listener.
    //
    // We preserve "deliver the latest snapshot the moment the listener
    // attaches" — the reason this used to be single-subscription — by:
    //   1. caching every emission in [_lastEmittedSales] (also used as
    //      `initialData:` on the StreamBuilder so remounts never sit
    //      in `ConnectionState.waiting`), and
    //   2. replaying that cache from [onListen] when a subscriber
    //      attaches AND we already have data ([_hasEmitted] guard).
    //      The guard is what prevents cold-start subscribers from
    //      flashing an empty list before the first Firestore fetch
    //      resolves.
    //
    // The controller is async (no `sync: true`) so the [onListen]
    // replay is delivered on a microtask after `listen()` returns.
    // A sync controller would deliver mid-`initState` and trigger a
    // forbidden `setState` during build.
    _salesController = StreamController<List<Sale>>.broadcast(
      onListen: () {
        if (_hasEmitted && !_salesController.isClosed) {
          _salesController.add(_lastEmittedSales);
        }
      },
    );

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
    _hasEmitted = true;
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

      final stockAmountEntered = _parseStockAmount();
      if (stockAmountEntered == null) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          showSnackbar(
            context,
            'Please check the stock amount entered.',
            Colors.red,
          );
        });
        setLoading(false);
        return;
      }

      final salesData = {
        'amount': amountEntered,
        'stockAmount': stockAmountEntered,
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
        stockAmount: stockAmountEntered,
        type: 'Cash',
        products: selectedProducts,
        dateAdded: DateFormat("dd-MM-yyyy HH:mm").parse(salesSelectedDate),
      );

      // The paid sale is durable at this point. Record its payment before
      // ancillary stock updates so an inventory-write failure cannot erase
      // the conversion from internal reporting.
      await PaymentReceiptTracker.instance.capture(
        PaymentReceived(
          transactionId: 'cash_sale:${docRef.id}',
          amountBucket: amountBucketZAR(amountEntered),
          source: 'cash_sale',
          method: 'cash',
        ),
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
          hasProducts: selectedProducts.isNotEmpty,
          productCountBucket: productCountBucket(selectedProducts.length),
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
      stockAmountController.text =
          sale.stockAmount == 0 ? '' : sale.stockAmount.toString();

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
      final updatedStockAmount = _parseStockAmount();
      if (updatedStockAmount == null) {
        showSnackbar(
          context,
          'Please check the stock amount entered.',
          Colors.red,
        );
        return;
      }

      // Prepare the sale update data
      final salesData = {
        'amount': updatedAmount,
        'stockAmount': updatedStockAmount,
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

      // Always emit through [_emitSales] so [_lastEmittedSales] and
      // [_hasEmitted] stay in sync with what subscribers see. Stats
      // still wait on [productsLoaded] because cost/profit math needs
      // the product catalog; the list itself can render without it.
      _emitSales(sales);
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
    final salesStockTotals = SalesStockTotals.fromSales(sales);
    double totalCostAmount = 0.0;

    for (var sale in sales) {
      for (var entry in sale.products.entries) {
        final product = products.firstWhere(
          (p) => p.id == entry.key,
          orElse: () => Product(),
        );
        totalCostAmount += (product.cost ?? 0) * entry.value;
      }
    }

    totalSales = salesStockTotals.salesAmount;
    totalStockAmount = salesStockTotals.stockAmount;
    totalCost = totalCostAmount;
    totalProfit = salesStockTotals.salesAmount - totalCostAmount;
    totalNumberOfSales = salesStockTotals.entryCount;

    notifyListeners();
  }

  /// Parses the optional amount spent buying stock. Empty values are stored
  /// as zero so sales created before this field existed remain equivalent.
  /// A null result means the user supplied an invalid or negative value.
  double? _parseStockAmount() {
    final input = stockAmountController.text.trim();
    if (input.isEmpty) return 0.0;
    final value = double.tryParse(input);
    if (value == null || value < 0) return null;
    return value;
  }

  @override
  void dispose() {
    _salesController.close();
    super.dispose();
  }
}
