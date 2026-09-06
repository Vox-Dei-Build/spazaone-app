import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pasella/services/store_session.dart';
import 'package:intl/intl.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_details/product_details.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/utils/show_toast.dart';

/// Manual cash and Pay Later transactions move stock the merchant already
/// owns. Supplier-backed dropshipping listings must stay in the commerce-order
/// flow, where delivery, payment and fulfilment are captured safely.
List<Product> selectableManualTransactionProducts(
  Iterable<Product> products,
) =>
    products.where((product) => !product.isDropshipListing).toList();

class TransactionViewModel extends ChangeNotifier {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final String userId = StoreSession.instance.storeId;
  final TextEditingController amountController = TextEditingController();
  final TextEditingController stockAmountController = TextEditingController();
  final TextEditingController remarksController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  String salesSelectedDate = DateFormat(
    "dd-MM-yyyy HH:mm",
  ).format(DateTime.now());

  /// Mutates [selectedDate] and notifies listeners. Use this from the
  /// shared `DateRow` callback so the displayed date refreshes
  /// immediately and the dirty-tracking baseline picks up the change.
  void setSelectedDate(DateTime value) {
    selectedDate = value;
    notifyListeners();
  }

  /// Mutates [salesSelectedDate] (kept as a `dd-MM-yyyy HH:mm` string for
  /// backwards compat with the existing Firestore write paths) and
  /// notifies listeners.
  void setSalesSelectedDate(DateTime value) {
    salesSelectedDate = DateFormat("dd-MM-yyyy HH:mm").format(value);
    notifyListeners();
  }

  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  List<Product> products = [];
  List<Product> filteredProducts = [];
  Map<String, int> selectedProducts = {};

  /// Products surfaced as quick-add suggestions above the search tile in
  /// [ProductSelectionWidget]. Default implementation is empty; flows
  /// that have a customer binding (currently only AddCredit — cash
  /// sales carry no customerId) override this to return ranked
  /// previous-transaction picks. Empty list means "no suggestions
  /// surface" — the picker collapses gracefully.
  List<Product> get suggestedProducts => const [];

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  int currentPage = 0;
  int itemsPerPage = 5;
  Sale? currentSale;

  bool _isLoading = false;

  bool get isLoading => _isLoading;

  /// Snapshot of the controller values + selected products + dates taken
  /// the first time [markPristine] is called. Used by [isDirty] so the
  /// shared `TransactionFormScaffold` can prompt before discarding work.
  String? _pristineAmount;
  String? _pristineStockAmount;
  String? _pristineRemarks;
  Map<String, int>? _pristineProducts;
  DateTime? _pristineSelectedDate;
  String? _pristineSalesSelectedDate;

  /// Call after the form has been populated (Add: in the constructor;
  /// Edit: after the existing record loads). Subsequent calls are no-ops
  /// unless [force] is true, which Edit screens use after a successful
  /// load to reset the baseline.
  void markPristine({bool force = false}) {
    if (!force && _pristineAmount != null) return;
    _pristineAmount = amountController.text;
    _pristineStockAmount = stockAmountController.text;
    _pristineRemarks = remarksController.text;
    _pristineProducts = Map<String, int>.from(selectedProducts);
    _pristineSelectedDate = selectedDate;
    _pristineSalesSelectedDate = salesSelectedDate;
  }

  /// True when the user has edited any tracked field since the last
  /// [markPristine]. Drives the unsaved-changes guard in
  /// `TransactionFormScaffold`.
  bool get isDirty {
    if (_pristineAmount == null) return false;
    if (amountController.text != _pristineAmount) return true;
    if (stockAmountController.text != _pristineStockAmount) return true;
    if (remarksController.text != _pristineRemarks) return true;
    if (selectedDate != _pristineSelectedDate) return true;
    if (salesSelectedDate != _pristineSalesSelectedDate) return true;
    final originalProducts = _pristineProducts ?? const {};
    if (selectedProducts.length != originalProducts.length) return true;
    for (final entry in selectedProducts.entries) {
      if (originalProducts[entry.key] != entry.value) return true;
    }
    return false;
  }

  TransactionViewModel() {
    loadProducts();
    // Most Add* flows have empty controllers at construction, so this
    // captures an "empty" baseline. Edit* flows should call
    // `markPristine(force: true)` again after they finish loading the
    // existing record.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      markPristine();
    });
    amountController.addListener(notifyListeners);
    stockAmountController.addListener(notifyListeners);
    remarksController.addListener(notifyListeners);
  }

  Future<void> loadProducts() async {
    try {
      QuerySnapshot snapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('products')
          .get();
      products = selectableManualTransactionProducts(
        snapshot.docs.map(
          (doc) => Product.fromMap(doc.data() as Map<String, dynamic>, doc.id),
        ),
      );
      filteredProducts = products;

      notifyListeners();
    } catch (e) {
      print("Error loading products: $e");
    }
  }

  /// Resolve a usable [BuildContext] for showing SnackBars / pushing
  /// routes from view-model methods. Prefers the live context the
  /// caller passed in (which is always mounted by virtue of having
  /// just fired the action), and falls back to [scaffoldKey] only when
  /// the caller didn't have one. Returns `null` if neither is usable —
  /// callers must check before dereferencing.
  ///
  /// This exists because the previous `scaffoldKey.currentContext!`
  /// pattern silently NPEs when the key is detached from any live
  /// `Scaffold` (which happened during the `TransactionFormScaffold`
  /// migration in 7cd4126).
  BuildContext? _resolveContext(BuildContext? caller) {
    if (caller != null && caller.mounted) return caller;
    final fromKey = scaffoldKey.currentContext;
    if (fromKey != null && fromKey.mounted) return fromKey;
    return null;
  }

  SnackBarAction updateStockSnackBar(
    BuildContext context,
    String productId,
    int quantity,
    Product product,
  ) {
    return SnackBarAction(
      label: 'Update Stock',
      textColor: Colors.white,
      onPressed: () async {
        final navContext = _resolveContext(context);
        if (navContext == null) return;
        await Navigator.of(navContext).push(
          MaterialPageRoute(
            builder: (_) =>
                ProductDetailsPage(docID: productId, product: product),
          ),
        );
        // After navigating back, reload the products and check stock again
        await loadProducts();
        Product updatedProduct = products.firstWhere(
          (p) => p.id == productId,
          orElse: () => Product(),
        );
        if (updatedProduct.quantity != null && updatedProduct.quantity! > 0) {
          addProduct(context, productId, quantity);
        } else {
          final toastContext = _resolveContext(context);
          if (toastContext != null) {
            showSnackbar(
              toastContext,
              'Still out of stock. Please add stock.',
              Colors.red,
            );
          }
        }
      },
    );
  }

  Product productById(String productId) {
    return products.firstWhere(
      (p) => p.id == productId,
      orElse: () => Product(),
    );
  }

  int availableStockFor(String productId) {
    final quantity = productById(productId).quantity;
    return quantity == null || quantity < 0 ? 0 : quantity;
  }

  void addProduct(BuildContext context, String productId, int quantity) async {
    Product? product = productById(productId);
    final available = product.quantity ?? 0;
    if (available >= quantity && quantity > 0) {
      if (selectedProducts.containsKey(productId)) {
        selectedProducts[productId] = selectedProducts[productId]! + quantity;
      } else {
        selectedProducts[productId] = quantity;
      }
      notifyListeners();
    } else {
      // PAS-UX-XX: instead of hard-blocking with a "Stock is zero" toast,
      // give the merchant an explicit one-tap top-up. A merchant who is
      // mid-transaction almost always knows their on-hand count is stale
      // (just received a delivery, hand-counted the shelf, etc.) and
      // wants to proceed without context-switching to the product page.
      // Falling back to the snackbar+navigate path only when the
      // confirmation is declined or the write fails.
      final topUp = await _confirmAndTopUpStock(
        context,
        product: product,
        productId: productId,
        currentStock: available,
        requestedQuantity: quantity,
      );
      if (topUp) {
        if (selectedProducts.containsKey(productId)) {
          selectedProducts[productId] = selectedProducts[productId]! + quantity;
        } else {
          selectedProducts[productId] = quantity;
        }
        notifyListeners();
      } else {
        final toastContext = _resolveContext(context);
        if (toastContext != null) {
          showSnackbarWithNavigation(
            toastContext,
            'Cannot add product. Stock is zero or not available.',
            Colors.orange,
            updateStockSnackBar(context, productId, 1, product),
          );
        }
      }
    }
  }

  Future<void> updateProductQuantity(
    BuildContext context,
    String productId,
    int quantity,
  ) async {
    if (quantity <= 0) {
      selectedProducts.remove(productId);
      notifyListeners();
      return;
    }
    Product product = productById(productId);
    final available = product.quantity ?? 0;
    if (available >= quantity) {
      selectedProducts[productId] = quantity;
      notifyListeners();
      return;
    }

    // PAS-UX-XX: requested qty exceeds on-hand stock. Previously this
    // path silently dropped the request and showed an orange snackbar
    // with an "Update Stock" action that forced the merchant to leave
    // the transaction, edit the product, and start over. For a SMB
    // merchant typing in a sale at the till, that interrupt is the
    // single most common reason transactions get abandoned (see
    // user feedback). Replace the wall with an inline confirmation:
    // "Only N in stock — add M more and continue?" with one tap.
    final topUp = await _confirmAndTopUpStock(
      context,
      product: product,
      productId: productId,
      currentStock: available,
      requestedQuantity: quantity,
    );
    if (topUp) {
      selectedProducts[productId] = quantity;
      notifyListeners();
    } else {
      // User declined — preserve the previous behaviour so the snackbar
      // recovery path still works for merchants who'd rather edit the
      // product details.
      final toastContext = _resolveContext(context);
      if (toastContext != null) {
        showSnackbarWithNavigation(
          toastContext,
          'Insufficient stock for ${product.name}.',
          Colors.orange,
          updateStockSnackBar(context, productId, 1, product),
        );
      }
      notifyListeners();
    }
  }

  /// Prompts the merchant to top up the on-hand stock so the requested
  /// transaction line can proceed. On confirm, writes the new quantity
  /// to Firestore (`users/{uid}/products/{id}.quantity`) and updates the
  /// in-memory [products] list so subsequent reads (`productById`,
  /// `availableStockFor`) see the bumped value immediately.
  ///
  /// Returns `true` if the merchant confirmed AND the write succeeded;
  /// `false` on cancel or write failure. Callers must fall back to the
  /// blocking snackbar path on `false`.
  Future<bool> _confirmAndTopUpStock(
    BuildContext context, {
    required Product product,
    required String productId,
    required int currentStock,
    required int requestedQuantity,
  }) async {
    final dialogContext = _resolveContext(context);
    if (dialogContext == null) return false;

    final shortfall = requestedQuantity - currentStock;
    final productName = product.name ?? 'this product';

    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add more stock?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentStock <= 0
                    ? '$productName is currently out of stock.'
                    : 'Only $currentStock of $productName in stock — you '
                        'asked for $requestedQuantity.',
              ),
              const SizedBox(height: 12),
              Text(
                'Add $shortfall more to inventory and continue with this '
                'transaction?',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your inventory will be updated immediately.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Add $shortfall & continue'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return false;

    try {
      await firestore
          .collection('users')
          .doc(userId)
          .collection('products')
          .doc(productId)
          .update({'quantity': requestedQuantity});
      // Keep the in-memory list in sync so the very next gate
      // (e.g. tapping `+` again) reads the new value without a round
      // trip to Firestore.
      product.quantity = requestedQuantity;
      final idx = products.indexWhere((p) => p.id == productId);
      if (idx >= 0) products[idx] = product;
      final fIdx = filteredProducts.indexWhere((p) => p.id == productId);
      if (fIdx >= 0) filteredProducts[fIdx] = product;
      final toastContext = _resolveContext(context);
      if (toastContext != null) {
        showSnackbar(
          toastContext,
          'Stock for $productName updated to $requestedQuantity.',
          Colors.green,
        );
      }
      return true;
    } catch (e) {
      final toastContext = _resolveContext(context);
      if (toastContext != null) {
        showSnackbar(
          toastContext,
          'Could not update stock: $e',
          Colors.red,
        );
      }
      return false;
    }
  }

  double calculateTotalAmount() {
    double total = 0.0;
    for (var productId in selectedProducts.keys) {
      Product? product = productById(productId);
      if (product.sellingPrice != null) {
        total += product.sellingPrice! * selectedProducts[productId]!;
      }
    }
    return total;
  }

  void filterProducts(String query) {
    if (query.isEmpty) {
      filteredProducts = products;
    } else {
      filteredProducts = products
          .where(
            (product) =>
                product.name!.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
    }
    notifyListeners();
  }

  List<MapEntry<String, int>> get paginatedSelectedProducts {
    final startIndex = currentPage * itemsPerPage;
    final endIndex = (startIndex + itemsPerPage).clamp(
      0,
      selectedProducts.length,
    );
    return selectedProducts.entries
        .skip(startIndex)
        .take(endIndex - startIndex)
        .toList();
  }

  void nextPage() {
    if ((currentPage + 1) * itemsPerPage < selectedProducts.length) {
      currentPage++;
      notifyListeners();
    }
  }

  void previousPage() {
    if (currentPage > 0) {
      currentPage--;
      notifyListeners();
    }
  }

  Future<void> sendSMS(
      String currentUserId,
      String customerId,
      double amountEntered,
      String customerName,
      String transactionType,
      String? mobileNumber,
      {MessagingPricingSnapshotV1? pricingSnapshot}) async {
    try {
      MessagingNotificationService notificationService =
          await MessagingNotificationService.create(
        pricingSnapshot: pricingSnapshot,
      );
      await notificationService.sendConfirmationMessage(
        currentUserId,
        customerId,
        transactionType,
        amountEntered,
        customerName,
        mobileNumber,
      );
    } catch (e) {
      print(e);
    }
  }

  @protected
  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void resetForm() {
    amountController.clear();
    stockAmountController.clear();
    remarksController.clear();
    selectedProducts.clear();
    salesSelectedDate = DateFormat("dd-MM-yyyy HH:mm").format(DateTime.now());
    setLoading(false);
    notifyListeners();
  }

  void resetFormAndNavigateAway(BuildContext context) {
    resetForm();
    Navigator.of(context).pop();
  }

  /// Leaves a transaction form without persisting the pending edits.
  /// Marking the current values pristine first prevents the form-level
  /// PopScope from showing a second discard prompt after the merchant has
  /// already made that choice in the confirmation-sheet close flow.
  void discardFormAndNavigateAway(BuildContext context) {
    markPristine(force: true);
    setLoading(false);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    // PAS-CRASH-_dependents: flip the disposed flag *before* tearing
    // down anything that listens to this notifier (controllers' own
    // listeners call `notifyListeners`). That way late callbacks fired
    // from in-flight Futures (`updateSale`, `deleteSale`,
    // `loadSaleDetails`, etc.) are silently dropped via the override
    // below instead of throwing "A ChangeNotifier was used after being
    // disposed", and the framework's `_dependents.isEmpty` assertion
    // gets one less way to be violated by a stray rebuild during route
    // teardown.
    _disposed = true;
    amountController.dispose();
    stockAmountController.dispose();
    remarksController.dispose();
    searchController.dispose();
    super.dispose();
  }

  bool _disposed = false;

  /// Public read-only flag so subclasses / async tasks can early-exit
  /// rather than rely solely on the `notifyListeners` guard.
  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}
