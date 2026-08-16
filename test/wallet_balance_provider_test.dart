import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/shared/billing/wallet_balance_provider.dart';

class _MemoryStorage implements StoreSessionStorage {
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

void main() {
  late String? sessionUserId;
  late StreamController<String?> auth;
  late Map<String, StreamController<Map<String, dynamic>?>> storeStreams;
  late Map<String, StreamController<Map<String, dynamic>?>> campaignStreams;
  late StoreSession session;
  late WalletBalanceProvider provider;

  StreamController<Map<String, dynamic>?> streamFor(
    Map<String, StreamController<Map<String, dynamic>?>> streams,
    String id,
  ) {
    return streams.putIfAbsent(
      id,
      () => StreamController<Map<String, dynamic>?>.broadcast(sync: true),
    );
  }

  Future<void> selectStores(List<Map<String, Object?>> stores) async {
    session = StoreSession.testing(
      userIdProvider: () => sessionUserId,
      bootstrapLoader: () async => {'stores': stores},
      storage: _MemoryStorage(),
    );
    await session.bootstrap();
  }

  setUp(() {
    sessionUserId = null;
    auth = StreamController<String?>.broadcast(sync: true);
    storeStreams = {};
    campaignStreams = {};
  });

  tearDown(() async {
    provider.dispose();
    await auth.close();
    for (final stream in [...storeStreams.values, ...campaignStreams.values]) {
      await stream.close();
    }
  });

  WalletBalanceProvider createProvider({String? initialUserId}) {
    return WalletBalanceProvider(
      storeSession: session,
      authUserIds: auth.stream,
      initialAuthUserId: initialUserId,
      storeWalletStream: (id) => streamFor(storeStreams, id).stream,
      campaignWalletStream: (id) => streamFor(campaignStreams, id).stream,
    );
  }

  test('initial empty auth state never constructs a wallet path', () async {
    await selectStores(const []);
    provider = createProvider();

    expect(storeStreams, isEmpty);
    expect(campaignStreams, isEmpty);
    expect(provider.virtualBalance, 0);
    expect(provider.salesVirtualBalance, 0);
    expect(provider.isLoading, isFalse);
  });

  test('StoreSession.clear while signed out resets subscribed balances',
      () async {
    sessionUserId = 'user-a';
    await selectStores(const [
      {'storeId': 'store-a', 'storeName': 'Store A', 'role': 'owner'},
    ]);
    provider = createProvider(initialUserId: 'user-a');
    streamFor(storeStreams, 'store-a').add({
      'virtualBalance': 120,
      'salesVirtualBalance': 40,
    });
    expect(provider.virtualBalance, 120);

    sessionUserId = null;
    auth.add(null);
    session.clear();

    expect(provider.virtualBalance, 0);
    expect(provider.salesVirtualBalance, 0);
    expect(provider.isLoading, isFalse);
  });

  test('rapid sign-out and sign-in ignores the cancelled store snapshot',
      () async {
    sessionUserId = 'user-a';
    await selectStores(const [
      {'storeId': 'store-a', 'storeName': 'Store A', 'role': 'owner'},
    ]);
    provider = createProvider(initialUserId: 'user-a');
    final oldStream = streamFor(storeStreams, 'store-a');

    auth.add(null);
    oldStream.add({'virtualBalance': 999, 'salesVirtualBalance': 999});
    expect(provider.virtualBalance, 0);

    auth.add('user-a');
    oldStream.add({'virtualBalance': 50, 'salesVirtualBalance': 10});

    expect(provider.virtualBalance, 50);
    expect(provider.salesVirtualBalance, 10);
  });

  test('store switching rejects stale snapshots from the old store', () async {
    sessionUserId = 'user-a';
    await selectStores(const [
      {'storeId': 'store-a', 'storeName': 'Store A', 'role': 'owner'},
      {'storeId': 'store-b', 'storeName': 'Store B', 'role': 'admin'},
    ]);
    provider = createProvider(initialUserId: 'user-a');
    final oldStream = streamFor(storeStreams, 'store-a');

    await session.selectStore('store-b');
    final newStream = streamFor(storeStreams, 'store-b');
    oldStream.add({'virtualBalance': 900, 'salesVirtualBalance': 900});
    newStream.add({'virtualBalance': 75, 'salesVirtualBalance': 15});

    expect(provider.virtualBalance, 75);
    expect(provider.salesVirtualBalance, 15);
  });

  test('empty shared-wallet pointer does not construct a Firestore path',
      () async {
    sessionUserId = 'user-a';
    await selectStores(const [
      {
        'storeId': 'store-a',
        'storeName': 'Store A',
        'role': 'owner',
        'sharedCampaignCredits': true,
        'campaignWalletStoreId': ' ',
      },
    ]);
    provider = createProvider(initialUserId: 'user-a');

    expect(storeStreams, isEmpty);
    expect(campaignStreams, isEmpty);
    expect(provider.isLoading, isFalse);
  });

  test('disposed provider rejects later snapshots and auth events', () async {
    sessionUserId = 'user-a';
    await selectStores(const [
      {'storeId': 'store-a', 'storeName': 'Store A', 'role': 'owner'},
    ]);
    provider = createProvider(initialUserId: 'user-a');
    final changesBeforeDispose = <String>[];
    provider.addListener(() => changesBeforeDispose.add('changed'));
    final stream = streamFor(storeStreams, 'store-a');

    provider.dispose();
    stream.add({'virtualBalance': 100});
    auth.add(null);

    expect(changesBeforeDispose, isEmpty);
    provider = createProvider();
  });
}
