import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/sales/widgets/sales_list.dart';

void main() {
  testWidgets('cash sales empty state is concise and actionable',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesListEmptyState(onAddSale: () => taps++),
        ),
      ),
    );

    expect(find.text('No recorded sales yet'), findsOneWidget);
    expect(find.text('Record sale'), findsOneWidget);
    expect(find.textContaining('day-end'), findsNothing);
    expect(find.textContaining('walkthrough'), findsNothing);

    await tester.tap(find.text('Record sale'));
    await tester.pump();
    expect(taps, 1);
  });
}
