import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/services/store_session.dart';
import 'package:flutter/material.dart';
import 'package:pasella/models/stock/product_group_model.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/models/stock/products_initial_data.dart';
import 'package:pasella/pages/stock/product_group_page/product_group_page.dart';
import 'package:pasella/utils/string_utils.dart';
import 'package:rxdart/rxdart.dart';

class StockViewModel with ChangeNotifier {
  final FirebaseFirestore? _firestoreOverride;
  final Stream<List<Product>>? _productsStreamOverride;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  final String userId;
  final TextEditingController newProductGroupController =
      TextEditingController();
  bool isLoading = false;
  bool _disposed = false;
  String? errorMessage;
  List<Product> products = [];
  StreamSubscription<List<Product>>? _productsSubscription;

  /// One full-catalogue listener feeds both the in-memory report state and the
  /// Products tab. Without replay/sharing, `watchProducts()` and
  /// `ProductList` each subscribed to the same Firestore query, doubling the
  /// initial document reads and every subsequent changed-document read.
  late final Stream<List<Product>> _sharedProductsStream =
      _buildProductsStream().shareReplay(maxSize: 1);

  StockViewModel({
    FirebaseFirestore? firestore,
    String? userId,
    Stream<List<Product>>? productsStream,
  })  : _firestoreOverride = firestore,
        _productsStreamOverride = productsStream,
        userId = userId ?? StoreSession.instance.storeId;

  /// Keeps the report totals and low-stock section on the same live product
  /// truth surface as the catalogue list. Previously [products] came from a
  /// one-time read, so a newly saved product appeared in Products via its
  /// StreamBuilder while the Stock tab retained stale totals until the whole
  /// page was reconstructed.
  void watchProducts() {
    _productsSubscription?.cancel();
    _productsSubscription = streamProducts().listen(
      (latest) {
        if (_disposed) return;
        products = List<Product>.unmodifiable(latest);
        errorMessage = null;
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_disposed) return;
        setErrorMessage('An error occurred while loading products');
      },
    );
  }

  Future<void> loadProducts() async {
    try {
      QuerySnapshot snapshot = await _firestore
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
      setErrorMessage("An error occurred while loading products");
    }
  }

  List<ProductGroup> getDefaultProductGroups() {
    return initialProductGroups
        .map((name) => ProductGroup(name: name))
        .toList();
  }

  Stream<int> getProductCount(String productGroupName) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('products')
        .where('group', isEqualTo: productGroupName)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Stream<List<ProductGroup>> streamProductGroups() {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('productGroups')
        .snapshots()
        .map(
          (snapshot) => [
            ...getDefaultProductGroups(),
            ...snapshot.docs
                .map((doc) => ProductGroup.fromMap(doc.data()))
                .toList(),
          ],
        );
  }

  Future<void> addProductGroup(String name) async {
    setLoading(true);
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('productGroups')
          .add({
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      setErrorMessage("An error occurred while adding the product group");
    } finally {
      setLoading(false);
    }
  }

  Future<void> editProductGroup(
      BuildContext context, String oldName, String newName) async {
    // PAS-CRASH-_dependents: capture the Navigator synchronously *before*
    // any await. Previously this method scheduled `pop()` +
    // `pushReplacement()` inside a `addPostFrameCallback` and then ran
    // `setLoading(false)` (which calls `notifyListeners()`) in the
    // `finally` block. That sequence — pop + pushReplacement + notify in
    // the same frame — left the dialog's InheritedElement being
    // deactivated while its Consumer was still registered, tripping
    // `_dependents.isEmpty: is not true` at framework.dart:6179.
    final navigator = Navigator.of(context);
    setLoading(true);
    try {
      var productGroupQuery = await _firestore
          .collection('users')
          .doc(userId)
          .collection('productGroups')
          .where('name', isEqualTo: oldName)
          .get();

      for (var doc in productGroupQuery.docs) {
        await doc.reference.update({'name': newName});
      }

      var productQuery = await _firestore
          .collection('users')
          .doc(userId)
          .collection('products')
          .where('group', isEqualTo: oldName)
          .get();

      for (var doc in productQuery.docs) {
        await doc.reference.update({'group': newName});
      }

      // Finish state mutation first, then perform navigation. Pop the
      // dialog, then in a microtask push the replacement so the two
      // route transitions don't collide in the same frame.
      isLoading = false;
      notifyListeners();
      navigator.pop();
      await Future<void>.delayed(Duration.zero);
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => ProductGroupPage(name: newName, viewModel: this),
        ),
      );
    } catch (e) {
      setErrorMessage("An error occurred while editing the product group");
      setLoading(false);
    }
  }

  Future<void> ensureUncategorizedGroupExists() async {
    final uncategorizedGroupQuery = await _firestore
        .collection('users')
        .doc(userId)
        .collection('productGroups')
        .where('name', isEqualTo: 'Uncategorized')
        .get();

    if (uncategorizedGroupQuery.docs.isEmpty) {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('productGroups')
          .add({
        'name': 'Uncategorized',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> moveProductsToAnotherGroup(
      String oldGroupName, String newGroupName) async {
    setLoading(true);
    try {
      await ensureUncategorizedGroupExists();

      var productQuery = await _firestore
          .collection('users')
          .doc(userId)
          .collection('products')
          .where('group', isEqualTo: oldGroupName)
          .get();

      for (var doc in productQuery.docs) {
        await doc.reference.update({'group': newGroupName});
      }

      setLoading(false);
    } catch (e) {
      setErrorMessage("An error occurred while moving the products");
      setLoading(false);
    }
  }

  Future<void> deleteProductGroup(String name) async {
    setLoading(true);
    try {
      var productGroupQuery = await _firestore
          .collection('users')
          .doc(userId)
          .collection('productGroups')
          .where('name', isEqualTo: name)
          .get();

      for (var doc in productGroupQuery.docs) {
        await doc.reference.delete();
      }

      setLoading(false);
    } catch (e) {
      setErrorMessage("An error occurred while deleting the product group");
      setLoading(false);
    }
  }

  Future<void> onAddProductGroup(BuildContext context) async {
    if (newProductGroupController.text.isNotEmpty) {
      // PAS-CRASH-_dependents: capture the Navigator synchronously and
      // finalize state before popping. The previous version scheduled
      // `pop()` in a `addPostFrameCallback` and then continued to flip
      // `isLoading`, `notifyListeners()`, and clear the controller in
      // the `finally` block — i.e. it rebuilt the dialog's still-mounted
      // Consumer after the route was already on its way out. That's the
      // race that surfaced as `_dependents.isEmpty: is not true` at
      // framework.dart:6179.
      final navigator = Navigator.of(context);
      isLoading = true;
      notifyListeners();
      try {
        var formattedText =
            formatStringToCamelCase(newProductGroupController.text);
        await addProductGroup(formattedText);
        // Finalize state first…
        isLoading = false;
        newProductGroupController.clear();
        notifyListeners();
        // …then pop synchronously, on the next microtask, so the
        // teardown does not collide with the notification above.
        await Future<void>.delayed(Duration.zero);
        navigator.pop();
      } catch (e) {
        setErrorMessage("An error occurred while adding the product group");
        isLoading = false;
        notifyListeners();
      }
    } else {
      setErrorMessage("Please enter a product group name");
      notifyListeners();
    }
  }

  Stream<List<Product>> _buildProductsStream() {
    final override = _productsStreamOverride;
    if (override != null) return override;
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('products')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Product.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Stream<List<Product>> streamProducts() => _sharedProductsStream;

  Stream<List<Product>> streamProductsByGroup(String? groupName) {
    if (groupName == null) return streamProducts();
    // The full catalogue remains mounted behind a group drilldown. Filter the
    // replayed stream locally so opening a group does not create a second
    // Firestore listener for products already present in memory.
    return streamProducts().map(
      (products) => products
          .where((product) => product.group == groupName)
          .toList(growable: false),
    );
  }

  List<Product> checkLowStock() {
    List<Product> lowStockProducts = [];
    for (var product in products) {
      if (product.quantity != null && product.quantity! <= 5) {
        lowStockProducts.add(product);
      }
    }
    return lowStockProducts;
  }

  void setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }

  void setErrorMessage(String? message) {
    errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _productsSubscription?.cancel();
    newProductGroupController.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }
}
