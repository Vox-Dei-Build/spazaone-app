import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/services/store_session.dart';
import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:intl/intl.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/models/sales/stock_invoice_attachment.dart';
import 'package:pasella/pages/sales/models/sale_edit_result.dart';
import 'package:pasella/pages/sales/widgets/edit_sale.dart';
import 'package:pasella/pages/sales/widgets/stock_invoice_viewer_page.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/transaction_detail_widgets.dart';
import 'package:pasella/services/stock_invoice_attachment_service.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';
import 'package:pasella/widgets/private_region.dart';

class SaleDetailPage extends StatefulWidget {
  final Sale sale;
  final Future<Uint8List?> Function(String storagePath)?
      loadStockInvoicePreview;
  final Widget Function(Sale sale)? editSaleBuilder;

  const SaleDetailPage({
    super.key,
    required this.sale,
    this.loadStockInvoicePreview,
    this.editSaleBuilder,
  });

  @override
  State<SaleDetailPage> createState() => _SaleDetailPageState();
}

class _SaleDetailPageState extends State<SaleDetailPage> {
  late Sale sale;
  bool _wasUpdated = false;
  bool _exitAuthorized = false;

  // PAS-UX-15: batched product lookup.
  //
  // Audit found this page rendered one FutureBuilder<DocumentSnapshot>
  // per product entry, each issuing an independent Firestore .get()
  // against /users/<uid>/products/<id>. A sale with 12 line items
  // therefore round-tripped Firestore 12 times in parallel and
  // showed 12 separate spinners that resolved at different frames.
  // We now fetch every product in a single batch (chunked at the
  // Firestore whereIn cap of 30) and keep the result in a map keyed
  // by product id.
  late Future<Map<String, Map<String, dynamic>>> _productsFuture;

  Future<Uint8List?> _loadStockInvoicePreview(String storagePath) =>
      widget.loadStockInvoicePreview?.call(storagePath) ??
      StockInvoiceAttachmentService().loadPreview(storagePath);

  void _closeDetails({required bool changed}) {
    if (!mounted || _exitAuthorized) return;
    setState(() => _exitAuthorized = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(changed ? true : null);
    });
  }

  void _applyEditResult(SaleEditResult? result) {
    if (result == null || !mounted) return;
    switch (result.outcome) {
      case SaleEditOutcome.updated:
        final updatedSale = result.sale;
        if (updatedSale == null) return;
        setState(() {
          sale = updatedSale;
          _productsFuture = _fetchProducts(sale.products.keys.toList());
          _wasUpdated = true;
        });
      case SaleEditOutcome.deleted:
        _closeDetails(changed: true);
    }
  }

  @override
  void initState() {
    super.initState();
    sale = widget.sale; // Initialize with the passed sale data
    _productsFuture = _fetchProducts(sale.products.keys.toList());
  }

  /// Fetches every product referenced by [productIds] in a single
  /// batched query (chunked by Firestore's 30-element whereIn cap).
  /// Returns a map keyed by product id; missing ids are simply
  /// absent from the map and rendered as 'Unknown product' below.
  Future<Map<String, Map<String, dynamic>>> _fetchProducts(
      List<String> productIds) async {
    if (productIds.isEmpty) return const {};
    final uid = StoreSession.instance.storeId;
    if (uid.isEmpty) return const {};

    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('products');

    // Chunk to honour Firestore's 30-element whereIn limit. In
    // practice merchants rarely break 10 line items per sale but
    // we chunk defensively so this doesn't silently drop products
    // off long sales.
    const chunkSize = 30;
    final result = <String, Map<String, dynamic>>{};
    for (var i = 0; i < productIds.length; i += chunkSize) {
      final end = (i + chunkSize < productIds.length)
          ? i + chunkSize
          : productIds.length;
      final chunk = productIds.sublist(i, end);
      final snap = await col.where(FieldPath.documentId, whereIn: chunk).get();
      for (final doc in snap.docs) {
        result[doc.id] = doc.data();
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _exitAuthorized || !_wasUpdated,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeDetails(changed: true);
      },
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Sale details',
          onBackPressed: () => _closeDetails(changed: _wasUpdated),
          trailing: IconButton(
            tooltip: 'Edit sale',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final result = await Navigator.of(context).push<SaleEditResult>(
                MaterialPageRoute(
                  builder: (context) =>
                      widget.editSaleBuilder?.call(sale) ??
                      EditSale(sale: sale),
                ),
              );
              _applyEditResult(result);
            },
          ),
        ),
        body: SaleDetailsContent(
          sale: sale,
          productsFuture: _productsFuture,
          loadStockInvoicePreview: _loadStockInvoicePreview,
        ),
      ),
    );
  }
}

/// Read-only sale presentation shared by the live detail page and previews.
/// Product lookup and invoice storage remain owned by the calling page.
class SaleDetailsContent extends StatelessWidget {
  const SaleDetailsContent({
    super.key,
    required this.sale,
    required this.productsFuture,
    required this.loadStockInvoicePreview,
  });

  final Sale sale;
  final Future<Map<String, Map<String, dynamic>>> productsFuture;
  final Future<Uint8List?> Function(String storagePath) loadStockInvoicePreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remarks = sale.remarks?.trim() ?? '';
    return SafeArea(
      child: PrivateRegion(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TransactionDetailHero(
              eyebrow: 'Sale',
              amount: CurrencyUtil.format(sale.amount),
              status: 'Paid',
              statusTone: TransactionDetailStatusTone.positive,
              meta: DateFormat('d MMM yyyy · HH:mm').format(sale.dateAdded),
            ),
            const SizedBox(height: SpazaSpace.md),
            TransactionDetailCard(
              child: Column(
                children: [
                  TransactionDetailRow(
                    'Stock amount',
                    CurrencyUtil.format(sale.stockAmount),
                  ),
                  const Divider(),
                  TransactionDetailRow('Payment', sale.type),
                ],
              ),
            ),
            if (remarks.isNotEmpty) ...[
              const SizedBox(height: SpazaSpace.md),
              TransactionDetailCard(
                title: 'Note',
                child: Text(remarks, style: theme.textTheme.bodyMedium),
              ),
            ],
            if (sale.products.isNotEmpty) ...[
              const SizedBox(height: SpazaSpace.md),
              TransactionDetailCard(
                title: 'Products',
                child: FutureBuilder<Map<String, Map<String, dynamic>>>(
                  future: productsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return const Text('Could not load products.');
                    }
                    final products = snapshot.data ?? const {};
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0;
                            index < sale.products.entries.length;
                            index++) ...[
                          if (index > 0) const Divider(),
                          _SaleProductRow(
                            product: products[
                                sale.products.entries.elementAt(index).key],
                            quantity:
                                sale.products.entries.elementAt(index).value,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
            if (sale.stockInvoices.isNotEmpty) ...[
              const SizedBox(height: SpazaSpace.md),
              TransactionDetailCard(
                title: 'Stock invoices',
                child: Column(
                  children: sale.stockInvoices
                      .map((attachment) => _StockInvoiceTile(
                            attachment: attachment,
                            loadPreview: loadStockInvoicePreview,
                          ))
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SaleProductRow extends StatelessWidget {
  const _SaleProductRow({required this.product, required this.quantity});

  final Map<String, dynamic>? product;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    if (product == null) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(SpazaIcons.products),
        title: Text('Product unavailable'),
      );
    }
    final name = formatStringToCamelCase(
      (product!['name'] ?? 'Unnamed product').toString(),
    );
    final sellingPrice = product!['sellingPrice'];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 6,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: SpazaColors.subtle,
          borderRadius: BorderRadius.circular(SpazaRadius.small),
        ),
        child: const Icon(SpazaIcons.products, size: 19),
      ),
      title: Text(name),
      subtitle: Text(
        sellingPrice is num
            ? '$quantity × ${CurrencyUtil.format(sellingPrice.toDouble())}'
            : '$quantity sold',
      ),
    );
  }
}

class _StockInvoiceTile extends StatelessWidget {
  const _StockInvoiceTile({
    required this.attachment,
    required this.loadPreview,
  });

  final StockInvoiceAttachment attachment;
  final Future<Uint8List?> Function(String storagePath) loadPreview;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open invoice ${attachment.fileName}',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SizedBox.square(
          dimension: 44,
          child: attachment.isPdf
              ? const Icon(Icons.picture_as_pdf_outlined)
              : FutureBuilder<Uint8List?>(
                  future: loadPreview(attachment.storagePath),
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    if (bytes != null) {
                      return ClipRRect(
                        borderRadius:
                            BorderRadius.circular(SpazaRadius.control),
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.receipt_long_outlined,
                          ),
                        ),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    }
                    return const Icon(Icons.receipt_long_outlined);
                  },
                ),
        ),
        title: Text(
          attachment.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          attachment.isPdf ? 'Private invoice PDF' : 'Private invoice image',
        ),
        trailing: const Icon(Icons.open_in_full_rounded),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => StockInvoiceViewerPage(
              fileName: attachment.fileName,
              contentType: attachment.contentType,
              loadBytes: () => loadPreview(attachment.storagePath),
            ),
          ),
        ),
      ),
    );
  }
}
