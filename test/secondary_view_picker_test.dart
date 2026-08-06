import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/shared/widgets/secondary_view_picker.dart';

enum _ExampleView { dated, summary }

Widget _subject({
  required double textScale,
  required _ExampleView value,
  required ValueChanged<_ExampleView> onSelected,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(320, 568),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: SecondaryViewPicker<_ExampleView>(
          key: const ValueKey('subject-view-picker'),
          semanticLabel: 'Report view',
          value: value,
          options: const [
            SecondaryViewOption(
              value: _ExampleView.dated,
              label: 'Date view',
              icon: Icons.receipt_long_outlined,
            ),
            SecondaryViewOption(
              value: _ExampleView.summary,
              label: 'Summary',
              icon: Icons.account_balance_wallet_outlined,
            ),
          ],
          onSelected: onSelected,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('narrow accessibility layout stays quiet and overflow-free', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _subject(
        textScale: 2,
        value: _ExampleView.dated,
        onSelected: (_) {},
      ),
    );

    expect(find.byType(SegmentedButton<_ExampleView>), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Date view'), findsOneWidget);
    expect(find.text('VIEW'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp(r'Report view: Date view')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(PopupMenuButton<_ExampleView>)).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('menu exposes both secondary views and changes selection', (
    tester,
  ) async {
    var selected = _ExampleView.dated;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return _subject(
            textScale: 1,
            value: selected,
            onSelected: (value) {
              setState(() {
                selected = value;
              });
            },
          );
        },
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<_ExampleView>));
    await tester.pumpAndSettle();

    expect(find.text('Date view'), findsNWidgets(2));
    expect(find.text('Summary'), findsOneWidget);

    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();

    expect(selected, _ExampleView.summary);
    expect(find.text('Summary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
