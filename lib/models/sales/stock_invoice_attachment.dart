import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Private, store-scoped stock-invoice metadata stored on a sale document.
///
/// [storagePath] is deliberately retained instead of a download URL. Firebase
/// Storage rules therefore remain the authorization boundary whenever the app
/// loads an invoice image.
class StockInvoiceAttachment {
  const StockInvoiceAttachment({
    required this.storagePath,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    this.uploadedAt,
  });

  final String storagePath;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final DateTime? uploadedAt;

  bool get isPdf => contentType.toLowerCase() == 'application/pdf';
  bool get isImage => !isPdf;

  factory StockInvoiceAttachment.fromMap(Map<String, dynamic> data) {
    final uploadedValue = data['uploadedAt'];
    DateTime? uploadedAt;
    if (uploadedValue is Timestamp) {
      uploadedAt = uploadedValue.toDate();
    } else if (uploadedValue is String) {
      uploadedAt = DateTime.tryParse(uploadedValue);
    }

    return StockInvoiceAttachment(
      storagePath: (data['storagePath'] ?? '').toString(),
      fileName: (data['fileName'] ?? 'Stock invoice').toString(),
      contentType: (data['contentType'] ?? 'image/jpeg').toString(),
      sizeBytes: _asInt(data['sizeBytes']),
      uploadedAt: uploadedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'storagePath': storagePath,
        'fileName': fileName,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
        if (uploadedAt != null) 'uploadedAt': Timestamp.fromDate(uploadedAt!),
      };

  static int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

enum StockInvoiceDraftStatus { ready, uploading, uploaded, failed }

/// Mutable form state for a local page or an already-uploaded attachment.
class StockInvoiceDraft {
  StockInvoiceDraft.local(this.localFile)
      : attachment = null,
        status = StockInvoiceDraftStatus.ready,
        errorMessage = null,
        progress = 0;

  StockInvoiceDraft.existing(this.attachment)
      : localFile = null,
        status = StockInvoiceDraftStatus.uploaded,
        errorMessage = null,
        progress = 1;

  File? localFile;
  StockInvoiceAttachment? attachment;
  StockInvoiceDraftStatus status;
  String? errorMessage;
  double progress;

  String get displayName =>
      localFile?.uri.pathSegments.last ??
      attachment?.fileName ??
      'Invoice page';

  bool get isPdf =>
      attachment?.isPdf == true ||
      (localFile?.path.toLowerCase().endsWith('.pdf') ?? false);

  bool get isExisting => attachment != null && localFile == null;
  bool get canRetry =>
      localFile != null && status == StockInvoiceDraftStatus.failed;
}
