import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/startup_session_progress.dart';

void main() {
  late StartupSessionProgress progress;
  setUp(() => progress = StartupSessionProgress());
  tearDown(() => progress.dispose());

  StartupSessionToken begin(
          {String user = 'owner-a', String store = 'shop-a'}) =>
      progress.bind(userId: user, storeId: store)!;

  test('consent choice alone cannot release a still-visible privacy surface',
      () async {
    final token = begin();
    final ready = progress.waitUntilReady(token);
    var delivered = false;
    ready.then((_) => delivered = true);
    progress.complete(token, StartupOutcome.completed);
    await Future<void>.delayed(Duration.zero);
    expect(delivered, isFalse);
    expect(progress.ready, isFalse);

    progress.consentSurfaceClosed(token, consentDecided: true);
    expect(await ready, isTrue);
  });

  test('closing a surface without a saved choice cannot grant readiness', () {
    final token = begin();
    progress.consentSurfaceClosed(token, consentDecided: false);
    progress.complete(token, StartupOutcome.skipped);
    expect(progress.ready, isFalse);
  });

  test(
      'selected onboarding form keeps notification waiting until startup completes',
      () async {
    final token = begin();
    expect(progress.tryBegin(token), isTrue);
    progress.consentSurfaceClosed(token, consentDecided: true);
    final ready = progress.waitUntilReady(token);
    var delivered = false;
    ready.then((_) => delivered = true);
    await Future<void>.delayed(Duration.zero);
    expect(delivered, isFalse);
    progress.complete(token, StartupOutcome.completed);
    expect(await ready, isTrue);
  });

  test('offline, disabled or operator skip can complete only this session',
      () async {
    final token = begin(user: 'operator-a', store: 'shared-shop');
    progress.consentSurfaceClosed(token, consentDecided: true);
    progress.complete(token, StartupOutcome.skipped);
    expect(await progress.waitUntilReady(token), isTrue);
    expect(progress.outcome, StartupOutcome.skipped);

    progress.reset();
    final nextLogin = begin(user: 'operator-a', store: 'shared-shop');
    expect(identical(nextLogin, token), isFalse);
    expect(progress.outcome, isNull);
    expect(progress.ready, isFalse);
  });

  test('store switch cancels old waiters and ignores late completion',
      () async {
    final oldStore = begin();
    final oldWait = progress.waitUntilReady(oldStore);
    final newStore = begin(store: 'shop-b');
    expect(await oldWait, isFalse);
    progress.consentSurfaceClosed(oldStore, consentDecided: true);
    progress.complete(oldStore, StartupOutcome.completed);
    expect(progress.ready, isFalse);
    expect(progress.current, same(newStore));
    progress.consentSurfaceClosed(newStore, consentDecided: true);
    progress.complete(newStore, StartupOutcome.skipped);
    expect(await progress.waitUntilReady(newStore), isTrue);
  });

  test('logout and same-account login do not reuse an old generation',
      () async {
    final oldLogin = begin();
    final pending = progress.waitUntilReady(oldLogin);
    progress.reset();
    final nextLogin = begin();
    expect(await pending, isFalse);
    expect(progress.isCurrent(oldLogin), isFalse);
    expect(progress.isCurrent(nextLogin), isTrue);
    expect(progress.ready, isFalse);
  });

  test('repeated binding preserves progress and only one route owns startup',
      () {
    final token = begin();
    expect(begin(), same(token));
    expect(progress.tryBegin(token), isTrue);
    expect(progress.tryBegin(token), isFalse);
    progress.abandon(token);
    expect(progress.tryBegin(token), isTrue);
    progress.complete(token, StartupOutcome.skipped);
    expect(progress.tryBegin(token), isFalse);
  });
}
