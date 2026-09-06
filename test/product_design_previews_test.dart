import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/pages/stock/widgets/whatsapp_listing_preview.dart';
import '../tool/product_design_previews.dart';

void main() {
  for (final entry in productDesignPreviews().entries) {
    for (final large in [false, true]) {
      testWidgets(
          '${entry.key} preview uses production presentation without services${large ? ' with large text' : ''}',
          (tester) async {
        final size = large ? const Size(320, 568) : const Size(390, 844);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          theme: kCustomThemeData,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
            child: child!,
          ),
          home: Builder(builder: entry.value),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('search preview opens the selected product identity',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: kCustomThemeData,
        home: Builder(builder: productDesignPreviews()['Product search']!)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'milk');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Cream Milk · 1 L'));
    await tester.pumpAndSettle();
    final nameField = tester.widget<CustomTextField>(find.byWidgetPredicate(
        (widget) =>
            widget is CustomTextField && widget.label == 'Product name*'));
    expect(nameField.controller!.text, 'Full cream milk · 1 L');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Add product shows listing control first and keeps preview optional',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: Builder(builder: productDesignPreviews()['Add product']!),
    ));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('whatsapp-listing-toggle'));
    final name = find.byWidgetPredicate((widget) =>
        widget is CustomTextField && widget.label == 'Product name*');
    final price = find.byWidgetPredicate((widget) =>
        widget is CustomTextField && widget.label == 'Selling price*');
    expect(toggle.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(toggle).dy, lessThan(tester.getTopLeft(name).dy));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.byKey(const ValueKey('wa-image-required-cue')), findsOneWidget);
    expect(find.byType(WhatsappListingPreview), findsNothing);
    expect(tester.widget<CustomTextField>(price).validator!('0'),
        'Enter a price above zero for WhatsApp listings');

    await tester.ensureVisible(find.text('Preview WhatsApp listing'));
    await tester.tap(find.text('Preview WhatsApp listing'));
    await tester.pumpAndSettle();
    expect(find.byType(WhatsappListingPreview), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
