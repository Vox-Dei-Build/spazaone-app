import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/models/stock/whatsapp_catalog_status.dart';
import 'package:pasella/pages/stock/widgets/whatsapp_catalog_status_card.dart';
import 'package:pasella/services/whatsapp_catalog_status_service.dart';
import 'package:pasella/services/store_session.dart';

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
  Future<void> writeStores(
    String uid,
    List<StoreMembership> stores,
  ) async {}
}

Map<String, dynamic> page({
  required List<Map<String, dynamic>> products,
  String? token,
  String version = 'version-a',
}) =>
    {
      'schemaVersion': 2,
      'checkedAtMs': 1000,
      'freshUntilMs': 301000,
      'rollout': 'enabled',
      'summary': {
        'totalProducts': 2,
        'eligible': 2,
        'live': 1,
        'syncing': 1,
        'needsAttention': 0,
        'removalSyncing': 0,
        'supportReview': 0,
        'canBrowseFive': false,
        'canBrowseTen': false,
      },
      'products': products,
      'nextPageToken': token,
      'catalogVersion': version,
      'retryPermitted': false,
    };

Map<String, dynamic> product(String id, String status) => {
      'productId': id,
      'status': status,
      'reasonCodes': const <String>[],
      'action': 'none',
      'updatedAtMs': 1000,
    };

WhatsAppCatalogSnapshot summarySnapshot({
  required int live,
  WhatsAppCatalogRollout rollout = WhatsAppCatalogRollout.enabled,
}) {
  final checked = DateTime(2026, 9, 3, 12).millisecondsSinceEpoch;
  return WhatsAppCatalogSnapshot(
    checkedAtMs: checked,
    freshUntilMs: checked + const Duration(minutes: 5).inMilliseconds,
    rollout: rollout,
    summary: WhatsAppCatalogSummary(
      totalProducts: live,
      eligible: live,
      live: live,
      syncing: 0,
      needsAttention: 0,
      removalSyncing: 0,
      supportReview: 0,
      canBrowseFive: live >= 5,
      canBrowseTen: live >= 10,
    ),
    products: const [],
    catalogVersion: 'version-$live',
  );
}

WhatsAppCatalogStatusController summaryController(
  WhatsAppCatalogSnapshot snapshot,
) =>
    WhatsAppCatalogStatusController(
      enabled: () => true,
      storeSession: StoreSession.testing(
        userIdProvider: () => 'owner-a',
        bootstrapLoader: () async => const <String, dynamic>{},
        storage: _MemoryStoreStorage(),
      ),
    )..snapshot = snapshot;

void main() {
  test('unknown server status fails closed to support review', () {
    final state = WhatsAppCatalogProductState.fromMap({
      ...product('bread', 'future_provider_state'),
      'action': 'refresh',
    });

    expect(state.status, WhatsAppCatalogProductStatus.supportReview);
    expect(state.action, WhatsAppCatalogProductAction.contactSupport);
    expect(state.reasonCodes, ['unknown_status']);
  });

  test('service loads and merges every page', () async {
    final requestedTokens = <String?>[];
    final service = WhatsAppCatalogStatusService(
      userIdProvider: () => '',
      pageLoader: ({required storeId, required pageSize, pageToken}) async {
        requestedTokens.add(pageToken);
        return pageToken == null
            ? page(products: [product('a', 'live')], token: 'next')
            : page(products: [product('b', 'syncing')]);
      },
    );

    final result = await service.fetch('store-a');

    expect(requestedTokens, [null, 'next']);
    expect(result.products.map((item) => item.productId), ['a', 'b']);
    expect(result.productsById['a']?.status, WhatsAppCatalogProductStatus.live);
  });

  test('service restarts pagination once when catalogue changes', () async {
    var firstPageCalls = 0;
    var shouldDrift = true;
    final service = WhatsAppCatalogStatusService(
      userIdProvider: () => '',
      pageLoader: ({required storeId, required pageSize, pageToken}) async {
        if (pageToken == null) {
          firstPageCalls++;
          return page(products: [product('a', 'live')], token: 'next');
        }
        if (shouldDrift) {
          shouldDrift = false;
          throw const WhatsAppCatalogChangedException();
        }
        return page(products: [product('b', 'syncing')]);
      },
    );

    final result = await service.fetch('store-a');

    expect(firstPageCalls, 2);
    expect(result.products, hasLength(2));
  });

  test('cache is isolated by user and store and expires after 24 hours',
      () async {
    final directory = await Directory.systemTemp.createTemp('wa-status-test');
    Hive.init(directory.path);
    final box = await Hive.openBox<dynamic>('wa-status-test-box');
    addTearDown(() async {
      await box.close();
      await directory.delete(recursive: true);
    });
    var userId = 'owner-a';
    final service = WhatsAppCatalogStatusService(
      cache: box,
      userIdProvider: () => userId,
      pageLoader: ({required storeId, required pageSize, pageToken}) async =>
          page(products: const []),
    );
    final snapshot = WhatsAppCatalogSnapshot.fromMap(page(products: const []));
    await service.writeCache('store-a', snapshot);

    expect(await service.readCache('store-a'), isNotNull);
    expect(await service.readCache('store-b'), isNull);
    userId = 'owner-b';
    expect(await service.readCache('store-a'), isNull);
    userId = 'owner-a';
    expect(
      await service.readCache(
        'store-a',
        now: DateTime.now().add(const Duration(hours: 25)),
      ),
      isNull,
    );
  });

  testWidgets('a late response cannot replace the newly selected store',
      (tester) async {
    final storeAResponse = Completer<Map<String, dynamic>>();
    final session = StoreSession.testing(
      userIdProvider: () => 'owner-a',
      bootstrapLoader: () async => {
        'stores': [
          const StoreMembership(
            storeId: 'store-a',
            storeName: 'Store A',
            role: StoreRole.owner,
          ).toMap(),
          const StoreMembership(
            storeId: 'store-b',
            storeName: 'Store B',
            role: StoreRole.owner,
          ).toMap(),
        ],
      },
      storage: _MemoryStoreStorage(),
    );
    await session.bootstrap();
    final service = WhatsAppCatalogStatusService(
      userIdProvider: () => '',
      pageLoader: ({required storeId, required pageSize, pageToken}) {
        if (storeId == 'store-a') return storeAResponse.future;
        return Future.value(page(products: [product('store-b-item', 'live')]));
      },
    );
    final controller = WhatsAppCatalogStatusController(
      service: service,
      storeSession: session,
      enabled: () => true,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    controller.start();
    await tester.pump();
    await session.selectStore('store-b');
    await tester.pumpAndSettle();

    expect(controller.snapshot?.products.single.productId, 'store-b-item');
    storeAResponse.complete(page(products: [product('store-a-item', 'live')]));
    await tester.pumpAndSettle();
    expect(controller.snapshot?.products.single.productId, 'store-b-item');
  });

  for (final expectation in <(int, String)>[
    (4, 'Add 1 more valid product to reach a five-product view.'),
    (5, 'Ready for WhatsApp browsing. Add 5 more for a ten-product view.'),
    (
      10,
      'Customers can browse 10 products at a time and continue to see more.'
    ),
  ]) {
    testWidgets('summary guidance is truthful at ${expectation.$1} live',
        (tester) async {
      final controller = summaryController(
        summarySnapshot(live: expectation.$1),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: WhatsAppCatalogStatusCard(controller: controller),
              ),
            ),
          ),
        ),
      );

      expect(find.text(expectation.$2), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shops outside rollout see the explicit neutral state',
      (tester) async {
    final controller = summaryController(
      summarySnapshot(
        live: 0,
        rollout: WhatsAppCatalogRollout.notEnabled,
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WhatsAppCatalogStatusCard(controller: controller),
        ),
      ),
    );

    expect(
      find.text('Catalogue rollout is not yet enabled for this shop.'),
      findsOneWidget,
    );
  });
}
