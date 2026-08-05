import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/promotion_bottom_action.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/review_and_pricing/review_and_pricing_step.dart';
import 'package:pasella/shared/billing/wallet_affordability_footer.dart';

void main() {
  testWidgets('promotion action clears the system navigation inset',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 720),
            padding: EdgeInsets.only(bottom: 32),
            viewPadding: EdgeInsets.only(bottom: 32),
          ),
          child: Scaffold(
            bottomNavigationBar: PromotionBottomAction(
              child: SizedBox(
                key: const Key('review-action'),
                height: 48,
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Review promotion'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final actionBottom = tester
        .getBottomRight(
          find.byKey(const Key('review-action')),
        )
        .dy;
    expect(actionBottom, lessThanOrEqualTo(720 - 32));
  });

  testWidgets('scaffold keeps promotion action above the keyboard',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 720),
            viewInsets: EdgeInsets.only(bottom: 280),
          ),
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            bottomNavigationBar: PromotionBottomAction(
              child: SizedBox(
                key: const Key('continue-action'),
                height: 48,
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Continue'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final actionBottom = tester
        .getBottomRight(
          find.byKey(const Key('continue-action')),
        )
        .dy;
    expect(actionBottom, lessThanOrEqualTo(720 - 280));
  });

  testWidgets('review footer cannot expand over the promotion body',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 720),
            padding: EdgeInsets.only(top: 24, bottom: 24),
            viewPadding: EdgeInsets.only(top: 24, bottom: 24),
          ),
          child: Scaffold(
            appBar: AppBar(title: const Text('Promote product')),
            body: const Center(
              child: SizedBox(
                key: Key('review-body'),
                height: 240,
                child: Text('Ready to send'),
              ),
            ),
            bottomNavigationBar: PromotionBottomAction(
              child: WalletAffordabilityFooter.test(
                balance: 157.58,
                cost: 7.22,
                confirmLabel: 'Send promotion',
                confirmIcon: Icons.send_rounded,
                onBack: () {},
                onConfirm: _noop,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('review-body'))).height, 240);
    expect(
      tester.getTopLeft(find.text('Send promotion')).dy,
      greaterThan(560),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('send review stays usable at 320px with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            padding: EdgeInsets.only(top: 24, bottom: 24),
            viewPadding: EdgeInsets.only(top: 24, bottom: 24),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Builder(
            builder: (context) {
              SizeConfig().init(context);
              return Scaffold(
                appBar: AppBar(title: const Text('Promote product')),
                body: const ReviewAndPricingStep(
                  templateContent: 'A premium product from {{shopName}}.',
                  smsContent: 'Call the shop to order.',
                  mediaUrl: null,
                  shopName: 'Spaza One Store',
                  sendWhatsApp: true,
                  sendSMS: true,
                  totalCost: 7.22,
                  breakdown: {
                    'whatsappCount': 2,
                    'whatsappUnit': 1.0,
                    'smsCount': 2,
                    'smsUnit': 1.11,
                    'smsSegments': 1,
                    'unknownCount': 1,
                    'unknownUnit': 3.0,
                  },
                ),
                bottomNavigationBar: PromotionBottomAction(
                  child: WalletAffordabilityFooter.test(
                    balance: 157.58,
                    cost: 7.22,
                    confirmLabel: 'Send promotion',
                    confirmIcon: Icons.send_rounded,
                    onBack: () {},
                    onConfirm: _noop,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('promotion-review-content')), findsOneWidget);
    expect(find.byKey(const Key('promotion-review-summary')), findsOneWidget);
    expect(find.text('Ready to send'), findsOneWidget);
    expect(find.text('Send promotion'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('promotion-review-summary'))).dy,
      greaterThan(70),
    );
    expect(
      tester.getBottomRight(find.text('Send promotion')).dy,
      lessThanOrEqualTo(568 - 24),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _noop() async {}
