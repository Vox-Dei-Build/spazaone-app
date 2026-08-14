import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/wallet.dart';

void main() {
  testWidgets('balance page separates SpazaOne balance from legacy money', (
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

    expect(find.text('SpazaOne balance'), findsOneWidget);
    expect(find.text('Shared across your shops'), findsOneWidget);
    expect(
      find.text('Use this balance for customer messages and promotions.'),
      findsOneWidget,
    );
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

    expect(find.text('SpazaOne balance'), findsOneWidget);
    expect(find.text('Legacy Balance'), findsNothing);
    expect(find.byKey(const ValueKey('billing-balance-legacy')), findsNothing);
  });

  test('legacy wallet deep links map to focused destinations', () {
    expect(
      walletInitialDestination(WalletInitialTab.topUp),
      WalletInitialDestination.addMoney,
    );
    expect(
      walletInitialDestination(WalletInitialTab.withdraw),
      WalletInitialDestination.payouts,
    );
    expect(
      walletInitialDestination(WalletInitialTab.account),
      WalletInitialDestination.money,
    );
  });

  testWidgets('balance hero fits narrow screens with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.8),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BillingBalancePanel(
              campaignBalance: 100,
              salesBalance: 0,
              storeName: 'Test Shop',
              sharedCampaignCredits: true,
              onCampaignTap: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Add money'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
