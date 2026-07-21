import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/services/store_session.dart';
import 'package:flutter/material.dart';
import 'package:pasella/models/stock/product_group_model.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/models/stock/products_initial_data.dart';
import 'package:pasella/pages/stock/product_group_page/product_group_page.dart';
import 'package:pasella/utils/string_utils.dart';

class StockViewModel with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String userId;
  final TextEditingController newProductGroupController =
      TextEditingController();
  bool isLoading = false;
  bool _disposed = false;
  String? errorMessage;
  List<Product> products = [];

  StockViewModel() : userId = StoreSession.instance.storeId;

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

  Stream<List<Product>> streamProducts() {
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

  Stream<List<Product>> streamProductsByGroup(String? groupName) {
    if (groupName != null) {
      return _firestore
          .collection('users')
          .doc(userId)
          .collection('products')
          .where('group', isEqualTo: groupName)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => Product.fromMap(doc.data(), doc.id))
              .toList());
    } else {
      return _firestore
          .collection('users')
          .doc(userId)
          .collection('products')
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => Product.fromMap(doc.data(), doc.id))
              .toList());
    }
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
