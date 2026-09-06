import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/promote/widgets/templates/template_picker_card.dart';
import 'package:pasella/pages/wallet/widgets/notification_tile.dart';
import '../tool/commerce_design_previews.dart';

void main() {
  for (final entry in commerceDesignPreviews().entries) {
    testWidgets('${entry.key} renders production UI at 320px and 2x text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: kCustomThemeData,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(builder: entry.value),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 4; i++) {
        final scrollable = find.byType(Scrollable).first;
        if (scrollable.evaluate().isNotEmpty) {
          await tester.drag(scrollable, const Offset(0, -350));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
    });
  }

  testWidgets(
      'online example opens local receipt and retains its monetary values',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: Builder(builder: commerceDesignPreviews()['Online orders']!),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('R275,50').first);
    await tester.pumpAndSettle();
    expect(find.text('Online receipt'), findsOneWidget);
    expect(find.text('Fees (incl VAT)'), findsOneWidget);
    expect(find.textContaining(RegExp(r'8[,.]50')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pending template remains unavailable while approved choices can change',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: Builder(builder: commerceDesignPreviews()['Templates']!),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekend offer'));
    await tester.pump();
    expect(
        tester
            .widgetList<TemplatePickerCard>(find.byType(TemplatePickerCard))
            .elementAt(1)
            .selected,
        isTrue);
    await tester.ensureVisible(find.text('New product arrival'));
    await tester.tap(find.text('New product arrival'));
    await tester.pump();
    expect(
        tester
            .widgetList<TemplatePickerCard>(find.byType(TemplatePickerCard))
            .elementAt(2)
            .selected,
        isFalse);
  });

  testWidgets(
      'message details show full text and a reachable close action at 2x',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Builder(builder: commerceDesignPreviews()['Money history']!),
    ));
    await tester.pumpAndSettle();
    for (var i = 0;
        i < 8 && find.byType(NotificationTile).hitTestable().evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byType(NotificationTile));
    await tester.pumpAndSettle();
    expect(
        find.text('Your order is ready for collection at Neighbourhood Store.'),
        findsOneWidget);
    await tester.ensureVisible(find.text('Close'));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Message details'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
