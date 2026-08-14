import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/settings/setup/your_shop_page.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_setup_state.dart';
import 'package:pasella/shared/widgets/primary_workspace_header.dart';

const _incomplete = MerchantSetupState(
  hasCustomers: true,
  hasProducts: true,
  hasListedProduct: false,
  hasOrderingLink: false,
  hasApprovedTemplate: false,
  hasBank: false,
  shopName: 'My Store',
  orderingUrl: '',
  orderingCode: '',
  fallbackText: '',
  loading: false,
);

void main() {
  testWidgets('Your shop exposes setup and shop destinations without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var setupTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: YourShopOverview(
              state: _incomplete,
              showStoresAndTeam: true,
              onSetup: () => setupTaps++,
              onShopLink: () {},
              onStoreDetails: () {},
              onStoresAndTeam: () {},
              onOnlinePayments: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Finish setting up your shop'), findsOneWidget);
    expect(find.text('2 of 6 done'), findsOneWidget);
    expect(find.text('Shop link'), findsOneWidget);
    expect(find.text('Store details'), findsOneWidget);
    expect(find.text('Stores & team'), findsOneWidget);
    expect(find.text('Online payments'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('your-shop-setup-progress')));
    expect(setupTaps, 1);
  });

  testWidgets('My Store shows compact setup progress and remains tappable',
      (tester) async {
    var storeTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceHeaderBar(
            storeName: 'My Store',
            setupProgressLabel: '2/6',
            onStorePressed: () => storeTaps++,
            onShopPressed: () {},
          ),
        ),
      ),
    );

    expect(
        find.byKey(const ValueKey('workspace-setup-progress')), findsOneWidget);
    expect(find.text('2/6'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workspace-store-action')));
    expect(storeTaps, 1);
    expect(
      find.bySemanticsLabel(
        'Current store, My Store. Open your shop. Setup 2/6 complete',
      ),
      findsOneWidget,
    );
  });
}
