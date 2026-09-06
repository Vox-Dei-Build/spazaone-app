import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import '../tool/app_design_preview.dart';
import '../tool/customer_design_previews.dart';
import '../tool/product_design_previews.dart';
import '../tool/commerce_design_previews.dart';
import '../tool/settings_design_previews.dart';

void main() {
  final screens = {
    ...customerDesignPreviews(),
    ...productDesignPreviews(),
    ...commerceDesignPreviews(),
    ...settingsDesignPreviews(),
  };
  for (final scale in [1.0, 2.0]) {
    for (final screen in screens.entries) {
      testWidgets('${screen.key} preview fits 320px at ${scale}x text',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          theme: kCustomThemeData,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(builder: screen.value),
        ));
        await tester.pumpAndSettle();
        if (screen.key == 'Shop setup') {
          expect(find.text('Set up your shop'), findsOneWidget);
          expect(find.text('Everyday tools'), findsOneWidget);
          expect(find.text('Add more when you’re ready'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('gallery finds a screen, tries its local controls and returns',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const AppDesignPreview());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preview-all-screens')));
    await tester.pumpAndSettle();
    expect(find.text('Explore the app'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('preview-gallery-search')), 'privacy');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preview-gallery-Privacy')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crash reports'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Example only'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Explore the app'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('preview-gallery-Privacy')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
