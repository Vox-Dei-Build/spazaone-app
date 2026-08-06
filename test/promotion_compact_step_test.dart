import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/customer_selection/customer_selection_step.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/promotion_details/template_and_details_step.dart';

void main() {
  testWidgets('recipient step avoids repeating the normal channel behaviour',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            SizeConfig().init(context);
            return Scaffold(
              body: CustomerSelectionStep(
                heading: 'Choose customers',
                allCustomersLabel: 'All with a phone number',
                allCustomers: true,
                customers: const [
                  {
                    'id': 'customer-1',
                    'name': 'Lebo',
                    'number': '0648370009',
                  },
                ],
                selectedCustomerIds: const {'customer-1'},
                onAllCustomersChanged: (_) {},
                onCustomerToggle: (_) {},
                onAddCustomer: () {},
                sendWhatsApp: true,
                sendSMS: true,
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Choose customers'), findsOneWidget);
    expect(find.text('All with a phone number'), findsOneWidget);
    expect(find.textContaining('WhatsApp will be used'), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets('empty recipient step offers a compact add-customer recovery',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var addCustomerRequested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            SizeConfig().init(context);
            return Scaffold(
              body: CustomerSelectionStep(
                allCustomers: false,
                customers: const [],
                selectedCustomerIds: const {},
                hiddenWithoutNumberCount: 2,
                recommendationText: 'Recommended customers appear first.',
                onAllCustomersChanged: (_) {},
                onCustomerToggle: (_) {},
                onAddCustomer: () => addCustomerRequested = true,
              ),
            );
          },
        ),
      ),
    );

    expect(find.byKey(const Key('promotion-empty-customers')), findsOneWidget);
    expect(find.text('No customers ready'), findsOneWidget);
    expect(
      find.text(
        '2 customers need mobile numbers. Update them in Customers or add someone new.',
      ),
      findsOneWidget,
    );
    expect(find.text('All customers'), findsNothing);
    expect(find.text('Recommended customers appear first.'), findsNothing);

    await tester.tap(find.byKey(const Key('promotion-add-customer')));
    expect(addCustomerRequested, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('promotion setup uses compact section copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            SizeConfig().init(context);
            return Scaffold(
              body: TemplateAndDetailsStep(
                selectedTemplateId: 'template-1',
                onTemplateChanged: (_) {},
                sendWhatsApp: true,
                sendSMS: false,
                onWhatsAppChanged: (_) {},
                onSMSChanged: (_) {},
                templates: const [
                  {
                    'id': 'template-1',
                    'displayName': 'Weekend special',
                    'channels': {
                      'whatsapp': {
                        'approvalStatus': 'approved',
                        'templateContent': 'Weekend special from {{shopName}}',
                      },
                    },
                  },
                ],
                shopName: 'Lebo Store',
                whatsappPrice: 1,
                smsPricePerSegment: 1,
                onCreateTemplate: () {},
                linkedProduct: null,
                onLinkedProductChanged: (_) {},
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Product (optional)'), findsOneWidget);
    expect(find.text('Send via'), findsOneWidget);
    expect(find.textContaining('WhatsApp is cheaper'), findsNothing);
    expect(find.textContaining('Connect this campaign'), findsNothing);
    expect(find.textContaining('How your message will look'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
