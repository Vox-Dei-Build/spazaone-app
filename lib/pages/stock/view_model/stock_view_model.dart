import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

  StockViewModel() : userId = FirebaseAuth.instance.currentUser?.uid ?? '';

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

      // Navigate to the updated group page after successful update
      SchedulerBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) =>
                ProductGroupPage(name: newName, viewModel: this),
          ),
        );
      });
    } catch (e) {
      setErrorMessage("An error occurred while editing the product group");
    } finally {
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
      isLoading = true;
      notifyListeners();
      try {
        var formattedText =
            formatStringToCamelCase(newProductGroupController.text);
        await addProductGroup(formattedText);
        SchedulerBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pop();
        });
      } catch (e) {
        setErrorMessage("An error occurred while adding the product group");
      } finally {
        isLoading = false;
        notifyListeners();
        newProductGroupController.clear();
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
              .map((doc) =>
                  Product.fromMap(doc.data() as Map<String, dynamic>, doc.id))
              .toList());
    } else {
      return _firestore
          .collection('users')
          .doc(userId)
          .collection('products')
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) =>
                  Product.fromMap(doc.data() as Map<String, dynamic>, doc.id))
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
