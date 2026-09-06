import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotions_tab.dart';
import 'package:pasella/pages/sales/widgets/marketing_overview.dart';

void main() {
  Widget app(Widget child, {double textScale = 1}) => MaterialApp(
        theme: kCustomThemeData,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(body: child),
      );

  testWidgets(
      'campaign card keeps open and rerun actions independent at large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opens = 0;
    var reruns = 0;
    const name = 'Fresh bakery selection for the whole family this weekend';
    await tester.pumpWidget(app(
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: PromotionHistoryCard(
          name: name,
          dateLabel: '5 Sep 2026',
          status: 'complete',
          onOpen: () => opens++,
          onRunAgain: () => reruns++,
        ),
      ),
      textScale: 2,
    ));
    final title = tester.widget<Text>(find.text(name));
    expect(title.maxLines, isNull);
    expect(title.overflow, isNot(TextOverflow.ellipsis));
    await tester.ensureVisible(find.text('Run again'));
    await tester.pumpAndSettle();
    expect(
        tester
            .getSize(find.byWidgetPredicate((widget) => widget is TextButton))
            .height,
        greaterThanOrEqualTo(48));
    await tester.tap(find.text('Run again'));
    expect(reruns, 1);
    expect(opens, 0);
    await tester.ensureVisible(find.text(name));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved campaign retains the review-and-send affordance',
      (tester) async {
    var opens = 0;
    await tester.pumpWidget(app(PromotionHistoryCard(
      name: 'Bread',
      dateLabel: '5 Sep 2026',
      status: 'saved',
      onOpen: () => opens++,
    )));
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Tap to review and send'), findsOneWidget);
    expect(find.text('Run again'), findsNothing);
    await tester.tap(find.text('Bread'));
    expect(opens, 1);
  });

  testWidgets(
      'short marketing viewport scrolls its action and real history at 2x text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var chooses = 0;
    var opens = 0;
    await tester.pumpWidget(app(
      SizedBox(
        height: 120,
        child: MarketingOverview(
          onChooseProduct: () => chooses++,
          campaignHistory: ListView(
            children: [
              PromotionHistoryCard(
                name: 'Weekend offer',
                dateLabel: '5 Sep 2026',
                status: 'saved',
                onOpen: () => opens++,
              ),
            ],
          ),
        ),
      ),
      textScale: 2,
    ));
    expect(tester.takeException(), isNull);
    final outerScroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('marketing-choose-product')),
      40,
      scrollable: outerScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('marketing-choose-product')));
    expect(chooses, 1);
    await tester.scrollUntilVisible(find.text('Weekend offer'), 40,
        scrollable: outerScroll);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekend offer'));
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });
}
