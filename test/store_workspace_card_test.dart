import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/settings/stores/store_management_page.dart';
import 'package:pasella/pages/settings/stores/store_workspace_card.dart';

void main() {
  testWidgets('store entry shows a long active name at 320px with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const name = 'Soweto Market and Community Grocery Store';
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              StoreWorkspaceCard(
                activeStoreName: name,
                storeCount: 2,
                role: 'owner',
                onTap: () {},
              ),
              const ActiveStoreSummary(storeName: name, role: 'Owner'),
            ],
          ),
        ),
      ),
    ));
    expect(find.text(name), findsNWidgets(2));
    for (final nameText in tester.widgetList<Text>(find.text(name))) {
      expect(nameText.maxLines, isNull);
    }
    expect(find.text('Active store · Owner'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

    expect(find.text('Stores & team'), findsOneWidget);
    expect(find.text('Soweto Market'), findsOneWidget);
    expect(find.text('2 stores · Owner'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Soweto Market'));
    expect(tapped, isTrue);
  });

  testWidgets('store workspace uses truthful loading and retry states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoreWorkspaceCard(
            activeStoreName: 'Loading stores…',
            storeCount: 0,
            role: 'owner',
            loading: true,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Loading stores…'), findsOneWidget);
    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.text('My Store'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoreWorkspaceCard(
            activeStoreName: 'Stores unavailable',
            storeCount: 0,
            role: 'owner',
            connectionIssue: true,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Stores unavailable'), findsOneWidget);
    expect(find.text('Tap to reconnect'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('My Store'), findsNothing);
  });
}
