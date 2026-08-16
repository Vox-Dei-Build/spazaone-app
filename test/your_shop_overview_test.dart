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
  testWidgets('Your shop keeps management separate from setup', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: YourShopOverview(
              showStoresAndTeam: true,
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
    expect(find.text('Finish setting up your shop'), findsNothing);
    expect(find.text('Continue setup'), findsNothing);
    expect(
      find.byKey(const ValueKey('your-shop-setup-progress')),
      findsNothing,
    );
    expect(find.text('Shop link'), findsOneWidget);
    expect(find.text('Store details'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('your-shop-overview')),
      const Offset(0, -280),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stores & team'), findsOneWidget);

    expect(find.byType(Divider), findsNothing);
  });

  test('incomplete shops open setup directly from My Store', () {
    expect(workspaceShouldOpenSetup(_incomplete), isTrue);
    expect(
      workspaceShouldOpenSetup(const MerchantSetupState.loading()),
      isFalse,
    );
    expect(
      workspaceShouldOpenSetup(
        const MerchantSetupState(
          hasCustomers: true,
          hasProducts: true,
          hasListedProduct: true,
          hasOrderingLink: true,
          hasOrderingOptions: true,
          hasApprovedTemplate: true,
          hasBank: true,
          shopName: 'My Store',
          orderingUrl: 'https://example.com',
          orderingCode: 'READY',
          fallbackText: '',
          loading: false,
        ),
      ),
      isFalse,
    );
  });

  testWidgets('My Store shows compact setup progress and remains tappable',
      (tester) async {
    var storeTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceHeaderBar(
            storeName: 'My Store',
            setupProgressLabel: '2/6 setup',
            onStorePressed: () => storeTaps++,
            onShopPressed: () {},
          ),
        ),
      ),
    );

    expect(
        find.byKey(const ValueKey('workspace-setup-progress')), findsOneWidget);
    expect(find.text('2/6 setup'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workspace-store-action')));
    expect(storeTaps, 1);
    expect(
      find.bySemanticsLabel(
        'Current store, My Store. Open your shop. 2/6 setup complete',
      ),
      findsOneWidget,
    );
  });
}
