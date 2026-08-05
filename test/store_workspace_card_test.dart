import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/settings/stores/store_workspace_card.dart';

void main() {
  testWidgets('store workspace entry makes active store and team discoverable',
      (
    tester,
  ) async {
    var tapped = false;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoreWorkspaceCard(
            activeStoreName: 'Soweto Market',
            storeCount: 2,
            role: 'owner',
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('STORES & TEAM'), findsOneWidget);
    expect(find.text('Soweto Market'), findsOneWidget);
    expect(find.text('2 stores · Owner'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Soweto Market'));
    expect(tapped, isTrue);
  });
}
