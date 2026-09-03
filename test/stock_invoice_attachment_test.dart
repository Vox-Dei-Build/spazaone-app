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

StockInvoiceAttachment pdfAttachment(String name) => StockInvoiceAttachment(
      storagePath: 'stock_invoices/store-a/sale-a/$name.pdf',
      fileName: '$name.pdf',
      contentType: 'application/pdf',
      sizeBytes: 2048,
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

  test('legacy metadata defaults to an image and PDFs round-trip', () {
    final legacy = StockInvoiceAttachment.fromMap({
      'storagePath': 'stock_invoices/store-a/sale-a/legacy.jpg',
      'fileName': 'legacy.jpg',
      'sizeBytes': 12,
    });
    final pdf =
        StockInvoiceAttachment.fromMap(pdfAttachment('supplier').toMap());

    expect(legacy.contentType, 'image/jpeg');
    expect(legacy.isImage, isTrue);
    expect(pdf.isPdf, isTrue);
    expect(pdf.toMap()['contentType'], 'application/pdf');
  });

  test('invoice validation accepts signatures and rejects spoofed files', () {
    final pdf = StockInvoiceAttachmentService.validateBytes(
      Uint8List.fromList('%PDF-1.7'.codeUnits),
      fileName: 'invoice.pdf',
    );
    final jpeg = StockInvoiceAttachmentService.validateBytes(
      Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]),
      fileName: 'invoice.jpeg',
    );
    final png = StockInvoiceAttachmentService.validateBytes(
      Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      fileName: 'invoice.png',
    );

    expect(pdf.contentType, 'application/pdf');
    expect(jpeg.contentType, 'image/jpeg');
    expect(png.contentType, 'image/png');
    expect(
      () => StockInvoiceAttachmentService.validateBytes(
        Uint8List.fromList('%PDF-1.7'.codeUnits),
        fileName: 'invoice.jpg',
      ),
      throwsA(isA<StockInvoiceValidationException>()),
    );
    expect(
      () => StockInvoiceAttachmentService.validateBytes(
        Uint8List.fromList([1, 2, 3]),
        fileName: 'invoice.pdf',
      ),
      throwsA(isA<StockInvoiceValidationException>()),
    );
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
    expect(find.textContaining('Up to 3 images or PDFs'), findsOneWidget);
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

    await tester.tap(find.text('page-1.jpg'));
    await tester.pump();
    await tester.pump();

    expect(find.text('page-1.jpg'), findsWidgets);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('sale details identify PDF invoices without loading thumbnails',
      (tester) async {
    var loads = 0;
    final sale = Sale(
      id: 'sale-a',
      amount: 100,
      stockAmount: 50,
      type: 'Cash',
      products: const {},
      dateAdded: DateTime(2026, 8, 24, 9),
      stockInvoices: [pdfAttachment('supplier')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SaleDetailPage(
          sale: sale,
          loadStockInvoicePreview: (_) async {
            loads++;
            return Uint8List.fromList('%PDF-1.7'.codeUnits);
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Private invoice PDF'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(loads, 0);
  });
}
