import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/models/sales/stock_invoice_attachment.dart';
import 'package:pasella/services/stock_invoice_attachment_service.dart';

class StockInvoiceAttachmentsField extends StatelessWidget {
  const StockInvoiceAttachmentsField({
    super.key,
    required this.attachments,
    required this.onAdd,
    required this.onRemove,
    required this.onReplace,
    required this.onRetry,
    this.loadPreview,
  });

  final List<StockInvoiceDraft> attachments;
  final Future<void> Function() onAdd;
  final Future<void> Function(int index) onRemove;
  final Future<void> Function(int index) onReplace;
  final Future<void> Function(int index) onRetry;
  final Future<Uint8List?> Function(String storagePath)? loadPreview;

  @override
  Widget build(BuildContext context) {
    final canAdd =
        attachments.length < StockInvoiceAttachmentService.maxAttachments;
    return Padding(
      padding: const EdgeInsets.only(bottom: LayoutConstants.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('attach-stock-invoice'),
            onPressed: canAdd ? onAdd : null,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Attach stock invoice'),
          ),
          const SizedBox(height: 6),
          Text(
            'Optional · Up to 3 images · No invoice text is read automatically.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: LayoutConstants.spaceSm),
            ...List.generate(
              attachments.length,
              (index) => _InvoiceDraftTile(
                key: ValueKey('stock-invoice-$index'),
                draft: attachments[index],
                onRemove: () => onRemove(index),
                onReplace: () => onReplace(index),
                onRetry: () => onRetry(index),
                loadPreview: loadPreview,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InvoiceDraftTile extends StatelessWidget {
  const _InvoiceDraftTile({
    super.key,
    required this.draft,
    required this.onRemove,
    required this.onReplace,
    required this.onRetry,
    required this.loadPreview,
  });

  final StockInvoiceDraft draft;
  final Future<void> Function() onRemove;
  final Future<void> Function() onReplace;
  final Future<void> Function() onRetry;
  final Future<Uint8List?> Function(String storagePath)? loadPreview;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(width: 56, height: 56, child: _preview()),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _statusText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  draft.status == StockInvoiceDraftStatus.failed
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (draft.status == StockInvoiceDraftStatus.uploading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: draft.progress),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (draft.canRetry)
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                TextButton(onPressed: onReplace, child: const Text('Replace')),
                TextButton(onPressed: onRemove, child: const Text('Remove')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _statusText {
    switch (draft.status) {
      case StockInvoiceDraftStatus.ready:
        return 'Ready to upload when you save';
      case StockInvoiceDraftStatus.uploading:
        return 'Uploading ${(draft.progress * 100).round()}%';
      case StockInvoiceDraftStatus.uploaded:
        return 'Attached securely';
      case StockInvoiceDraftStatus.failed:
        return draft.errorMessage ??
            'Upload failed. Retry or remove this image.';
    }
  }

  Widget _preview() {
    final local = draft.localFile;
    if (local != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(local, fit: BoxFit.cover, errorBuilder: _imageError),
      );
    }
    final path = draft.attachment?.storagePath;
    if (path == null || loadPreview == null) return _placeholder();
    return FutureBuilder<Uint8List?>(
      future: loadPreview!(path),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return _placeholder(
            loading: snapshot.connectionState == ConnectionState.waiting,
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child:
              Image.memory(bytes, fit: BoxFit.cover, errorBuilder: _imageError),
        );
      },
    );
  }

  Widget _imageError(BuildContext context, Object error, StackTrace? stack) =>
      _placeholder();

  Widget _placeholder({bool loading = false}) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: loading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.receipt_long_outlined),
        ),
      );
}
