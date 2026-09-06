import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/dashboard/dashboard.dart';
import 'package:pasella/services/startup_session_progress.dart';

void main() {
  testWidgets(
      'notification readiness waits for the selected form and its closing transition',
      (tester) async {
    final progress = StartupSessionProgress();
    addTearDown(progress.dispose);
    final token = progress.bind(userId: 'owner-a', storeId: 'shop-a')!;
    progress.consentSurfaceClosed(token, consentDecided: true);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('Workspace', key: ValueKey('workspace'))),
    ));
    final context = tester.element(find.byKey(const ValueKey('workspace')));
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) =>
          Scaffold(appBar: AppBar(title: const Text('Add product'))),
    ));
    await tester.pumpAndSettle();
    final pending = waitUntilStartupRouteReady(context,
        isCurrent: () => progress.isCurrent(token)).then((current) {
      if (current) progress.complete(token, StartupOutcome.completed);
      return current;
    });
    await tester.pump(const Duration(milliseconds: 200));
    expect(progress.ready, isFalse);

    navigator.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 20));
    expect(progress.ready, isFalse);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    expect(await pending, isTrue);
    expect(progress.ready, isTrue);
  });

  testWidgets('store switch cancels a pending route hand-off before navigation',
      (tester) async {
    final progress = StartupSessionProgress();
    addTearDown(progress.dispose);
    final token = progress.bind(userId: 'owner-a', storeId: 'shop-a')!;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('Workspace', key: ValueKey('workspace'))),
    ));
    final context = tester.element(find.byKey(const ValueKey('workspace')));
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('First-use surface')),
    ));
    await tester.pumpAndSettle();
    var dispatched = false;
    final pending = waitUntilStartupRouteReady(context,
        isCurrent: () => progress.isCurrent(token)).then((current) {
      if (current) dispatched = true;
      return current;
    });
    progress.bind(userId: 'owner-a', storeId: 'shop-b');
    await tester.pump(const Duration(milliseconds: 100));
    expect(await pending, isFalse);
    expect(dispatched, isFalse);
  });
}
