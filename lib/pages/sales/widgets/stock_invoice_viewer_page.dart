import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:pasella/services/stock_invoice_attachment_service.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pdfrx/pdfrx.dart';

typedef StockInvoiceBytesLoader = Future<Uint8List?> Function();

class StockInvoiceViewerPage extends StatefulWidget {
  const StockInvoiceViewerPage({
    super.key,
    required this.fileName,
    required this.contentType,
    required this.loadBytes,
  });

  final String fileName;
  final String contentType;
  final StockInvoiceBytesLoader loadBytes;

  @override
  State<StockInvoiceViewerPage> createState() => _StockInvoiceViewerPageState();
}

class _StockInvoiceViewerPageState extends State<StockInvoiceViewerPage> {
  late Future<Uint8List> _bytes;
  bool _failureReported = false;

  @override
  void initState() {
    super.initState();
    _bytes = _load();
  }

  Future<Uint8List> _load() async {
    try {
      final bytes = await widget.loadBytes();
      if (bytes == null) {
        throw const StockInvoiceValidationException(
          'This invoice file is no longer available.',
        );
      }
      StockInvoiceAttachmentService.validateBytes(
        bytes,
        fileName: widget.fileName,
        declaredContentType: widget.contentType,
      );
      return bytes;
    } catch (error) {
      _captureFailure(error);
      rethrow;
    }
  }

  void _retry() {
    _failureReported = false;
    setState(() => _bytes = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: CustomAppBar(title: widget.fileName),
      body: SafeArea(
        child: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return _InvoiceLoadError(
                message: _messageFor(snapshot.error),
                onRetry: _retry,
              );
            }
            final bytes = snapshot.data!;
            if (widget.contentType.toLowerCase() == 'application/pdf') {
              return PdfViewer.data(
                bytes,
                sourceName: widget.fileName,
                params: PdfViewerParams(
                  backgroundColor: Colors.black,
                  loadingBannerBuilder: (_, __, ___) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  errorBannerBuilder: (_, error, __, ___) {
                    _captureFailure(error, category: 'corrupt_file');
                    return _InvoiceLoadError(
                      message: 'This PDF is corrupt or cannot be displayed.',
                      onRetry: _retry,
                    );
                  },
                ),
              );
            }
            return Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, error, __) {
                    _captureFailure(error, category: 'corrupt_file');
                    return _InvoiceLoadError(
                      message:
                          'This invoice image is corrupt or cannot be displayed.',
                      onRetry: _retry,
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _messageFor(Object? error) {
    if (error is StockInvoiceValidationException) {
      if (error.message.contains('no longer available')) return error.message;
      return 'This invoice file is corrupt or unsupported.';
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'object-not-found':
          return 'This invoice file is no longer available.';
        case 'unauthorized':
        case 'unauthenticated':
          return 'You do not have access to this invoice.';
        case 'retry-limit-exceeded':
        case 'unavailable':
        case 'network-request-failed':
        case 'unknown':
          return 'Could not load this invoice. Check your connection and retry.';
      }
    }
    return 'Could not load this invoice. Please retry.';
  }

  void _captureFailure(Object error, {String? category}) {
    if (_failureReported) return;
    _failureReported = true;
    unawaited(
      TelemetryService.instance.capture(
        StockInvoiceViewerFailed(
          fileType: widget.contentType.toLowerCase() == 'application/pdf'
              ? 'pdf'
              : 'image',
          failure: category ?? _failureCategory(error),
        ),
      ),
    );
  }

  String _failureCategory(Object error) {
    if (error is StockInvoiceValidationException) {
      return error.message.contains('no longer available')
          ? 'missing_file'
          : 'corrupt_file';
    }
    if (error is FirebaseException) {
      return switch (error.code) {
        'object-not-found' => 'missing_file',
        'unauthorized' || 'unauthenticated' => 'denied',
        'retry-limit-exceeded' ||
        'unavailable' ||
        'network-request-failed' ||
        'unknown' =>
          'offline',
        _ => 'unavailable',
      };
    }
    return 'unavailable';
  }
}

class _InvoiceLoadError extends StatelessWidget {
  const _InvoiceLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 40),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
