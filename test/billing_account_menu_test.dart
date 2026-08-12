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
    expect(find.text('Transaction history'), findsOneWidget);
    expect(find.text('Payment setup'), findsOneWidget);
    expect(find.text('Fees and limits'), findsOneWidget);
    expect(find.text('Payments, top-ups and message charges'), findsNothing);
    expect(find.text('Account used for deposits and payouts'), findsNothing);
    expect(find.text('Messaging, payment and payout costs'), findsNothing);
    final dashboard = tester.getRect(
      find.byKey(const ValueKey('billing-account-dashboard')),
    );
    final lastTile = tester.getRect(
      find.byKey(const ValueKey('billing-account-fees')),
    );
    expect(lastTile.bottom, greaterThan(dashboard.bottom - 20));
    expect(lastTile.height, greaterThan(90));

    await tester.tap(find.text('Transaction history'));
    await tester.tap(find.text('Payment setup'));
    await tester.tap(find.text('Fees and limits'));
    expect(historyTaps, 1);
    expect(bankingTaps, 1);
    expect(feesTaps, 1);
  });
}
