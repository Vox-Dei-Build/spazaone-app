import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/shared/widgets/workspace_date_filter.dart';

void main() {
  testWidgets('date control opens presets and exposes one accessible action',
      (tester) async {
    final semantics = tester.ensureSemantics();
    DateTime? selected;
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: Scaffold(
        body: WorkspaceDateFilter(
          selectedDay: DateTime.now(),
          startDate: null,
          endDate: null,
          onDaySelect: (day) => selected = day,
          onRangeSelect: (_, __) {},
          onClear: () {},
        ),
      ),
    ));
    expect(find.bySemanticsLabel('Change date, Today'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Change date, Today'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Today'));
    await tester.pumpAndSettle();
    expect(DateUtils.isSameDay(selected, DateTime.now()), isTrue);
    expect(find.text('Choose dates'), findsNothing);
    semantics.dispose();
  });

  testWidgets('month preset can be refined without an out-of-bounds date',
      (tester) async {
    final now = DateTime.now();
    DateTime? start;
    DateTime? end;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        return Scaffold(
          body: WorkspaceDateFilter(
            selectedDay: start == null ? now : null,
            startDate: start,
            endDate: end,
            onDaySelect: (_) {},
            onRangeSelect: (from, to) => setState(() {
              start = from;
              end = to;
            }),
            onClear: () {},
          ),
        );
      }),
    ));
    await tester.tap(find.byKey(const ValueKey('workspace-date-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This month'));
    await tester.pumpAndSettle();
    expect(start, DateTime(now.year, now.month, 1));
    expect(end, DateTime(now.year, now.month + 1, 0));

    await tester.tap(find.byKey(const ValueKey('workspace-date-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a date range'));
    await tester.pumpAndSettle();
    final picker = tester.widget<DateRangePickerDialog>(
      find.byType(DateRangePickerDialog),
    );
    expect(picker.initialDateRange!.end.isAfter(picker.lastDate), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long ranges remain readable at 200% text on a narrow phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: WorkspaceDateFilter(
            selectedDay: null,
            startDate: DateTime(2025, 12, 20),
            endDate: DateTime(2026, 1, 20),
            onDaySelect: (_) {},
            onRangeSelect: (_, __) {},
            onClear: () {},
          ),
        ),
      ),
    ));
    expect(find.text('20 Dec 2025 – 20 Jan 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
