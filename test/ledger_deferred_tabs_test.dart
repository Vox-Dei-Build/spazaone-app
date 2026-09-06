import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/ledger/widgets/ledger_main_content.dart';

void main() {
  testWidgets('report content is not built before its tab is selected', (
    tester,
  ) async {
    final selectedTab = ValueNotifier<int>(0);
    addTearDown(selectedTab.dispose);
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: LedgerDeferredTab(
          tabIndexNotifier: selectedTab,
          tabIndex: 1,
          builder: (_) {
            builds++;
            return const Text('Activity report');
          },
        ),
      ),
    );

    expect(builds, 0);
    expect(find.text('Activity report'), findsNothing);

    selectedTab.value = 1;
    await tester.pump();

    expect(builds, 1);
    expect(find.text('Activity report'), findsOneWidget);

    selectedTab.value = 0;
    await tester.pump();

    expect(builds, 1);
    expect(find.text('Activity report'), findsOneWidget);
  });

  testWidgets('swiping to a report tab activates its deferred content', (
    tester,
  ) async {
    final selectedTab = ValueNotifier<int>(0);
    addTearDown(selectedTab.dispose);
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: const TabBar(
                tabs: [Tab(text: 'Customers'), Tab(text: 'Activity')]),
            body: TabBarView(
              children: [
                const Text('Customer list'),
                LedgerDeferredTab(
                  tabIndexNotifier: selectedTab,
                  tabIndex: 1,
                  builder: (_) {
                    builds++;
                    return const Text('Activity report');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(builds, 0);

    await tester.drag(find.byType(TabBarView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(builds, greaterThanOrEqualTo(1));
    expect(find.text('Activity report'), findsOneWidget);
  });
}
