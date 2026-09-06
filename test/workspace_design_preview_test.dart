import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/workspace_design_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (var page = 0; page < 3; page++) {
    final name = ['activity', 'products', 'sales'][page];
    for (final narrow in [false, true]) {
      testWidgets(
          '$name workspace fits ${narrow ? 'small phone with large text' : 'portrait phone'}',
          (tester) async {
        final size = narrow ? const Size(320, 568) : const Size(390, 844);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(
              size: size, textScaler: TextScaler.linear(narrow ? 2 : 1)),
          child: WorkspaceDesignPreview(initialPage: page),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('DESIGN PREVIEW · EXAMPLE DATA'), findsOneWidget);
      });
    }
  }

  testWidgets('preview supports navigation, stock filtering and sales details',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const WorkspaceDesignPreview());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('product-filter-low')));
    await tester.pumpAndSettle();
    expect(find.text('Full Cream Milk · 1 L'), findsOneWidget);
    expect(find.text('Maize Meal · 2.5 Kg'), findsNothing);
    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sales-summary-details')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
