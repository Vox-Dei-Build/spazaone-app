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

_SummaryController _summaryController(
  WhatsAppCatalogSnapshot snapshot,
) =>
    _SummaryController(snapshot);

class _SummaryController extends WhatsAppCatalogStatusController {
  _SummaryController(WhatsAppCatalogSnapshot initialSnapshot)
      : super(
          enabled: () => true,
          now: () => DateTime(2026, 9, 3, 12, 10),
          storeSession: StoreSession.testing(
            userIdProvider: () => 'owner-a',
            bootstrapLoader: () async => const <String, dynamic>{},
            storage: _MemoryStoreStorage(),
          ),
        ) {
    snapshot = initialSnapshot;
  }

  int refreshes = 0;
  WhatsAppCatalogSnapshot? refreshedSnapshot;

  @override
  Future<void> manualRefresh() async {
    refreshes++;
    snapshot = refreshedSnapshot ?? snapshot;
    notifyListeners();
  }
}

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

  for (final live in [4, 5, 10]) {
    testWidgets('drawer reports $live live without browsing promises',
        (tester) async {
      final controller = _summaryController(summarySnapshot(live: live));
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WhatsAppCatalogStatusCard(controller: controller)),
      ));
      expect(find.text('Live on WhatsApp'), findsNothing);
      await tester
          .tap(find.byKey(const ValueKey('whatsapp-catalog-status-entry')));
      await tester.pumpAndSettle();
      expect(find.text('Live on WhatsApp'), findsOneWidget);
      expect(find.text('$live'), findsOneWidget);
      expect(find.textContaining('five-product'), findsNothing);
      expect(find.textContaining('ten-product'), findsNothing);
      expect(find.textContaining('Ready for'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shops outside rollout see the explicit neutral state',
      (tester) async {
    final controller = _summaryController(
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

    expect(find.text('Listing not enabled yet'), findsOneWidget);
    expect(find.text('0 live'), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('whatsapp-catalog-status-entry')));
    await tester.pumpAndSettle();
    expect(
      find.text('Not available for this shop yet.'),
      findsOneWidget,
    );
  });

  testWidgets('catalogue entry stays compact and opens live details',
      (tester) async {
    final controller = _summaryController(summarySnapshot(live: 5));
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WhatsAppCatalogStatusCard(controller: controller),
      ),
    ));

    final entry = find.byKey(const ValueKey('whatsapp-catalog-status-entry'));
    expect(tester.getSize(entry).height, lessThanOrEqualTo(60));
    expect(find.text('Last checked: 5 live'), findsOneWidget);
    expect(find.text('Needs attention'), findsNothing);
    expect(find.byTooltip('Refresh catalogue status'), findsNothing);

    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.byTooltip('Refresh catalogue status'), findsOneWidget);

    controller.refreshedSnapshot = summarySnapshot(live: 10);
    await tester.tap(find.byTooltip('Refresh catalogue status'));
    await tester.pump();
    expect(controller.refreshes, 1);
    expect(
      find.text('10'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable status keeps error and retry inside details',
      (tester) async {
    final controller = _summaryController(summarySnapshot(live: 0))
      ..snapshot = null
      ..errorMessage = 'Could not load the latest catalogue status.';
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WhatsAppCatalogStatusCard(controller: controller),
      ),
    ));
    expect(find.text('Status unavailable'), findsOneWidget);
    expect(find.text(controller.errorMessage!), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('whatsapp-catalog-status-entry')));
    await tester.pumpAndSettle();
    expect(find.text(controller.errorMessage!), findsOneWidget);
    expect(find.byTooltip('Refresh catalogue status'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached failure keeps one concise error beside the check time',
      (tester) async {
    final controller = _summaryController(summarySnapshot(live: 4))
      ..errorMessage = "Couldn’t refresh.";
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WhatsAppCatalogStatusCard(controller: controller),
      ),
    ));

    await tester
        .tap(find.byKey(const ValueKey('whatsapp-catalog-status-entry')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn’t refresh."), findsOneWidget);
    expect(find.textContaining('Last checked catalogue'), findsNothing);
    expect(find.textContaining('3 Sep, 12:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalogue details remain readable on narrow large-text screens',
      (tester) async {
    final controller = _summaryController(summarySnapshot(live: 4));
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: WhatsAppCatalogStatusCard(controller: controller),
      ),
    ));
    expect(tester.takeException(), isNull);
    await tester
        .tap(find.byKey(const ValueKey('whatsapp-catalog-status-entry')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Refresh status'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh status').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening catalogue details dismisses a retained search focus',
      (tester) async {
    final controller = _summaryController(summarySnapshot(live: 4));
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TextField(focusNode: focus),
            WhatsAppCatalogStatusCard(controller: controller),
          ],
        ),
      ),
    ));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester
        .tap(find.byKey(const ValueKey('whatsapp-catalog-status-entry')));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(find.byTooltip('Refresh catalogue status'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
