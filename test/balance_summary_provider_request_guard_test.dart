import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';

class _TestStoreSession extends ChangeNotifier {
  _TestStoreSession(this.storeId);

  String storeId;

  void select(String value) {
    storeId = value;
    notifyListeners();
  }
}

class _PendingBalanceRequest {
  _PendingBalanceRequest(this.parameters);

  final Map<String, dynamic> parameters;
  final completer = Completer<Map<String, dynamic>>();
}

Map<String, dynamic> _balance(double amount) => {
      'totalBalance': amount,
      'payment': {'count': 2, 'totalAmount': amount + 20},
      'credit': {'count': 3, 'totalAmount': amount + 30},
      'totalCustomers': 5,
      'outstandingCustomers': 1,
    };

void main() {
  late _TestStoreSession storeSession;
  late List<_PendingBalanceRequest> requests;
  late BalanceSummaryProvider provider;

  setUp(() {
    storeSession = _TestStoreSession('store-a');
    requests = [];
    provider = BalanceSummaryProvider(
      storeSession: storeSession,
      storeIdProvider: () => storeSession.storeId,
      loader: (parameters) {
        final request = _PendingBalanceRequest(parameters);
        requests.add(request);
        return request.completer.future;
      },
    );
  });

  tearDown(() {
    provider.dispose();
    storeSession.dispose();
  });

  test('an older range cannot overwrite a newer completed range', () async {
    final firstStart = DateTime(2026, 9, 1);
    final firstEnd = DateTime(2026, 9, 1, 23, 59);
    final latestStart = DateTime(2026, 9, 5);
    final latestEnd = DateTime(2026, 9, 5, 23, 59);

    final first = provider.fetchBalanceSummary(
      startDate: firstStart,
      endDate: firstEnd,
    );
    final latest = provider.fetchBalanceSummary(
      startDate: latestStart,
      endDate: latestEnd,
    );

    expect(requests[1].parameters, {
      'storeId': 'store-a',
      'startDate': latestStart.toIso8601String(),
      'endDate': latestEnd.toIso8601String(),
    });

    requests[1].completer.complete(_balance(500));
    await latest;
    expect(provider.balanceSummary.netBalance, 500);
    expect(provider.isLedgerLoading, isFalse);

    requests[0].completer.complete(_balance(100));
    await first;
    expect(provider.balanceSummary.netBalance, 500);
    expect(provider.isLedgerLoading, isFalse);
  });

  test('loading notifications remain safe for initState callers', () async {
    var notifications = 0;
    provider.addListener(() => notifications++);

    final fetch = provider.fetchBalanceSummary(
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 1, 23, 59),
    );

    expect(provider.isLedgerLoading, isTrue);
    expect(notifications, 0);
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);

    requests.single.completer.complete(_balance(100));
    await fetch;
    expect(provider.isLedgerLoading, isFalse);
    expect(notifications, 1);
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 2);
  });

  test('an older completion cannot clear the latest request loading state',
      () async {
    final first = provider.fetchBalanceSummary(
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 1, 23, 59),
    );
    final latest = provider.fetchBalanceSummary(
      startDate: DateTime(2026, 9, 2),
      endDate: DateTime(2026, 9, 2, 23, 59),
    );

    requests[0].completer.complete(_balance(100));
    await first;
    expect(provider.balanceSummary.netBalance, 0);
    expect(provider.isLedgerLoading, isTrue);

    requests[1].completer.complete(_balance(200));
    await latest;
    expect(provider.balanceSummary.netBalance, 200);
    expect(provider.isLedgerLoading, isFalse);
  });

  test('a response for a previously selected store is discarded', () async {
    final oldStoreRequest = provider.fetchBalanceSummary(
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 2),
    );
    expect(provider.isLedgerLoading, isTrue);

    storeSession.select('store-b');
    expect(provider.balanceSummary.netBalance, 0);
    expect(provider.isLedgerLoading, isFalse);

    requests[0].completer.complete(_balance(900));
    await oldStoreRequest;
    expect(provider.balanceSummary.netBalance, 0);
    expect(provider.isLedgerLoading, isFalse);

    final currentStoreRequest = provider.fetchBalanceSummary(
      startDate: DateTime(2026, 9, 3),
      endDate: DateTime(2026, 9, 4),
    );
    expect(requests[1].parameters['storeId'], 'store-b');
    requests[1].completer.complete(_balance(300));
    await currentStoreRequest;
    expect(provider.balanceSummary.netBalance, 300);
  });
}
