import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/wallet.dart';

void main() {
  testWidgets('Billing separates campaign credits from legacy money', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: BillingBalancePanel(
              campaignBalance: 157.58,
              salesBalance: 13663.23,
              storeName: 'Koekie Food Security',
              sharedCampaignCredits: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Campaign Credits'), findsOneWidget);
    expect(find.text('All stores'), findsOneWidget);
    expect(find.text('Legacy Balance'), findsOneWidget);
    expect(find.text('Sales balance'), findsNothing);
    expect(find.text('Koekie Food Security'), findsOneWidget);
    expect(find.textContaining('Pays for'), findsNothing);
    expect(find.textContaining('Available for withdrawal'), findsNothing);
    expect(find.textContaining('Only for this store'), findsNothing);
    final campaign = tester.getRect(
      find.byKey(const ValueKey('billing-balance-campaign')),
    );
    final legacy = tester.getRect(
      find.byKey(const ValueKey('billing-balance-legacy')),
    );
    expect(legacy.top, greaterThan(campaign.bottom));
    expect(campaign.width, greaterThan(330));
    expect(legacy.width, greaterThan(330));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Billing hides Legacy Balance after it reaches zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BillingBalancePanel(
            campaignBalance: 100,
            salesBalance: 0,
            storeName: 'Test Shop',
            sharedCampaignCredits: false,
          ),
        ),
      ),
    );

    expect(find.text('Campaign Credits'), findsOneWidget);
    expect(find.text('Legacy Balance'), findsNothing);
    expect(find.byKey(const ValueKey('billing-balance-legacy')), findsNothing);
  });
}
