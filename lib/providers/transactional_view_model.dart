import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_details/product_details.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/utils/show_toast.dart';

class TransactionViewModel extends ChangeNotifier {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final TextEditingController amountController = TextEditingController();
  final TextEditingController remarksController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  String salesSelectedDate =
      DateFormat("dd-MM-yyyy HH:mm").format(DateTime.now());

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
    remarksController.addListener(notifyListeners);
  }

  Future<void> loadProducts() async {
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
      BuildContext context, String productId, int quantity, Product product) {
    return SnackBarAction(
      label: 'Update Stock',
      textColor: Colors.white,
      onPressed: () async {
        final navContext = _resolveContext(context);
        if (navContext == null) return;
        await Navigator.of(navContext).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailsPage(
              docID: productId,
              product: product,
            ),
          ),
        );
        // After navigating back, reload the products and check stock again
        await loadProducts();
        Product updatedProduct = products.firstWhere((p) => p.id == productId,
            orElse: () => Product());
        if (updatedProduct.quantity != null && updatedProduct.quantity! > 0) {
          addProduct(context, productId, quantity);
        } else {
          final toastContext = _resolveContext(context);
          if (toastContext != null) {
            showSnackbar(
                toastContext, 'Still out of stock. Please add stock.', Colors.red);
          }
        }
      },
    );
  }

  void addProduct(BuildContext context, String productId, int quantity) async {
    Product? product =
        products.firstWhere((p) => p.id == productId, orElse: () => Product());
    if (product.quantity != null && product.quantity! > 0) {
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

  void updateProductQuantity(
      BuildContext context, String productId, int quantity) {
    if (quantity <= 0) {
      selectedProducts.remove(productId);
    } else {
      Product? product = products.firstWhere((p) => p.id == productId,
          orElse: () => Product());
      if (product.quantity != null && product.quantity! >= quantity) {
        selectedProducts[productId] = quantity;
      } else {
        final toastContext = _resolveContext(context);
        if (toastContext != null) {
          showSnackbarWithNavigation(
            toastContext,
            'Insufficient stock for ${product.name}.',
            Colors.orange,
            updateStockSnackBar(context, productId, 1, product),
          );
        }
      }
    }
    notifyListeners();
  }

  double calculateTotalAmount() {
    double total = 0.0;
    for (var productId in selectedProducts.keys) {
      Product? product = products.firstWhere((p) => p.id == productId,
          orElse: () => Product());
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
          .where((product) =>
              product.name!.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }
    notifyListeners();
  }

  List<MapEntry<String, int>> get paginatedSelectedProducts {
    final startIndex = currentPage * itemsPerPage;
    final endIndex =
        (startIndex + itemsPerPage).clamp(0, selectedProducts.length);
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
  ) async {
    try {
      MessagingNotificationService notificationService =
          await MessagingNotificationService.create();
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

  void resetFormAndNavigateAway(BuildContext context) {
    amountController.clear();
    remarksController.clear();
    selectedProducts.clear();
    salesSelectedDate = DateFormat("dd-MM-yyyy HH:mm").format(DateTime.now());
    setLoading(false);
    notifyListeners();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    amountController.dispose();
    remarksController.dispose();
    searchController.dispose();
    super.dispose();
  }
}
