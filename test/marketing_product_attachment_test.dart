import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_promotion_page.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/review_and_pricing/review_and_pricing_step.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/steps/content_step.dart';
import 'package:pasella/pages/sales/widgets/marketing_overview.dart';
import 'package:pasella/services/whatsapp_capability_cache.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

void main() {
  testWidgets('Sales marketing leads with one product-first action',
      (tester) async {
    var chooseProductTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 760,
            child: MarketingOverview(
              onChooseProduct: () => chooseProductTaps++,
              campaignHistory: const Text('Previous campaigns appear here'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Promote a product'), findsOneWidget);
    expect(find.text('No message writing or channel setup.'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Choose product'), findsNWidgets(2));
    expect(find.text('Pick customers'), findsOneWidget);
    expect(find.text('Review & send'), findsOneWidget);
    expect(find.text('Campaign history'), findsOneWidget);
    expect(find.text('Templates'), findsNothing);
    expect(find.text('Create Template'), findsNothing);

    await tester.tap(find.byKey(const Key('marketing-choose-product')));
    await tester.pump();

    expect(chooseProductTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('template content explains how to continue and attach products',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final messageController = TextEditingController();
    final smsController = TextEditingController();
    final mediaController = TextEditingController();
    addTearDown(messageController.dispose);
    addTearDown(smsController.dispose);
    addTearDown(mediaController.dispose);
    String? latestMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            SizeConfig().init(context);
            return Scaffold(
              body: ContentStep(
                includeWhatsApp: true,
                includeSMS: true,
                whatsappContentController: messageController,
                smsContentController: smsController,
                mediaUrlController: mediaController,
                photoUtil: null,
                uploadingImage: false,
                onImageUploadingChanged: (_) {},
                whatsappPrice: 1,
                smsPricePerSegment: 1,
                smsSegments: 1,
                smsEncodingInfo: const SmsEncodingInfo(
                  encoding: SmsEncoding.gsm7,
                  septetLength: 0,
                  offendingCharacters: <String>{},
                ),
                onSmsPricingUpdate: (value) => latestMessage = value,
                shopName: 'Nasr General Store',
              ),
            );
          },
        ),
      ),
    );

    expect(
      find.textContaining('create a reusable message for WhatsApp approval'),
      findsOneWidget,
    );
    expect(find.text('Promotion message *'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField),
      'Fresh bread is available today.',
    );
    await tester.pump();

    expect(latestMessage, 'Fresh bread is available today.');
    expect(smsController.text, contains('Fresh bread is available today.'));
    expect(tester.takeException(), isNull);
  });

  test('linked product snapshot preserves WhatsApp catalogue availability', () {
    const product = LinkedProductRef(
      id: 'product-1',
      name: 'Fresh bread',
      sellingPrice: 18.5,
      imageUrl: 'https://example.com/bread.jpg',
      whatsappListed: true,
    );

    final restored = LinkedProductRef.fromMap(product.toMap());

    expect(restored?.id, 'product-1');
    expect(restored?.name, 'Fresh bread');
    expect(restored?.sellingPrice, 18.5);
    expect(restored?.whatsappListed, isTrue);
  });

  testWidgets('campaign review confirms the attached orderable product',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            SizeConfig().init(context);
            return const Scaffold(
              body: ReviewAndPricingStep(
                templateContent: 'Fresh bread is available today.',
                mediaUrl: null,
                shopName: 'Nasr General Store',
                sendWhatsApp: true,
                sendSMS: false,
                totalCost: 1,
                breakdown: {
                  'whatsappCount': 1,
                  'whatsappUnit': 1.0,
                },
                linkedProduct: LinkedProductRef(
                  id: 'product-1',
                  name: 'Fresh bread',
                  sellingPrice: 18.5,
                  whatsappListed: true,
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Attached product'), findsOneWidget);
    expect(find.text('Fresh bread'), findsOneWidget);
    expect(
      find.text('The Order on WhatsApp button will open this shop.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('product promotion preview resolves every automatic variable', () {
    final preview = resolvePromotionPreviewContent(
      templateContent:
          'Hi {{customerName}}, {{productName}} from {{shopName}} costs '
          '{{productPrice}}.',
      shopName: 'Nasr General Store',
      product: const LinkedProductRef(
        id: 'product-1',
        name: 'Fresh bread',
        sellingPrice: 18.5,
        whatsappListed: true,
      ),
    );

    expect(preview, startsWith('Hi [Customer Name], Fresh bread from '));
    expect(preview, contains('Nasr General Store'));
    expect(preview, contains('18,50'));
    expect(preview, isNot(contains('{{')));
  });

  test('product SMS is automatic, actionable, and one segment', () {
    final sms = buildProductPromotionSmsPreview(
      shopName: 'Koekie Food Security',
      product: const LinkedProductRef(
        id: 'cows',
        name: 'Cows',
        sellingPrice: 15000,
        whatsappListed: true,
      ),
      merchantMobileNumber: '+27 64 837 0009',
    );

    expect(
      sms,
      'Koekie Food Security: Cows is R15000.00. Call 0648370009 to '
      'order. Reply STOP to opt out.',
    );
    expect(SMSPricingUtil.calculateSegments(sms), 1);
  });

  testWidgets('campaign review shows separate automatic SMS copy',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            SizeConfig().init(context);
            return const Scaffold(
              body: ReviewAndPricingStep(
                templateContent: 'WhatsApp product card',
                smsContent: 'Call 0648370009 to order.',
                mediaUrl: null,
                shopName: 'Koekie Food Security',
                sendWhatsApp: true,
                sendSMS: true,
                totalCost: 2,
                breakdown: {
                  'whatsappCount': 1,
                  'whatsappUnit': 1.0,
                  'smsCount': 1,
                  'smsUnit': 1.0,
                  'smsSegments': 1,
                },
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('WhatsApp product card'), findsOneWidget);
    expect(find.text('Call 0648370009 to order.'), findsOneWidget);
    expect(
      find.text(
        'Each recipient receives WhatsApp if available, otherwise SMS.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('recently active customers are recommended by default', () {
    final now = DateTime(2026, 7, 14);
    final eligible = <Map<String, dynamic>>[
      {
        'id': 'recent',
        'lastTransaction': {
          'date': Timestamp.fromDate(now.subtract(const Duration(days: 12))),
        },
      },
      {
        'id': 'old',
        'lastTransaction': {
          'date': Timestamp.fromDate(now.subtract(const Duration(days: 120))),
        },
      },
    ];

    final recommended = PromotionsViewModel.recommendedCustomers(
      eligible,
      now: now,
    );

    expect(recommended.map((customer) => customer['id']), ['recent']);
  });

  test('successful product send refreshes the customer channel badge', () {
    final cache = WhatsAppCapabilityCache.instance;
    cache.reset();
    addTearDown(cache.reset);

    cache.markWhatsAppCapable('064 837 0009');

    expect(cache.hasEntry('0648370009'), isTrue);
    expect(cache.capabilityFor('+27 64 837 0009'), isTrue);
  });

  test('marketing experiment failure explains no delivery and no charge', () {
    final message = productPromotionFailureMessage(
      'WhatsApp send failed (Twilio 63032): provider limitation',
    );

    expect(message, contains('temporarily blocking marketing messages'));
    expect(message, contains('You were not charged'));
    expect(message, isNot(contains('63032')));
  });
}
