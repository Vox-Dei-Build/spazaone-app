import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:pasella/models/common/balance_summary_model.dart';
import 'package:pasella/services/store_session.dart';

typedef BalanceSummaryLoader = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> parameters,
);

class BalanceSummaryProvider with ChangeNotifier {
  BalanceSummaryProvider({
    @visibleForTesting BalanceSummaryLoader? loader,
    @visibleForTesting ValueGetter<String>? storeIdProvider,
    @visibleForTesting Listenable? storeSession,
  })  : _loader = loader ?? _loadBalanceSummary,
        _storeIdProvider =
            storeIdProvider ?? (() => StoreSession.instance.storeId),
        _storeSession = storeSession ?? StoreSession.instance {
    _activeStoreId = _storeIdProvider();
    _storeSession.addListener(_onStoreChanged);
  }

  final BalanceSummaryLoader _loader;
  final ValueGetter<String> _storeIdProvider;
  final Listenable _storeSession;

  late String _activeStoreId;
  int _requestEpoch = 0;
  int _loadingNotificationEpoch = 0;
  bool _disposed = false;
  String? _requestedStoreId;
  DateTime? _requestedStartDate;
  DateTime? _requestedEndDate;
  BalanceSummary _balanceSummary = BalanceSummary(
    netBalance: 0.0,
    paymentCount: 0,
    paymentAmount: 0.0,
    creditCount: 0,
    creditAmount: 0.0,
    totalCustomers: 0,
    owingNumberOfCustomers: 0,
  );

  BalanceSummary get balanceSummary => _balanceSummary;

  static Future<Map<String, dynamic>> _loadBalanceSummary(
    Map<String, dynamic> parameters,
  ) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('calculateUserBalance');
    final result = await callable.call(parameters);
    return Map<String, dynamic>.from(result.data as Map);
  }

  void _onStoreChanged() {
    final storeId = _storeIdProvider();
    if (storeId == _activeStoreId) return;

    // Any response issued for the previous store is now stale, even if no
    // newer request has started yet.
    _requestEpoch++;
    _requestedStoreId = null;
    _requestedStartDate = null;
    _requestedEndDate = null;
    _activeStoreId = storeId;
    _balanceSummary = BalanceSummary(
      netBalance: 0.0,
      paymentCount: 0,
      paymentAmount: 0.0,
      creditCount: 0,
      creditAmount: 0.0,
      totalCustomers: 0,
      owingNumberOfCustomers: 0,
    );
    _isLedgerLoading = false;
    _loadingNotificationEpoch++;
    notifyListeners();
  }

  void updateCustomDateRange(
      BuildContext context, DateTime start, DateTime end) {
    Future.delayed(Duration.zero, () {
      fetchBalanceSummary(startDate: start, endDate: end);
    });
  }

  Future<void> fetchBalanceSummary(
      {DateTime? startDate, DateTime? endDate}) async {
    final requestEpoch = ++_requestEpoch;
    final requestStoreId = _storeIdProvider();
    final requestStartDate = startDate;
    final requestEndDate = endDate;

    _requestedStoreId = requestStoreId;
    _requestedStartDate = requestStartDate;
    _requestedEndDate = requestEndDate;
    _setLedgerLoading(true);

    final parameters = {
      'storeId': requestStoreId,
      if (requestStartDate != null)
        'startDate': requestStartDate.toIso8601String(),
      if (requestEndDate != null) 'endDate': requestEndDate.toIso8601String(),
    };

    try {
      final data = await _loader(parameters);

      if (!_isLatestRequest(
        epoch: requestEpoch,
        storeId: requestStoreId,
        startDate: requestStartDate,
        endDate: requestEndDate,
      )) {
        return;
      }

      BalanceSummary newBalanceSummary = BalanceSummary(
        netBalance: (data['totalBalance'] as num).toDouble(),
        paymentCount: data['payment']['count'],
        paymentAmount: data['payment']['totalAmount'].toDouble(),
        creditCount: data['credit']['count'],
        creditAmount: data['credit']['totalAmount'].toDouble(),
        totalCustomers: data['totalCustomers'],
        owingNumberOfCustomers: data['outstandingCustomers'],
      );

      if (!_balanceSummary.equals(newBalanceSummary)) {
        _balanceSummary = newBalanceSummary;
      }
    } catch (e) {
      debugPrint('Error fetching balance summary: $e');
    } finally {
      if (_isLatestRequest(
        epoch: requestEpoch,
        storeId: requestStoreId,
        startDate: requestStartDate,
        endDate: requestEndDate,
      )) {
        _setLedgerLoading(false);
      }
    }
  }

  bool _isLatestRequest({
    required int epoch,
    required String storeId,
    required DateTime? startDate,
    required DateTime? endDate,
  }) {
    return epoch == _requestEpoch &&
        storeId == _requestedStoreId &&
        startDate == _requestedStartDate &&
        endDate == _requestedEndDate &&
        storeId == _activeStoreId &&
        storeId == _storeIdProvider();
  }

  void updateBalanceSummaryFromMap(Map<String, dynamic> data) {
    BalanceSummary newBalanceSummary = BalanceSummary(
      netBalance: data['totalBalance'].toDouble(),
      paymentCount: data['payment']['count'],
      paymentAmount: data['payment']['totalAmount'].toDouble(),
      creditCount: data['credit']['count'],
      creditAmount: data['credit']['totalAmount'].toDouble(),
      totalCustomers: data['totalCustomers'],
      owingNumberOfCustomers: data['outstandingCustomers'],
    );

    if (!_balanceSummary.equals(newBalanceSummary)) {
      _balanceSummary = newBalanceSummary;
      notifyListeners(); // This is crucial to notify listeners about the update
    }
  }

  bool _isLedgerLoading = false;
  bool get isLedgerLoading => _isLedgerLoading;
  set isLedgerLoading(bool value) {
    _setLedgerLoading(value);
  }

  void _setLedgerLoading(bool value) {
    if (_isLedgerLoading == value) return;
    _isLedgerLoading = value;
    final notificationEpoch = ++_loadingNotificationEpoch;
    // A fetch can start from a descendant's initState. Defer the notification
    // until the current build has finished, while updating the value now so a
    // Consumer built later in this frame still sees the correct state.
    Future<void>.delayed(Duration.zero, () {
      if (_disposed || notificationEpoch != _loadingNotificationEpoch) return;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _requestEpoch++;
    _loadingNotificationEpoch++;
    _requestedStoreId = null;
    _requestedStartDate = null;
    _requestedEndDate = null;
    _storeSession.removeListener(_onStoreChanged);
    super.dispose();
  }
}
