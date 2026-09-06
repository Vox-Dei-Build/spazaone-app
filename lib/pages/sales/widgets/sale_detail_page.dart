import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/services/store_session.dart';
import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:intl/intl.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/models/sales/stock_invoice_attachment.dart';
import 'package:pasella/pages/sales/widgets/edit_sale.dart';
import 'package:pasella/pages/sales/widgets/stock_invoice_viewer_page.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/services/stock_invoice_attachment_service.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';

class SaleDetailPage extends StatefulWidget {
  final Sale sale;
  final Future<Uint8List?> Function(String storagePath)?
      loadStockInvoicePreview;

  const SaleDetailPage({
    super.key,
    required this.sale,
    this.loadStockInvoicePreview,
  });

  @override
  State<SaleDetailPage> createState() => _SaleDetailPageState();
}

class _SaleDetailPageState extends State<SaleDetailPage> {
  late Sale sale;

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
  late final Future<Map<String, Map<String, dynamic>>> _productsFuture;

  Future<Uint8List?> _loadStockInvoicePreview(String storagePath) =>
      widget.loadStockInvoicePreview?.call(storagePath) ??
      StockInvoiceAttachmentService().loadPreview(storagePath);

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
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Sale details',
        trailing: IconButton(
          tooltip: 'Edit sale',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () async {
            // EditSale returns `true` when the sale was deleted — close
            // this details screen too since there is nothing left to view.
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (context) => EditSale(
                  sale: sale,
                ),
              ),
            );
            if (result == true && context.mounted) {
              Navigator.of(context).pop(true);
            }
          },
        ),
      ),
      body: SaleDetailsContent(
        sale: sale,
        productsFuture: _productsFuture,
        loadStockInvoicePreview: _loadStockInvoicePreview,
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
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sales amount', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Text(CurrencyUtil.format(sale.amount),
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  _SaleDetailValue(
                      'Stock amount', CurrencyUtil.format(sale.stockAmount)),
                  const Divider(height: 24),
                  _SaleDetailValue('Date',
                      DateFormat('dd MMM yyyy · HH:mm').format(sale.dateAdded)),
                  const SizedBox(height: 16),
                  _SaleDetailValue('Type', sale.type),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SaleDetailSection(
            title: 'Remarks',
            child: Text(sale.remarks ?? 'No remarks',
                style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 16),
          _SaleDetailSection(
            title: 'Products',
            child: sale.products.isEmpty
                ? Text('No products associated with this sale.',
                    style: theme.textTheme.bodyMedium)
                : FutureBuilder<Map<String, Map<String, dynamic>>>(
                    future: productsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final products = snapshot.data ?? const {};
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: sale.products.entries.map((entry) {
                          final product = products[entry.key];
                          if (product == null) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child:
                                  Text('Unknown product with ID: ${entry.key}'),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(SpazaIcons.products, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        formatStringToCamelCase(
                                            product['name'] ??
                                                'Unnamed product'),
                                        style: theme.textTheme.titleSmall),
                                    const SizedBox(height: 4),
                                    Text('Quantity: ${entry.value}',
                                        style: theme.textTheme.bodySmall),
                                    const SizedBox(height: 4),
                                    Text(
                                        product['sellingPrice'] is num
                                            ? 'Selling price: ${CurrencyUtil.format((product['sellingPrice'] as num).toDouble())}'
                                            : 'Selling price not set',
                                        style: theme.textTheme.bodySmall),
                                  ],
                                )),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          _SaleDetailSection(
            title: 'Stock invoices',
            child: sale.stockInvoices.isEmpty
                ? Text('No stock invoices attached.',
                    style: theme.textTheme.bodyMedium)
                : Column(
                    children: sale.stockInvoices
                        .map((attachment) => _StockInvoiceTile(
                              attachment: attachment,
                              loadPreview: loadStockInvoicePreview,
                            ))
                        .toList()),
          ),
        ],
      ),
    );
  }
}

class _SaleDetailSection extends StatelessWidget {
  const _SaleDetailSection({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

class _SaleDetailValue extends StatelessWidget {
  const _SaleDetailValue(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelWidget = Text(label, style: theme.textTheme.bodySmall);
    final valueWidget = Text(value, style: theme.textTheme.bodyMedium);
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 280 ||
          MediaQuery.textScalerOf(context).scale(14) >= 20) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          labelWidget,
          const SizedBox(height: 4),
          valueWidget,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: labelWidget),
        const SizedBox(width: 16),
        Flexible(child: valueWidget),
      ]);
    });
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
      child: Card(
        margin: const EdgeInsets.only(top: 8),
        child: ListTile(
          leading: SizedBox.square(
            dimension: 52,
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
      ),
    );
  }
}
