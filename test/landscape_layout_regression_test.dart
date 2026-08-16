import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/dashboard/dashboard.dart';
import 'package:pasella/pages/stock/product_group_page/widgets/product_list.dart';
import 'package:pasella/shared/widgets/empty_state_onboarding.dart';
import 'package:pasella/shared/widgets/responsive_app_layout.dart';

Future<void> _pumpAt(
  WidgetTester tester, {
  required Size size,
  required Widget child,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('primary navigation moves to a rail on phone landscape', (
    tester,
  ) async {
    var selected = -1;
    await _pumpAt(
      tester,
      size: const Size(800, 360),
      child: ResponsiveDashboardShell(
        selectedIndex: 0,
        onDestinationSelected: (index) => selected = index,
        body: const ColoredBox(
          key: ValueKey('workspace-body'),
          color: Colors.white,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('landscape-primary-navigation')),
      findsOneWidget,
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('landscape-primary-navigation')),
          )
          .width,
      68,
    );
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).labelType,
      NavigationRailLabelType.selected,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.inventory_outlined));
    expect(selected, 1);
  });

  testWidgets('bottom navigation remains the portrait pattern', (tester) async {
    await _pumpAt(
      tester,
      size: const Size(360, 800),
      child: ResponsiveDashboardShell(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        body: const SizedBox.expand(),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape navigation survives large accessibility text', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      size: const Size(720, 320),
      textScale: 2,
      child: ResponsiveDashboardShell(
        selectedIndex: 2,
        onDestinationSelected: (_) {},
        body: const SizedBox.expand(),
      ),
    );

    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth content uses the short landscape width', (tester) async {
    await _pumpAt(
      tester,
      size: const Size(640, 320),
      child: const Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(12),
            child: ResponsiveAuthLayout(
              branding: SizedBox(
                key: ValueKey('auth-brand'),
                width: 120,
                height: 140,
              ),
              form: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Enter your mobile number to start'),
                  SizedBox(height: 12),
                  TextField(),
                  SizedBox(height: 12),
                  FilledButton(
                    key: ValueKey('continue-action'),
                    onPressed: null,
                    child: Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('landscape-auth-layout')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('continue-action'))).dy,
      lessThan(320),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty product state scrolls in a short landscape viewport', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      size: const Size(640, 240),
      textScale: 2,
      child: Scaffold(
        body: ProductListEmptyState(
          showOnboarding: true,
          onAddProduct: () {},
        ),
      ),
    );

    expect(find.text('No products yet'), findsOneWidget);
    expect(find.text('Add product'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared empty states remain recoverable in landscape', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      size: const Size(640, 240),
      textScale: 2,
      child: Scaffold(
        body: EmptyStateOnboarding(
          icon: Icons.receipt_long_outlined,
          headline: 'No recorded sales yet',
          subtitle: 'Record a sale to see it here.',
          ctaLabel: 'Record sale',
          onCtaTap: () {},
        ),
      ),
    );

    expect(find.text('No recorded sales yet'), findsOneWidget);
    expect(find.text('Record sale'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final size in <Size>[
    const Size(320, 568),
    const Size(360, 640),
    const Size(412, 915),
    const Size(640, 320),
    const Size(800, 360),
  ]) {
    testWidgets(
      'centered content is finite and scrollable at $size with large text',
      (tester) async {
        await _pumpAt(
          tester,
          size: size,
          textScale: 2,
          child: const Scaffold(
            body: ScrollableCenteredContent(
              child: SizedBox(height: 900, child: Text('Tall empty state')),
            ),
          ),
        );

        expect(
          find.byKey(
            const ValueKey('scrollable-centered-content-viewport'),
          ),
          findsOneWidget,
        );
        await tester.drag(
          find.byKey(
            const ValueKey('scrollable-centered-content-viewport'),
          ),
          const Offset(0, -200),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'list-hosted centered content delegates scrolling at $size',
      (tester) async {
        await _pumpAt(
          tester,
          size: size,
          textScale: 2,
          child: Scaffold(
            body: ListView(
              children: const [
                SizedBox(height: 80),
                ScrollableCenteredContent(
                  child: SizedBox(
                    height: 900,
                    child: Text('List-hosted empty state'),
                  ),
                ),
              ],
            ),
          ),
        );

        expect(
          find.byKey(
            const ValueKey('scrollable-centered-content-viewport'),
          ),
          findsNothing,
        );
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
