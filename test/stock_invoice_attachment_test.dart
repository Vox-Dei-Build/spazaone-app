import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/models/sales/stock_invoice_attachment.dart';
import 'package:pasella/pages/sales/widgets/sale_detail_page.dart';
import 'package:pasella/pages/sales/widgets/stock_invoice_attachments_field.dart';
import 'package:pasella/services/stock_invoice_attachment_service.dart';

StockInvoiceAttachment attachment(String name) => StockInvoiceAttachment(
      storagePath: 'stock_invoices/store-a/sale-a/$name.jpg',
      fileName: '$name.jpg',
      contentType: 'image/jpeg',
      sizeBytes: 1024,
    );

void main() {
  test('sale invoice metadata round-trips without public download URLs', () {
    final sale = Sale.fromMap({
      'amount': 1200,
      'type': 'Cash',
      'products': <String, int>{},
      'dateAdded': '2026-08-24T09:00:00.000',
      'stockInvoices': [
        attachment('page-1').toMap(),
        attachment('page-2').toMap(),
      ],
    }, 'sale-a');

    expect(sale.stockInvoices, hasLength(2));
    expect(sale.stockInvoices.first.storagePath, startsWith('stock_invoices/'));
    expect(sale.stockInvoices.first.toMap(), isNot(contains('downloadUrl')));
    expect(sale.stockInvoices.first.toMap(), isNot(contains('url')));
  });

  test('invoice paths must bind both store and sale', () {
    expect(
      StockInvoiceAttachmentService.isStoreScopedPath(
        path: 'stock_invoices/store-a/sale-a/page.jpg',
        storeId: 'store-a',
        saleId: 'sale-a',
      ),
      isTrue,
    );
    expect(
      StockInvoiceAttachmentService.isStoreScopedPath(
        path: 'stock_invoices/store-b/sale-a/page.jpg',
        storeId: 'store-a',
        saleId: 'sale-a',
      ),
      isFalse,
    );
  });

  testWidgets('attachment field documents its limit and no-OCR behavior',
      (tester) async {
    final drafts = [
      StockInvoiceDraft.existing(attachment('page-1')),
      StockInvoiceDraft.existing(attachment('page-2')),
      StockInvoiceDraft.existing(attachment('page-3')),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockInvoiceAttachmentsField(
            attachments: drafts,
            onAdd: () async {},
            onRemove: (_) async {},
            onReplace: (_) async {},
            onRetry: (_) async {},
            loadPreview: (_) async => null,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Attach stock invoice'), findsOneWidget);
    expect(find.textContaining('Up to 3 images'), findsOneWidget);
    expect(find.textContaining('No invoice text is read'), findsOneWidget);
    final addButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('attach-stock-invoice')),
    );
    expect(addButton.onPressed, isNull);
    expect(find.text('Attached securely'), findsNWidgets(3));
  });

  testWidgets('sale details display private stock invoice metadata',
      (tester) async {
    final sale = Sale(
      id: 'sale-a',
      amount: 2430,
      stockAmount: 1200,
      type: 'Cash',
      products: const {},
      dateAdded: DateTime(2026, 8, 24, 9),
      stockInvoices: [attachment('page-1')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SaleDetailPage(
          sale: sale,
          loadStockInvoicePreview: (_) async => Uint8List(0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stock invoices'), findsOneWidget);
    expect(find.text('page-1.jpg'), findsOneWidget);
    expect(find.text('Private invoice image'), findsOneWidget);
  });
}
