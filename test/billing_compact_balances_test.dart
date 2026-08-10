import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/wallet.dart';

void main() {
  testWidgets('Billing shows balanced visual tiles without explanatory copy', (
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

    expect(find.text('Campaign credits'), findsOneWidget);
    expect(find.text('All stores'), findsOneWidget);
    expect(find.text('Sales balance'), findsOneWidget);
    expect(find.text('Koekie Food Security'), findsOneWidget);
    expect(find.textContaining('Pays for'), findsNothing);
    expect(find.textContaining('Available for withdrawal'), findsNothing);
    expect(find.textContaining('Only for this store'), findsNothing);
    final campaign = tester.getRect(
      find.byKey(const ValueKey('billing-balance-campaign')),
    );
    final sales = tester.getRect(
      find.byKey(const ValueKey('billing-balance-sales')),
    );
    expect(campaign.top, sales.top);
    expect(campaign.height, greaterThanOrEqualTo(150));
    expect(campaign.width, greaterThan(150));
    expect(sales.width, greaterThan(150));
    expect(tester.takeException(), isNull);
  });
}
