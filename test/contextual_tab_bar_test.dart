import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/shared/widgets/contextual_tab_bar.dart';

Widget _subject({required double textScale}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(320, 240),
        textScaler: TextScaler.linear(textScale),
      ),
      child: const DefaultTabController(
        length: 3,
        child: Scaffold(
          body: ContextualTabBar(
            labelStyle: TextStyle(fontSize: 14),
            tabs: [
              Tab(text: 'PRODUCTS'),
              Tab(text: 'CATALOGUE'),
              Tab(text: 'REPORT'),
            ],
            action: SizedBox(
              key: ValueKey('context-action'),
              width: 48,
              height: 48,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('large text keeps contextual tabs complete and scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_subject(textScale: 2));

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.isScrollable, isTrue);
    expect(tabBar.tabAlignment, TabAlignment.start);
    expect(find.text('CATALOGUE'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('context-action'))),
      const Size(48, 48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal text keeps primary tabs evenly distributed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_subject(textScale: 1));

    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isFalse);
    expect(tester.takeException(), isNull);
  });
}
