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

  TransactionViewModel() {
    loadProducts();
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

  SnackBarAction updateStockSnackBar(
      BuildContext context, String productId, int quantity, Product product) {
    return SnackBarAction(
      label: 'Update Stock',
      textColor: Colors.white,
      onPressed: () async {
        await Navigator.of(scaffoldKey.currentContext!).push(
          MaterialPageRoute(
            builder: (context) => ProductDetailsPage(
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
          if (scaffoldKey.currentContext!.mounted) {
            showSnackbar(scaffoldKey.currentContext!,
                'Still out of stock. Please add stock.', Colors.red);
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
      if (scaffoldKey.currentContext != null) {
        showSnackbarWithNavigation(
          scaffoldKey.currentContext!,
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
        if (scaffoldKey.currentContext != null) {
          showSnackbarWithNavigation(
            scaffoldKey.currentContext!,
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
          MessagingNotificationService();
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
