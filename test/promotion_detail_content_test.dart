import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/widgets/promotions/view_promotion/promotion_detail_content.dart';

void main() {
  test('legacy completed campaigns infer successful delivery totals', () {
    final summary = PromotionDeliverySummary.fromPromo({
      'status': 'complete',
      'customerIds': ['one', 'two'],
    });

    expect(summary.recipients, 2);
    expect(summary.attempted, 2);
    expect(summary.succeeded, 2);
    expect(summary.failed, 0);
  });

  test('current campaigns use persisted delivery totals', () {
    final summary = PromotionDeliverySummary.fromPromo({
      'status': 'partial',
      'customerIds': ['one', 'two', 'three'],
      'attemptedCount': 3,
      'succeededCount': 1,
      'failedCount': 2,
    });

    expect(summary.recipients, 3);
    expect(summary.attempted, 3);
    expect(summary.succeeded, 1);
    expect(summary.failed, 2);
  });

  testWidgets('campaign detail leads with outcome and compact report sections',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            SizeConfig().init(context);
            return Scaffold(
              body: PromotionDetailContent(
                promo: {
                  'status': 'partial',
                  'createdAt':
                      Timestamp.fromDate(DateTime(2026, 7, 14, 16, 55)),
                  'customerIds': const ['customer-1', 'customer-2'],
                  'attemptedCount': 2,
                  'succeededCount': 1,
                  'failedCount': 1,
                  'actualCost': 1.5,
                  'sendWhatsApp': true,
                  'sendSMS': true,
                  'linkedProduct': const {
                    'id': 'cows',
                    'name': 'Cows',
                    'sellingPrice': 15000,
                    'whatsappListed': true,
                  },
                },
                templateContent:
                    '{{productName}} from {{shopName}} is now available.',
                shopName: 'Koekie Food Security',
                estimatedCost: 2,
                customers: const [
                  {
                    'id': 'customer-1',
                    'name': 'Tsepo',
                    'number': '0648370009',
                  },
                ],
                selectedCustomerIds: const {'customer-1', 'customer-2'},
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Partially sent'), findsOneWidget);
    expect(find.text('1 delivered • 1 failed.'), findsOneWidget);
    expect(find.text('Product'), findsOneWidget);
    expect(find.text('Cows'), findsWidgets);
    expect(find.text('Delivery'), findsOneWidget);
    expect(find.text('Campaign cost'), findsOneWidget);
    expect(find.text('R1,50'), findsOneWidget);
    expect(find.text('SMS fallback'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(
      find.text('Cows from Koekie Food Security is now available.'),
      findsOneWidget,
    );
    expect(find.text('Recipients'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
