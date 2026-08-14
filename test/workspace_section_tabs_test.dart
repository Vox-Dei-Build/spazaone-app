import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/shared/widgets/workspace_section_tabs.dart';

Widget _subject({required double textScale}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          body: Column(
            children: const [
              WorkspaceSectionTabs(
                tabs: [
                  WorkspaceSectionTab(
                    label: 'Recorded sales',
                    semanticLabel: 'Recorded sales',
                  ),
                  WorkspaceSectionTab(
                    label: 'Online orders',
                    semanticLabel: 'Online orders',
                  ),
                  WorkspaceSectionTab(
                    label: 'Marketing',
                    semanticLabel: 'Marketing',
                  ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    Center(child: Text('Recorded content')),
                    Center(child: Text('Online content')),
                    Center(child: Text('Marketing content')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final width in <double>[320, 360]) {
    for (final scale in <double>[1, 2]) {
      testWidgets(
        'all workspace destinations remain visible at ${width.toInt()}dp and ${scale}x',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 640));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(_subject(textScale: scale));

          expect(find.text('Recorded sales'), findsOneWidget);
          expect(find.text('Online orders'), findsOneWidget);
          expect(find.text('Marketing'), findsOneWidget);
          expect(tester.takeException(), isNull);

          final surface = tester.widget<Container>(
            find.byKey(const ValueKey('workspace-section-tabs')),
          );
          final decoration = surface.decoration! as BoxDecoration;
          expect(decoration.border, isNull);
          expect(decoration.borderRadius, isNotNull);
          expect(decoration.color, isNotNull);

          await tester.tap(find.text('Online orders'));
          await tester.pumpAndSettle();
          expect(find.text('Online content'), findsOneWidget);
        },
      );
    }
  }
}
