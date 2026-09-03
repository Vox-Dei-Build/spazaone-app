import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/models/stock/whatsapp_catalog_status.dart';
import 'package:pasella/pages/stock/product_group_page/widgets/product_list.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';

WhatsAppCatalogSnapshot snapshotWith(String status) {
  return WhatsAppCatalogSnapshot.fromMap({
    'schemaVersion': 2,
    'checkedAtMs': 1000,
    'freshUntilMs': 301000,
    'rollout': 'enabled',
    'summary': {
      'totalProducts': 1,
      'eligible': 1,
      'live': status == 'live' ? 1 : 0,
      'syncing': status == 'syncing' ? 1 : 0,
      'needsAttention': 0,
      'removalSyncing': 0,
      'supportReview': 0,
      'canBrowseFive': false,
      'canBrowseTen': false,
    },
    'products': [
      {
        'productId': 'bread',
        'status': status,
        'reasonCodes': const <String>[],
        'action': 'none',
        'updatedAtMs': 1000,
      },
    ],
    'catalogVersion': 'version-a',
  });
}

void main() {
  Future<void> pumpList(
    WidgetTester tester, {
    WhatsAppCatalogSnapshot? snapshot,
  }) async {
    final product = Product(
      id: 'bread',
      name: 'Bread',
      sellingPrice: 18,
      quantity: 5,
      whatsappListed: true,
    );
    final viewModel = StockViewModel(
      userId: 'store-a',
      productsStream: Stream.value([product]),
    );
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductList(
            viewModel: viewModel,
            catalogSnapshot: snapshot,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a local listing request is never labelled Online',
      (tester) async {
    await pumpList(tester);

    expect(find.text('WhatsApp listing requested'), findsOneWidget);
    expect(find.text('Online'), findsNothing);
  });

  testWidgets('server-confirmed products are labelled live on WhatsApp',
      (tester) async {
    await pumpList(tester, snapshot: snapshotWith('live'));

    expect(find.text('Live on WhatsApp'), findsOneWidget);
    expect(find.text('WhatsApp listing requested'), findsNothing);
  });
}
