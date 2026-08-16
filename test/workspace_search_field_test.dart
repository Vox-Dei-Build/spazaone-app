import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/shared/widgets/workspace_search_field.dart';

void main() {
  testWidgets('workspace search is keyboard safe and clears consistently',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String latest = '';

    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: WorkspaceSearchField(
              controller: controller,
              hintText: 'Search products',
              semanticLabel: 'Search products by name',
              onChanged: (value) => latest = value,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'bread');
    await tester.pump();
    expect(latest, 'bread');
    expect(find.byTooltip('Clear search'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(latest, isEmpty);
  });

  testWidgets('read-only workspace search opens its destination',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceSearchField(
            hintText: 'Search customers',
            semanticLabel: 'Open customer search',
            readOnly: true,
            onTap: () => opened = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    expect(opened, isTrue);
  });
}
