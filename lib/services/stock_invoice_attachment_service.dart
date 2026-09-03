import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasella/models/sales/stock_invoice_attachment.dart';
import 'package:pasella/utils/photo_upload_util.dart';

enum StockInvoicePickSource { camera, gallery, pdf }

class StockInvoiceValidationException implements Exception {
  const StockInvoiceValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

@immutable
class StockInvoiceFileInfo {
  const StockInvoiceFileInfo({
    required this.contentType,
    required this.extension,
    required this.sizeBytes,
  });

  final String contentType;
  final String extension;
  final int sizeBytes;
}

class StockInvoiceAttachmentService {
  StockInvoiceAttachmentService({
    PhotoUploadUtil? photoUploadUtil,
    FirebaseStorage? storage,
    Random? random,
  })  : _providedPhotoUploadUtil = photoUploadUtil,
        _providedStorage = storage,
        _random = random ?? Random.secure();

  static const maxAttachments = 3;
  static const maxAttachmentBytes = 5 * 1024 * 1024;
  static const maxImageBytes = maxAttachmentBytes;

  final PhotoUploadUtil? _providedPhotoUploadUtil;
  final FirebaseStorage? _providedStorage;
  final Random _random;
  PhotoUploadUtil get _photoUploadUtil =>
      _providedPhotoUploadUtil ?? PhotoUploadUtil();
  FirebaseStorage get _storage => _providedStorage ?? FirebaseStorage.instance;

  Future<File?> pickAndPrepare(BuildContext context) async {
    final source = await showModalBottomSheet<StockInvoicePickSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Attach stock invoice'),
              subtitle: Text('Choose an image or a PDF up to 5 MB.'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(
                sheetContext,
                StockInvoicePickSource.camera,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo library'),
              onTap: () => Navigator.pop(
                sheetContext,
                StockInvoicePickSource.gallery,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF from Files'),
              onTap: () => Navigator.pop(
                sheetContext,
                StockInvoicePickSource.pdf,
              ),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    if (source == StockInvoicePickSource.pdf) {
      const pdfGroup = XTypeGroup(
        label: 'PDF documents',
        extensions: <String>['pdf'],
        mimeTypes: <String>['application/pdf'],
        uniformTypeIdentifiers: <String>['com.adobe.pdf'],
      );
      final selected = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[pdfGroup],
      );
      return selected == null ? null : File(selected.path);
    }
    if (!context.mounted) return null;
    File? result;
    await _photoUploadUtil.handleImagePickFromSource(
      context,
      source == StockInvoicePickSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
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

    final info = await validateFile(file);
    final sizeBytes = info.sizeBytes;
    final extension = info.extension;
    final contentType = info.contentType;
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

  Future<Uint8List?> loadAttachment(String storagePath) {
    return _storage.ref(storagePath).getData(maxAttachmentBytes);
  }

  Future<Uint8List?> loadPreview(String storagePath) =>
      loadAttachment(storagePath);

  static Future<StockInvoiceFileInfo> validateFile(File file) async {
    final sizeBytes = await file.length();
    if (sizeBytes <= 0) {
      throw const StockInvoiceValidationException(
        'That invoice file is empty. Choose another file.',
      );
    }
    if (sizeBytes > maxAttachmentBytes) {
      throw const StockInvoiceValidationException(
        'That invoice is larger than 5 MB. Choose a smaller file.',
      );
    }
    final handle = await file.open();
    late Uint8List header;
    try {
      header = await handle.read(sizeBytes < 8 ? sizeBytes : 8);
    } finally {
      await handle.close();
    }
    return validateBytes(
      header,
      fileName: file.path,
      sizeBytes: sizeBytes,
    );
  }

  static StockInvoiceFileInfo validateBytes(
    Uint8List bytes, {
    required String fileName,
    int? sizeBytes,
    String? declaredContentType,
  }) {
    final totalBytes = sizeBytes ?? bytes.length;
    if (totalBytes <= 0 || bytes.isEmpty) {
      throw const StockInvoiceValidationException(
        'That invoice file is empty. Choose another file.',
      );
    }
    if (totalBytes > maxAttachmentBytes) {
      throw const StockInvoiceValidationException(
        'That invoice is larger than 5 MB. Choose a smaller file.',
      );
    }
    final isPdf = bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2d;
    final isJpeg = bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    const pngSignature = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    final isPng = bytes.length >= pngSignature.length &&
        List<int>.generate(pngSignature.length, (index) => index)
            .every((index) => bytes[index] == pngSignature[index]);
    final lowerName = fileName.toLowerCase();
    late final StockInvoiceFileInfo detected;
    if (isPdf) {
      detected = StockInvoiceFileInfo(
        contentType: 'application/pdf',
        extension: 'pdf',
        sizeBytes: totalBytes,
      );
    } else if (isPng) {
      detected = StockInvoiceFileInfo(
        contentType: 'image/png',
        extension: 'png',
        sizeBytes: totalBytes,
      );
    } else if (isJpeg) {
      detected = StockInvoiceFileInfo(
        contentType: 'image/jpeg',
        extension: 'jpg',
        sizeBytes: totalBytes,
      );
    } else {
      throw const StockInvoiceValidationException(
        'Choose a valid PDF, JPEG or PNG invoice.',
      );
    }
    final extensionMatches = switch (detected.contentType) {
      'application/pdf' => lowerName.endsWith('.pdf'),
      'image/png' => lowerName.endsWith('.png'),
      _ => lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg'),
    };
    final declared = declaredContentType?.trim().toLowerCase();
    if (!extensionMatches ||
        (declared != null &&
            declared.isNotEmpty &&
            declared != detected.contentType)) {
      throw const StockInvoiceValidationException(
        'The invoice file type does not match its contents.',
      );
    }
    return detected;
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
}
