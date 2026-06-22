import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/shared/widgets/onboarding/customer_growth_nudge.dart';

void main() {
  testWidgets('customer growth nudge shows progress before ten customers', (
    tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerGrowthNudge(
            customerCount: 4,
            onAddCustomer: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Build toward 10 customers'), findsOneWidget);
    expect(find.textContaining('4 of 10'), findsOneWidget);

    await tester.tap(find.text('Add Customer'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('customer growth nudge hides at ten customers', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomerGrowthNudge(customerCount: 10),
        ),
      ),
    );

    expect(find.text('Build toward 10 customers'), findsNothing);
  });
}
