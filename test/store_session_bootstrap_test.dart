import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/store_session.dart';

class _MemoryStoreSessionStorage implements StoreSessionStorage {
  final Map<String, List<StoreMembership>> storesByUser = {};
  final Map<String, String> activeByUser = {};

  @override
  List<StoreMembership> readStores(String uid) =>
      List<StoreMembership>.of(storesByUser[uid] ?? const []);

  @override
  Future<void> writeStores(
    String uid,
    List<StoreMembership> stores,
  ) async {
    storesByUser[uid] = List<StoreMembership>.of(stores);
  }

  @override
  Future<void> clearStores(String uid) async {
    storesByUser.remove(uid);
  }

  @override
  String? readActiveStore(String uid) => activeByUser[uid];

  @override
  Future<void> writeActiveStore(String uid, String storeId) async {
    activeByUser[uid] = storeId;
  }
}

class _CorruptStoreSessionStorage extends _MemoryStoreSessionStorage {
  @override
  List<StoreMembership> readStores(String uid) {
    throw StateError('corrupt cache');
  }
}

class _DelayedStoreWriteStorage extends _MemoryStoreSessionStorage {
  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();

  @override
  Future<void> writeStores(
    String uid,
    List<StoreMembership> stores,
  ) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await releaseWrite.future;
    await super.writeStores(uid, stores);
  }
}

const _primary = StoreMembership(
  storeId: 'primary',
  storeName: 'Koekie Food Security',
  role: StoreRole.owner,
  campaignWalletStoreId: 'primary',
  sharedCampaignCredits: true,
);

const _secondary = StoreMembership(
  storeId: 'secondary',
  storeName: 'Kweneng Store',
  role: StoreRole.owner,
  campaignWalletStoreId: 'primary',
  sharedCampaignCredits: true,
);

Map<Object?, Object?> _payload(Iterable<StoreMembership> stores) => {
      'stores': stores.map((store) => store.toMap()).toList(),
      'sharedCampaignCreditsEnrollmentAllowed': true,
    };

void main() {
  test('restores verified store names before the network response arrives',
      () async {
    final storage = _MemoryStoreSessionStorage()
      ..storesByUser['owner'] = [_primary, _secondary]
      ..activeByUser['owner'] = 'secondary';
    final remote = Completer<Map<Object?, Object?>>();
    final session = StoreSession.testing(
      userIdProvider: () => 'owner',
      bootstrapLoader: () => remote.future,
      storage: storage,
    );

    final bootstrap = session.bootstrap();

    expect(session.loading, isTrue);
    expect(session.stores.map((store) => store.storeName), [
      'Koekie Food Security',
      'Kweneng Store',
    ]);
    expect(session.activeStoreName, 'Kweneng Store');

    remote.complete(_payload([_primary, _secondary]));
    await bootstrap;
    expect(session.loading, isFalse);
  });

  test('a bootstrap failure keeps cached names and selection', () async {
    final storage = _MemoryStoreSessionStorage()
      ..storesByUser['owner'] = [_primary, _secondary]
      ..activeByUser['owner'] = 'secondary';
    final session = StoreSession.testing(
      userIdProvider: () => 'owner',
      bootstrapLoader: () => Future.error(StateError('offline')),
      storage: storage,
    );

    await session.bootstrap();

    expect(session.activeStoreName, 'Kweneng Store');
    expect(session.stores, hasLength(2));
    expect(session.lastError, isA<StateError>());
  });

  test('a malformed response cannot erase a verified local snapshot', () async {
    final storage = _MemoryStoreSessionStorage()
      ..storesByUser['owner'] = [_primary, _secondary]
      ..activeByUser['owner'] = 'primary';
    final session = StoreSession.testing(
      userIdProvider: () => 'owner',
      bootstrapLoader: () async => {
        'sharedCampaignCreditsEnrollmentAllowed': true,
      },
      storage: storage,
    );

    await session.bootstrap();

    expect(session.activeStoreName, 'Koekie Food Security');
    expect(session.stores, hasLength(2));
    expect(storage.storesByUser['owner'], hasLength(2));
    expect(session.lastError, isA<StateError>());
  });

  test('an explicit empty response clears revoked cached access', () async {
    final storage = _MemoryStoreSessionStorage()
      ..storesByUser['owner'] = [_primary, _secondary]
      ..activeByUser['owner'] = 'secondary';
    final session = StoreSession.testing(
      userIdProvider: () => 'owner',
      bootstrapLoader: () async => _payload(const []),
      storage: storage,
    );

    await session.bootstrap();

    expect(session.stores, isEmpty);
    expect(storage.storesByUser['owner'], isNull);
    expect(storage.activeByUser['owner'], 'owner');
    expect(session.storeAccessResolved, isTrue);
    expect(session.activeStoreName, 'No stores available');
    expect(session.lastError, isNull);
  });

  test('a successful response refreshes the verified local snapshot', () async {
    final storage = _MemoryStoreSessionStorage()
      ..storesByUser['owner'] = [_primary]
      ..activeByUser['owner'] = 'primary';
    final session = StoreSession.testing(
      userIdProvider: () => 'owner',
      bootstrapLoader: () async => _payload([_primary, _secondary]),
      storage: storage,
    );

    await session.bootstrap();

    expect(session.stores, hasLength(2));
    expect(storage.storesByUser['owner'], hasLength(2));
    expect(session.activeStoreName, 'Koekie Food Security');
    expect(session.lastError, isNull);
  });

  test('first cached launch preserves a saved secondary-store selection',
      () async {
    final storage = _MemoryStoreSessionStorage()
      ..activeByUser['primary'] = 'secondary';
    final session = StoreSession.testing(
      userIdProvider: () => 'primary',
      bootstrapLoader: () async => _payload([_primary, _secondary]),
      storage: storage,
    );

    await session.bootstrap();

    expect(session.storeId, 'secondary');
    expect(session.activeStoreName, 'Kweneng Store');
    expect(storage.activeByUser['primary'], 'secondary');
  });

  test('a removed saved store falls back to a verified available store',
      () async {
    const replacement = StoreMembership(
      storeId: 'replacement',
      storeName: 'New Store',
      role: StoreRole.admin,
    );
    final storage = _MemoryStoreSessionStorage()
      ..storesByUser['owner'] = [_primary, _secondary]
      ..activeByUser['owner'] = 'secondary';
    final session = StoreSession.testing(
      userIdProvider: () => 'owner',
      bootstrapLoader: () async => _payload([replacement]),
      storage: storage,
    );

    await session.bootstrap();

    expect(session.storeId, 'replacement');
    expect(session.activeStoreName, 'New Store');
    expect(storage.activeByUser['owner'], 'replacement');
  });

  test('first-run failure shows an honest unavailable state', () async {
    final storage = _MemoryStoreSessionStorage();
    final session = StoreSession.testing(
      userIdProvider: () => 'owner',
      bootstrapLoader: () => Future.error(StateError('attestation failed')),
      storage: storage,
    );

    await session.bootstrap();

    expect(session.storeId, 'owner');
    expect(session.stores, isEmpty);
    expect(session.activeStoreName, 'Stores unavailable');
    expect(session.activeStoreName, isNot('My Store'));
  });

  test('a corrupt cache cannot prevent a verified network refresh', () async {
    final storage = _CorruptStoreSessionStorage();
    final session = StoreSession.testing(
      userIdProvider: () => 'owner',
      bootstrapLoader: () async => _payload([_primary, _secondary]),
      storage: storage,
    );

    await session.bootstrap();

    expect(session.stores, hasLength(2));
    expect(session.activeStoreName, 'Koekie Food Security');
    expect(session.lastError, isNull);
  });

  test('an old user bootstrap cannot overwrite a new signed-in user', () async {
    String? currentUser = 'user-a';
    final userAResponse = Completer<Map<Object?, Object?>>();
    final userBResponse = Completer<Map<Object?, Object?>>();
    var calls = 0;
    final storage = _MemoryStoreSessionStorage();
    const userAStore = StoreMembership(
      storeId: 'store-a',
      storeName: 'User A Store',
      role: StoreRole.owner,
    );
    const userBStore = StoreMembership(
      storeId: 'store-b',
      storeName: 'User B Store',
      role: StoreRole.owner,
    );
    final session = StoreSession.testing(
      userIdProvider: () => currentUser,
      bootstrapLoader: () {
        calls++;
        return calls == 1 ? userAResponse.future : userBResponse.future;
      },
      storage: storage,
    );

    final firstBootstrap = session.bootstrap();
    session.clear();
    currentUser = 'user-b';
    final secondBootstrap = session.bootstrap();

    userBResponse.complete(_payload([userBStore]));
    await secondBootstrap;
    userAResponse.complete(_payload([userAStore]));
    await firstBootstrap;

    expect(session.stores.single.storeName, 'User B Store');
    expect(session.storeId, 'store-b');
    expect(storage.storesByUser['user-a'], isNull);
    expect(storage.storesByUser['user-b']?.single.storeName, 'User B Store');
  });

  test('a selection made during refresh wins over an older cache write',
      () async {
    final storage = _DelayedStoreWriteStorage()
      ..storesByUser['owner'] = [_primary, _secondary]
      ..activeByUser['owner'] = 'primary';
    final session = StoreSession.testing(
      userIdProvider: () => 'owner',
      bootstrapLoader: () async => _payload([_primary, _secondary]),
      storage: storage,
    );

    final bootstrap = session.bootstrap();
    await storage.writeStarted.future;
    await session.selectStore('secondary');
    storage.releaseWrite.complete();
    await bootstrap;

    expect(session.activeStoreName, 'Kweneng Store');
    expect(storage.activeByUser['owner'], 'secondary');
  });
}
