import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/models/stock/products_initial_data.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/utils/photo_upload_util.dart';
import 'package:pasella/utils/show_toast.dart';

class ProductViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool isLoading = false;
  bool _disposed = false; // Track whether the ViewModel is disposed
  String? imageUrl;
  final PhotoUploadUtil _photoUploadUtil = PhotoUploadUtil();

  // Controllers to manage the text input fields
  late TextEditingController nameController;
  late TextEditingController costController;
  late TextEditingController sellingPriceController;
  late TextEditingController quantityController;
  late TextEditingController companyController;
  late TextEditingController descriptionController;
  bool _hasUnsavedChanges = false;

  List<String> productGroups = initialProductGroups;

  ProductViewModel(Product product) {
    nameController = TextEditingController(text: product.name);
    costController = TextEditingController(text: product.cost?.toString());
    sellingPriceController = TextEditingController(
      text: product.sellingPrice?.toString(),
    );
    quantityController = TextEditingController(
      text: product.quantity?.toString(),
    );
    companyController = TextEditingController(text: product.company);
    descriptionController = TextEditingController(text: product.description);
    imageUrl = product.image;
    _fetchProductGroups();
  }

  bool get hasUnsavedChanges => _hasUnsavedChanges;

  void markUnsavedChanges() {
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  Future<void> _fetchProductGroups() async {
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('productGroups')
          .get();

      final userGroups =
          querySnapshot.docs.map((doc) => doc['name'] as String).toList();
      productGroups = [...initialProductGroups, ...userGroups];
      productGroups.sort();
      notifyListeners();
    } catch (e) {
      print('Failed to fetch product groups: $e');
    }
  }

  void handleImagePick(BuildContext context, Product product) async {
    await _photoUploadUtil.handleImagePick(context, (pickedImage) async {
      if (pickedImage != null) {
        isLoading = true;
        markUnsavedChanges();
        notifyListeners();

        try {
          imageUrl = await _photoUploadUtil.uploadImage(
            pickedImage,
            'products/$userId/${pickedImage.path.split('/').last}',
          );
          product.image = imageUrl;
        } catch (e) {
          print('Failed to upload image: $e');
          imageUrl = null;
        } finally {
          isLoading = false;
          notifyListeners();
        }
      }
    });
  }

  Future<Product?> saveProduct(
    BuildContext context,
    Product product,
    String? docID, {
    bool showSuccessSnackbar = true,
  }) async {
    // PAS-WA-03: image is mandatory for WhatsApp-listed/orderable products.
    // The image picker is a GestureDetector outside the Form so the inline
    // field validators on the create/edit page can't catch this — gate it
    // here, before any Firestore write, so customers never see a listed
    // product with no photo.
    if (product.whatsappListed && (imageUrl == null || imageUrl!.isEmpty)) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        showErrorSnackBar(
          context,
          'Add a product image before listing this for WhatsApp orders.',
        );
      });
      return null;
    }

    if (!_validateInputs(context)) return null;

    try {
      isLoading = true;
      notifyListeners();

      product.name = nameController.text;
      product.cost = double.tryParse(costController.text);
      product.sellingPrice = double.tryParse(sellingPriceController.text);
      product.quantity = int.tryParse(quantityController.text);
      product.company = companyController.text;
      product.description = descriptionController.text;
      product.image = imageUrl;

      DocumentReference docRef;
      if (docID == null) {
        // Add new product
        docRef = await _firestore
            .collection('users')
            .doc(userId)
            .collection('products')
            .add(product.toMap());
        product.id = docRef.id;
      } else {
        // Update existing product
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('products')
            .doc(docID)
            .update(product.toMap());
        product.id = docID;
      }

      _hasUnsavedChanges = false;
      notifyListeners();

      // PAS-UX-16: emit ProductCreated / ProductUpdated so the
      // onboarding funnel ('signup -> first product -> first
      // customer -> first sale -> first message') is measurable
      // end-to-end. Buckets are coarse and contain no merchant PII.
      final event = (docID == null)
          ? ProductCreated(
              group: product.group,
              sellingPriceBucket: amountBucketZAR(product.sellingPrice ?? 0),
              costPriceBucket: amountBucketZAR(product.cost ?? 0),
              hasImage: (product.image ?? '').isNotEmpty,
            )
          : ProductUpdated(
              group: product.group,
              sellingPriceBucket: amountBucketZAR(product.sellingPrice ?? 0),
              costPriceBucket: amountBucketZAR(product.cost ?? 0),
              hasImage: (product.image ?? '').isNotEmpty,
            );
      // Fire-and-forget: telemetry must never block the UI.
      // ignore: unawaited_futures
      TelemetryService.instance.capture(event);

      if (showSuccessSnackbar) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          showSnackbar(context, 'Saved Successfully!', Colors.green);
        });
      }

      return product;
    } catch (e) {
      print(e);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        showErrorSnackBar(context, 'Failed to save product!');
      });
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteProduct(BuildContext context, String? docID) async {
    try {
      isLoading = true;
      notifyListeners();
      // PAS-UX-16: read group before delete so the event can carry
      // it without an extra round-trip after the doc is gone.
      String? groupBeforeDelete;
      try {
        final snap = await _firestore
            .collection('users')
            .doc(userId)
            .collection('products')
            .doc(docID)
            .get();
        groupBeforeDelete = snap.data()?['group'] as String?;
      } catch (_) {
        // If the read fails the analytics event still fires without
        // group context; never let observability code prevent the
        // actual delete.
      }
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('products')
          .doc(docID)
          .delete();
      // PAS-UX-16: ProductDeleted - fire-and-forget so telemetry
      // can't block the navigator.pop in the post-frame callback.
      // ignore: unawaited_futures
      TelemetryService.instance.capture(
        ProductDeleted(group: groupBeforeDelete),
      );
      SchedulerBinding.instance.addPostFrameCallback((_) {
        showSnackbar(context, 'Deleted Successfully!', Colors.green);
        Navigator.of(context).pop();
      });
    } catch (e) {
      showErrorSnackBar(context, 'Failed to delete product!');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  bool _validateInputs(BuildContext context) {
    return nameController.text.isNotEmpty &&
        costController.text.isNotEmpty &&
        sellingPriceController.text.isNotEmpty &&
        quantityController.text.isNotEmpty;
  }

  @override
  void dispose() {
    _disposed = true;
    nameController.dispose();
    costController.dispose();
    sellingPriceController.dispose();
    quantityController.dispose();
    companyController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }
}
