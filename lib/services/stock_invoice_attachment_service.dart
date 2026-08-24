import 'dart:io';
import 'dart:math';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pasella/models/sales/stock_invoice_attachment.dart';
import 'package:pasella/utils/photo_upload_util.dart';

class StockInvoiceAttachmentService {
  StockInvoiceAttachmentService({
    PhotoUploadUtil? photoUploadUtil,
    FirebaseStorage? storage,
    Random? random,
  })  : _providedPhotoUploadUtil = photoUploadUtil,
        _providedStorage = storage,
        _random = random ?? Random.secure();

  static const maxAttachments = 3;
  static const maxImageBytes = 5 * 1024 * 1024;

  final PhotoUploadUtil? _providedPhotoUploadUtil;
  final FirebaseStorage? _providedStorage;
  final Random _random;
  PhotoUploadUtil get _photoUploadUtil =>
      _providedPhotoUploadUtil ?? PhotoUploadUtil();
  FirebaseStorage get _storage => _providedStorage ?? FirebaseStorage.instance;

  Future<File?> pickAndPrepare(BuildContext context) async {
    File? result;
    await _photoUploadUtil.handleImagePick(
      context,
      (file) => result = file,
      purpose: PhotoPermissionPurpose.stockInvoice,
    );
    return result;
  }

  Future<StockInvoiceAttachment> upload({
    required String storeId,
    required String saleId,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    if (storeId.isEmpty || saleId.isEmpty) {
      throw StateError('A store and sale are required for invoice uploads.');
    }

    final sizeBytes = await file.length();
    if (sizeBytes <= 0 || sizeBytes > maxImageBytes) {
      throw const FileSystemException(
        'Invoice image must be no larger than 5 MB.',
      );
    }

    final extension = _extensionFor(file.path);
    final contentType = extension == 'png' ? 'image/png' : 'image/jpeg';
    final fileName =
        'invoice_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}.$extension';
    final storagePath = 'stock_invoices/$storeId/$saleId/$fileName';
    final ref = _storage.ref(storagePath);
    final task = ref.putFile(
      file,
      SettableMetadata(
        contentType: contentType,
        cacheControl: 'private, max-age=3600',
        customMetadata: const {'privacy': 'store-members-only'},
      ),
    );
    final subscription = task.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        onProgress?.call(snapshot.bytesTransferred / snapshot.totalBytes);
      }
    });

    try {
      await task;
      onProgress?.call(1);
      return StockInvoiceAttachment(
        storagePath: storagePath,
        fileName: fileName,
        contentType: contentType,
        sizeBytes: sizeBytes,
        uploadedAt: DateTime.now(),
      );
    } catch (_) {
      // A failed upload may still have created an object. Deleting the exact
      // target is safe and keeps failed attempts out of the user's storage.
      await deletePath(storagePath);
      rethrow;
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> deletePath(String storagePath) async {
    if (storagePath.isEmpty) return;
    try {
      await _storage.ref(storagePath).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }

  Future<Uint8List?> loadPreview(String storagePath) {
    return _storage.ref(storagePath).getData(maxImageBytes);
  }

  @visibleForTesting
  static bool isStoreScopedPath({
    required String path,
    required String storeId,
    required String saleId,
  }) {
    final prefix = 'stock_invoices/$storeId/$saleId/';
    return storeId.isNotEmpty && saleId.isNotEmpty && path.startsWith(prefix);
  }

  static String _extensionFor(String filePath) {
    final lower = filePath.toLowerCase();
    return lower.endsWith('.png') ? 'png' : 'jpg';
  }
}
