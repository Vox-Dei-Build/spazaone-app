import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/app_design_preview.dart';

void main() {
  testWidgets('preview supports local phone verification and screen selection',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const AppDesignPreview());
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '0821234567');
    await tester.tap(find.text('Send sign-in code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('preview-screen-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Business name'), findsOneWidget);
    await tester.tap(find.text('Wallet & payments'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wallet-payments-hub')), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Business name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
