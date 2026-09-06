import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/pages/sales/view_model/recorded_sales_reader.dart';
import 'package:pasella/models/sales/stock_invoice_attachment.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/payment_receipt_tracker.dart';
import 'package:pasella/services/review_prompt_service.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/services/stock_invoice_attachment_service.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:pasella/utils/show_toast.dart';

class SalesViewModel extends TransactionViewModel {
  late final StreamController<List<Sale>> _salesController;
  late final RecordedSalesReader recordedSalesReader;
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

  final StockInvoiceAttachmentService _stockInvoiceService;
  final List<StockInvoiceDraft> stockInvoiceDrafts = [];
  final Set<String> _removedStockInvoicePaths = {};
  String? _pristineStockInvoiceFingerprint;

  SalesViewModel({StockInvoiceAttachmentService? stockInvoiceService})
      : _stockInvoiceService =
            stockInvoiceService ?? StockInvoiceAttachmentService() {
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

    recordedSalesReader = RecordedSalesReader(
      query: _queryRecordedSales,
      onLoaded: (sales) {
        _emitSales(sales);
        _calculateSalesStats(sales);
      },
      onError: (error, stack) {
        CrashService.instance.recordNonFatal(
          error,
          stack,
          reason: 'sales: fetchRecordedSales',
        );
      },
    )..addListener(notifyListeners);

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

  @override
  bool get isDirty =>
      super.isDirty ||
      (_pristineStockInvoiceFingerprint != null &&
          _stockInvoiceFingerprint != _pristineStockInvoiceFingerprint);

  String get _stockInvoiceFingerprint => stockInvoiceDrafts
      .map(
        (draft) =>
            draft.localFile?.path ?? draft.attachment?.storagePath ?? 'missing',
      )
      .join('|');

  @override
  void markPristine({bool force = false}) {
    super.markPristine(force: force);
    if (force || _pristineStockInvoiceFingerprint == null) {
      _pristineStockInvoiceFingerprint = _stockInvoiceFingerprint;
    }
  }

  Future<void> addStockInvoice(BuildContext context) async {
    if (stockInvoiceDrafts.length >=
        StockInvoiceAttachmentService.maxAttachments) {
      showSnackbar(
        context,
        'You can attach up to 3 invoice files.',
        Colors.orange,
      );
      return;
    }
    final file = await _stockInvoiceService.pickAndPrepare(context);
    if (file == null || isDisposed) return;
    try {
      await StockInvoiceAttachmentService.validateFile(file);
    } on StockInvoiceValidationException catch (error) {
      if (context.mounted) showSnackbar(context, error.message, Colors.orange);
      return;
    }
    stockInvoiceDrafts.add(StockInvoiceDraft.local(file));
    notifyListeners();
  }

  Future<void> replaceStockInvoice(BuildContext context, int index) async {
    if (index < 0 || index >= stockInvoiceDrafts.length) return;
    final file = await _stockInvoiceService.pickAndPrepare(context);
    if (file == null || isDisposed) return;
    try {
      await StockInvoiceAttachmentService.validateFile(file);
    } on StockInvoiceValidationException catch (error) {
      if (context.mounted) showSnackbar(context, error.message, Colors.orange);
      return;
    }
    final previousAttachment = stockInvoiceDrafts[index].attachment;
    stockInvoiceDrafts[index] = StockInvoiceDraft.local(file)
      ..attachment = previousAttachment;
    notifyListeners();
  }

  Future<void> removeStockInvoice(int index) async {
    if (index < 0 || index >= stockInvoiceDrafts.length) return;
    final removed = stockInvoiceDrafts.removeAt(index);
    final previousPath = removed.attachment?.storagePath;
    if (previousPath != null) _removedStockInvoicePaths.add(previousPath);
    notifyListeners();
  }

  Future<void> retryStockInvoice(int index) async {
    if (index < 0 || index >= stockInvoiceDrafts.length) return;
    final draft = stockInvoiceDrafts[index];
    if (draft.localFile == null) return;
    draft
      ..status = StockInvoiceDraftStatus.ready
      ..errorMessage = null
      ..progress = 0;
    notifyListeners();
  }

  Future<Uint8List?> loadStockInvoicePreview(String storagePath) =>
      _stockInvoiceService.loadAttachment(storagePath);

  Future<_StockInvoiceUploadResult> _uploadStockInvoices(String saleId) async {
    final attachments = <StockInvoiceAttachment>[];
    final newlyUploadedPaths = <String>[];
    var failureCount = 0;

    for (final draft in stockInvoiceDrafts) {
      final localFile = draft.localFile;
      if (localFile == null && draft.attachment != null) {
        attachments.add(draft.attachment!);
        continue;
      }
      if (localFile == null) continue;
      final replacedAttachment = draft.attachment;

      draft
        ..status = StockInvoiceDraftStatus.uploading
        ..errorMessage = null
        ..progress = 0;
      notifyListeners();
      try {
        final attachment = await _stockInvoiceService.upload(
          storeId: userId,
          saleId: saleId,
          file: localFile,
          onProgress: (value) {
            draft.progress = value;
            notifyListeners();
          },
        );
        draft
          ..attachment = attachment
          ..localFile = null
          ..status = StockInvoiceDraftStatus.uploaded
          ..progress = 1;
        attachments.add(attachment);
        newlyUploadedPaths.add(attachment.storagePath);
        final replacedPath = replacedAttachment?.storagePath;
        if (replacedPath != null && replacedPath != attachment.storagePath) {
          _removedStockInvoicePaths.add(replacedPath);
        }
      } catch (_) {
        failureCount++;
        if (replacedAttachment != null) attachments.add(replacedAttachment);
        draft
          ..status = StockInvoiceDraftStatus.failed
          ..errorMessage =
              'Could not attach this file. The sale can still be saved.'
          ..progress = 0;
      }
      notifyListeners();
    }

    return _StockInvoiceUploadResult(
      attachments: attachments,
      newlyUploadedPaths: newlyUploadedPaths,
      failureCount: failureCount,
    );
  }

  Future<void> _deleteStockInvoicePaths(Iterable<String> paths) async {
    for (final path in paths.toSet()) {
      try {
        await _stockInvoiceService.deletePath(path);
      } catch (error, stack) {
        await CrashService.instance.recordNonFatal(
          error,
          stack,
          reason: 'stock invoice cleanup failed',
        );
      }
    }
  }

  List<_StockInvoiceDraftSnapshot> _snapshotStockInvoiceDrafts() =>
      stockInvoiceDrafts
          .map(
            (draft) => _StockInvoiceDraftSnapshot(
              draft: draft,
              localFile: draft.localFile,
              attachment: draft.attachment,
              status: draft.status,
              errorMessage: draft.errorMessage,
              progress: draft.progress,
            ),
          )
          .toList(growable: false);

  void _restoreStockInvoiceDraftsAfterWriteFailure(
    Iterable<_StockInvoiceDraftSnapshot> snapshots,
  ) {
    for (final snapshot in snapshots) {
      snapshot.draft
        ..localFile = snapshot.localFile
        ..attachment = snapshot.attachment
        ..status = snapshot.localFile == null
            ? snapshot.status
            : StockInvoiceDraftStatus.failed
        ..errorMessage = snapshot.localFile == null
            ? snapshot.errorMessage
            : 'The sale was not saved. Retry when you save again.'
        ..progress = snapshot.localFile == null ? snapshot.progress : 0;
    }
    notifyListeners();
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
    final start = DateTime(date.year, date.month, date.day);
    await recordedSalesReader.load(start, start.add(const Duration(days: 1)));
  }

  Future<void> updateSelectedDateRange(DateTime start, DateTime end) async {
    selectedPeriod = 'Custom';
    // Preserve the existing range query's exclusive end-date convention.
    await recordedSalesReader.load(start, end.add(const Duration(days: 1)));
  }

  Future<List<Sale>> _queryRecordedSales(
    DateTime start,
    DateTime endExclusive,
  ) async {
    final snapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('sales')
        .where('type', isEqualTo: 'Cash')
        .where('dateAdded', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('dateAdded', isLessThan: Timestamp.fromDate(endExclusive))
        .orderBy('dateAdded', descending: true)
        .get();

    return snapshot.docs
        .where((doc) {
          final data = doc.data();
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
          (doc) => Sale.fromMap(doc.data(), doc.id),
        )
        .toList();
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

      final docRef =
          firestore.collection('users').doc(userId).collection('sales').doc();
      final invoiceSnapshots = _snapshotStockInvoiceDrafts();
      final invoiceResult = await _uploadStockInvoices(docRef.id);
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
        'stockInvoices':
            invoiceResult.attachments.map((item) => item.toMap()).toList(),
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

      try {
        await docRef.set(salesData);
      } catch (_) {
        await _deleteStockInvoicePaths(invoiceResult.newlyUploadedPaths);
        _restoreStockInvoiceDraftsAfterWriteFailure(invoiceSnapshots);
        rethrow;
      }

      currentSale = Sale(
        id: docRef.id,
        amount: amountEntered,
        stockAmount: stockAmountEntered,
        type: 'Cash',
        products: selectedProducts,
        dateAdded: DateFormat("dd-MM-yyyy HH:mm").parse(salesSelectedDate),
        stockInvoices: invoiceResult.attachments,
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
        final failedInvoiceCount = invoiceResult.failureCount;
        resetForm();
        rootMessenger?.hideCurrentSnackBar();
        rootMessenger?.showSnackBar(
          SnackBar(
            content: Text(
              failedInvoiceCount == 0
                  ? 'Sale added successfully.'
                  : 'Sale saved. $failedInvoiceCount invoice image could not be attached.',
            ),
            backgroundColor:
                failedInvoiceCount == 0 ? Colors.green : Colors.orange,
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
      stockInvoiceDrafts
        ..clear()
        ..addAll(sale.stockInvoices.map(StockInvoiceDraft.existing));
      _removedStockInvoicePaths.clear();

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

  Future<Sale?> updateSale(
    Sale sale,
    double updatedAmount,
    Map<String, int> updatedProducts,
    BuildContext context,
  ) async {
    setLoading(true);

    if (!await isAnonymousGate(context)) {
      setLoading(false);
      return null;
    }

    try {
      final updatedStockAmount = _parseStockAmount();
      if (updatedStockAmount == null) {
        showSnackbar(
          context,
          'Please check the stock amount entered.',
          Colors.red,
        );
        return null;
      }

      final invoiceSnapshots = _snapshotStockInvoiceDrafts();
      final invoiceResult = await _uploadStockInvoices(sale.id);
      final removedInvoicePaths = Set<String>.from(_removedStockInvoicePaths);
      // Prepare the sale update data
      final updatedDate =
          DateFormat("dd-MM-yyyy HH:mm").parse(salesSelectedDate);
      final updatedInvoiceAttachments = invoiceResult.attachments.toList(
        growable: false,
      );
      final salesData = {
        'amount': updatedAmount,
        'stockAmount': updatedStockAmount,
        'products': updatedProducts,
        'dateAdded': Timestamp.fromDate(updatedDate),
        'remarks': remarksController.text,
        'stockInvoices':
            updatedInvoiceAttachments.map((item) => item.toMap()).toList(),
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
      try {
        await firestore
            .collection('users')
            .doc(userId)
            .collection('sales')
            .doc(sale.id)
            .update(salesData);
      } catch (_) {
        await _deleteStockInvoicePaths(invoiceResult.newlyUploadedPaths);
        _restoreStockInvoiceDraftsAfterWriteFailure(invoiceSnapshots);
        rethrow;
      }
      await _deleteStockInvoicePaths(removedInvoicePaths);
      _removedStockInvoicePaths.clear();

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
      showSnackbar(
        context,
        invoiceResult.failureCount == 0
            ? 'Sale updated successfully!'
            : 'Sale updated. ${invoiceResult.failureCount} invoice image could not be attached.',
        invoiceResult.failureCount == 0 ? Colors.green : Colors.orange,
      );

      refreshSales();
      return Sale(
        id: sale.id,
        amount: updatedAmount,
        stockAmount: updatedStockAmount,
        type: sale.type,
        products: Map<String, int>.from(updatedProducts),
        dateAdded: updatedDate,
        remarks: remarksController.text.trim().isEmpty
            ? null
            : remarksController.text,
        stockInvoices: updatedInvoiceAttachments,
      );
    } catch (error) {
      print("Error updating sale: $error");
      showSnackbar(context, 'Error updating sale. Please retry.', Colors.red);
      return null;
    } finally {
      setLoading(false);
    }
  }

  /// Deletes a previously committed sale and rolls back the product
  /// stock that was decremented at the time of the sale. Caller (the
  /// form scaffold) handles the destructive confirmation prompt.
  Future<bool> deleteSale(BuildContext context, Sale sale) async {
    if (isLoading) return false;
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

      await _deleteStockInvoicePaths(
        sale.stockInvoices.map((item) => item.storagePath),
      );

      refreshSales();

      if (context.mounted) {
        showSnackbar(context, 'Sale deleted.', Colors.green);
      }
      return true;
    } catch (error) {
      print("Error deleting sale: $error");
      if (context.mounted) {
        showSnackbar(context, 'Error deleting sale. Please retry.', Colors.red);
      }
      return false;
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
  void resetForm() {
    super.resetForm();
    stockInvoiceDrafts.clear();
    _removedStockInvoicePaths.clear();
    _pristineStockInvoiceFingerprint = '';
    notifyListeners();
  }

  @override
  void dispose() {
    recordedSalesReader.dispose();
    _salesController.close();
    super.dispose();
  }
}

class _StockInvoiceUploadResult {
  const _StockInvoiceUploadResult({
    required this.attachments,
    required this.newlyUploadedPaths,
    required this.failureCount,
  });

  final List<StockInvoiceAttachment> attachments;
  final List<String> newlyUploadedPaths;
  final int failureCount;
}

class _StockInvoiceDraftSnapshot {
  const _StockInvoiceDraftSnapshot({
    required this.draft,
    required this.localFile,
    required this.attachment,
    required this.status,
    required this.errorMessage,
    required this.progress,
  });

  final StockInvoiceDraft draft;
  final File? localFile;
  final StockInvoiceAttachment? attachment;
  final StockInvoiceDraftStatus status;
  final String? errorMessage;
  final double progress;
}
