import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/tabs/info_center_tab.dart';

void main() {
  testWidgets('Account uses navigation rows instead of nested segments', (
    tester,
  ) async {
    var historyTaps = 0;
    var bankingTaps = 0;
    var feesTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 360,
            child: BillingAccountMenu(
              showHistory: true,
              showBanking: true,
              showFees: true,
              onHistory: () => historyTaps++,
              onBanking: () => bankingTaps++,
              onFees: () => feesTaps++,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SegmentedButton), findsNothing);
    expect(find.text('Money activity'), findsOneWidget);
    expect(find.text('Set up online payments'), findsOneWidget);
    expect(find.text('Costs and limits'), findsOneWidget);
    expect(find.text('Payments and balance activity'), findsOneWidget);
    final dashboard = tester.getRect(
      find.byKey(const ValueKey('billing-account-dashboard')),
    );
    final lastTile = tester.getRect(
      find.byKey(const ValueKey('billing-account-fees')),
    );
    expect(lastTile.bottom, lessThanOrEqualTo(dashboard.bottom));
    expect(lastTile.height, lessThan(90));

    await tester.tap(find.text('Money activity'));
    await tester.tap(find.text('Set up online payments'));
    await tester.tap(find.text('Costs and limits'));
    expect(historyTaps, 1);
    expect(bankingTaps, 1);
    expect(feesTaps, 1);
  });
}
