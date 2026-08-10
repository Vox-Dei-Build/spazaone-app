import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/shared/widgets/primary_workspace_header.dart';
import 'package:pasella/shared/widgets/page_header.dart';
import 'package:pasella/shared/widgets/wallet_balance_pill.dart';

void main() {
  const storeName = 'Koekie Food Security and General Dealer';

  for (final width in <double>[320, 360, 384, 393, 411]) {
    for (final textScale in <double>[1, 2]) {
      testWidgets(
        'primary chrome protects brand at ${width.toInt()}dp and ${textScale}x text',
        (tester) async {
          tester.view.physicalSize = Size(width, 180);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 180),
                  textScaler: TextScaler.linear(textScale),
                ),
                child: Scaffold(
                  body: PageHeader(
                    actionWidget: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.help_outline),
                    ),
                    walletWidget: const WalletBalancePill(
                      presentation: WalletBalancePresentation(
                        balance: 0,
                        salesBalance: 25,
                        isShared: true,
                      ),
                    ),
                    connectivityWidget: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.cloud_done_outlined),
                    ),
                    onSettingsTap: () {},
                  ),
                ),
              ),
            ),
          );

          expect(tester.takeException(), isNull);
          final brand = find.byKey(const ValueKey('page-header-brand'));
          final wallet = find.byKey(const ValueKey('page-header-wallet'));
          expect(brand, findsOneWidget);
          expect(wallet, findsOneWidget);
          expect(tester.getSize(brand).width, greaterThanOrEqualTo(96));
          expect(tester.getSize(brand).height, 36);
          expect(tester.getSize(wallet).width, lessThanOrEqualTo(88));
          final settings = find.byKey(
            const ValueKey('page-header-settings'),
          );
          expect(settings, findsOneWidget);
          expect(
            tester.getTopLeft(settings).dx,
            greaterThan(
              tester.getTopLeft(find.byIcon(Icons.cloud_done_outlined)).dx,
            ),
          );
          expect(find.bySemanticsLabel('Spaza One'), findsOneWidget);
          expect(
            find.bySemanticsLabel(
              RegExp('shared campaign credits.*Low balance.*Top Up'),
            ),
            findsOneWidget,
          );
          expect(
            find.byIcon(Icons.account_balance_wallet_outlined),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
        },
      );
    }
  }

  for (final width in <double>[320, 360, 384]) {
    for (final textScale in <double>[1, 1.3, 2]) {
      testWidgets(
        'workspace header fits ${width.toInt()}dp at ${textScale}x text',
        (tester) async {
          tester.view.physicalSize = Size(width, 260);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 260),
                  textScaler: TextScaler.linear(textScale),
                ),
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: WorkspaceHeaderBar(
                      storeName: storeName,
                      onStorePressed: () {},
                      onShopPressed: () {},
                    ),
                  ),
                ),
              ),
            ),
          );

          expect(tester.takeException(), isNull);

          final store = find.byKey(
            const ValueKey('workspace-store-action'),
          );
          final shop = find.byKey(
            const ValueKey('workspace-shop-action'),
          );
          expect(store, findsOneWidget);
          expect(shop, findsOneWidget);
          expect(tester.getSize(store).height, greaterThanOrEqualTo(48));
          expect(tester.getSize(shop).height, greaterThanOrEqualTo(48));
          expect(
            tester.getTopLeft(store).dx,
            lessThan(tester.getTopLeft(shop).dx),
          );
        },
      );
    }
  }

  testWidgets('workspace actions expose full context and remain tappable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var storeTaps = 0;
    var shopTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: WorkspaceHeaderBar(
              storeName: storeName,
              onStorePressed: () => storeTaps++,
              onShopPressed: () => shopTaps++,
            ),
          ),
        ),
      ),
    );

    final store = find.bySemanticsLabel(
      'Current store, $storeName. Open stores and team',
    );
    final shop = find.bySemanticsLabel(
      'Open $storeName WhatsApp ordering link',
    );
    expect(store, findsOneWidget);
    expect(shop, findsOneWidget);

    await tester.tap(store);
    await tester.tap(shop);
    expect(storeTaps, 1);
    expect(shopTaps, 1);
  });

  testWidgets('store context becomes read-only when switching is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceHeaderBar(
            storeName: storeName,
            onStorePressed: null,
            onShopPressed: () {},
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('Current store, $storeName'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('rollback hides a synthetic store identity', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceHeaderBar(
            storeName: 'My Store',
            showStoreContext: false,
            onStorePressed: null,
            onShopPressed: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('workspace-store-action')),
      findsNothing,
    );
    expect(find.text('My Store'), findsNothing);
    expect(
      find.bySemanticsLabel('Open your WhatsApp ordering link'),
      findsOneWidget,
    );
  });
}
