import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/models/stock/whatsapp_catalog_status.dart';
import 'package:pasella/pages/stock/stock.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/services/whatsapp_catalog_status_service.dart';
import 'package:provider/provider.dart';

class _MemoryStoreStorage implements StoreSessionStorage {
  @override
  Future<void> clearStores(String uid) async {}
  @override
  String? readActiveStore(String uid) => null;
  @override
  List<StoreMembership> readStores(String uid) => const [];
  @override
  Future<void> writeActiveStore(String uid, String storeId) async {}
  @override
  Future<void> writeStores(String uid, List<StoreMembership> stores) async {}
}

StoreSession _session() => StoreSession.testing(
      userIdProvider: () => 'store-a',
      bootstrapLoader: () async => const <String, dynamic>{},
      storage: _MemoryStoreStorage(),
      multiStoreEnabled: false,
    );

class _CountingCatalogController extends WhatsAppCatalogStatusController {
  _CountingCatalogController(StoreSession session, {bool showStatus = false})
      : super(storeSession: session, enabled: () => showStatus);

  int refreshCount = 0;
  bool disposed = false;
  bool? resetPollingOnRefresh;

  @override
  Future<void> refresh({bool resetPolling = false}) async {
    expect(disposed, isFalse, reason: 'A removed workspace must not refresh.');
    refreshCount++;
    resetPollingOnRefresh = resetPolling;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

Map<String, dynamic> _statusPage() => {
      'schemaVersion': 2,
      'checkedAtMs': 1000,
      'freshUntilMs': 301000,
      'rollout': 'enabled',
      'summary': <String, dynamic>{},
      'products': <dynamic>[],
      'catalogVersion': 'version-a',
    };

void main() {
  Future<({ValueNotifier<bool> visible, _CountingCatalogController catalog})>
      pumpWorkspace(WidgetTester tester, {bool showStatus = false}) async {
    final session = _session();
    final catalog = _CountingCatalogController(session, showStatus: showStatus);
    if (showStatus) {
      catalog.snapshot = WhatsAppCatalogSnapshot.fromMap(_statusPage());
    }
    final visible = ValueNotifier(true);
    addTearDown(session.dispose);
    addTearDown(visible.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: kCustomThemeData,
      home: ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (_, show, __) => show
            ? MultiProvider(
                providers: [
                  ChangeNotifierProvider<StockViewModel>(
                    create: (_) => StockViewModel(
                      userId: 'store-a',
                      productsStream: Stream.value([
                        Product(id: 'bread', name: 'Bread', quantity: 4),
                      ]),
                    ),
                  ),
                  ChangeNotifierProvider<WhatsAppCatalogStatusController>(
                    create: (_) => catalog,
                  ),
                ],
                child: StockPageContent(
                  header: const SizedBox.shrink(),
                  supplierCatalog: const SizedBox.shrink(),
                  newProductBuilder: (context) => Scaffold(
                    appBar: AppBar(title: const Text('New product route')),
                    body: Center(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Save and return'),
                      ),
                    ),
                  ),
                ),
              )
            : const Scaffold(body: Text('Workspace removed')),
      ),
    ));
    await tester.pumpAndSettle();
    return (visible: visible, catalog: catalog);
  }

  for (final save in [false, true]) {
    testWidgets(
        '${save ? 'saving' : 'back from'} Add product refreshes the workspace-owned catalogue',
        (tester) async {
      final state = await pumpWorkspace(tester);
      await tester.tap(find.byKey(const ValueKey('add-product-action')));
      await tester.pumpAndSettle();
      expect(find.text('New product route'), findsOneWidget);
      expect(state.catalog.refreshCount, 0);

      if (save) {
        await tester.tap(find.text('Save and return'));
      } else {
        await tester.pageBack();
      }
      await tester.pumpAndSettle();

      expect(state.catalog.refreshCount, 1);
      expect(state.catalog.resetPollingOnRefresh, isTrue);
      expect(find.byKey(const ValueKey('add-product-action')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'return after removing Stock workspace does not touch disposed state',
      (tester) async {
    final state = await pumpWorkspace(tester);
    await tester.tap(find.byKey(const ValueKey('add-product-action')));
    await tester.pumpAndSettle();

    state.visible.value = false;
    await tester.pumpAndSettle();
    expect(state.catalog.disposed, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Workspace removed'), findsOneWidget);
    expect(state.catalog.refreshCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'catalogue summary scrolls away on narrow screens with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpWorkspace(tester, showStatus: true);
    expect(find.text('WhatsApp catalogue'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Bread'),
      150,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('product-catalogue-scroll')),
        matching: find.byWidgetPredicate((widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bread').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    testWidgets(
        'catalogue ${fails ? 'error' : 'response'} after dispose is ignored',
        (tester) async {
      final session = _session();
      addTearDown(session.dispose);
      final response = Completer<Map<String, dynamic>>();
      var requests = 0;
      final controller = WhatsAppCatalogStatusController(
        enabled: () => true,
        storeSession: session,
        service: WhatsAppCatalogStatusService(
          userIdProvider: () => '',
          pageLoader: ({required storeId, required pageSize, pageToken}) {
            requests++;
            return response.future;
          },
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      controller.start();
      await tester.pump();
      expect(requests, 1);
      controller.dispose();

      if (fails) {
        response.completeError(StateError('Delayed service failure'));
      } else {
        response.complete(_statusPage());
      }
      await tester.pumpAndSettle();
      await controller.refresh(resetPolling: true);

      expect(controller.snapshot, isNull);
      expect(requests, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
