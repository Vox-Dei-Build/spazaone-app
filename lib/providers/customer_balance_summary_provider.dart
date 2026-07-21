import 'package:flutter/foundation.dart';
import 'package:pasella/models/common/balance_summary_model.dart';
import 'package:pasella/utils/transaction_util.dart';
import 'package:pasella/services/store_session.dart';

/// Holds the running balance + stats for the currently-open customer profile.
///
/// Used by:
///  - the Pay Later screen's `CustomerBalanceHero` (compact balance band)
///  - the `ProfileAppBar`'s `PaymentStatusPill`
///
/// Previously this provider also injected an `AddCreditPaymentButtons` widget
/// into a `children` slot on [BalanceSummary]; that coupled the data model to
/// UI and forced the CTA to live wherever the summary card was rendered. The
/// CTA is now rendered directly by the page (`PayLaterActionBar`) and this
/// provider deals only in numbers + identity.
class CustomerBalanceSummaryProvider with ChangeNotifier {
  CustomerBalanceSummaryProvider() {
    _activeStoreId = StoreSession.instance.storeId;
    StoreSession.instance.addListener(_onStoreChanged);
  }

  String _activeStoreId = '';
  String _customerName = '';
  String _customerId = '';
  String _mobileNumber = '';
  BalanceSummary _customerBalanceSummary = BalanceSummary(
    netBalance: 0.0,
    paymentCount: 0,
    paymentAmount: 0.0,
    creditCount: 0,
    creditAmount: 0.0,
  );

  BalanceSummary get customerBalanceSummary => _customerBalanceSummary;

  String get customerName => _customerName;
  String get customerId => _customerId;
  String get mobileNumber => _mobileNumber;

  void _onStoreChanged() {
    final storeId = StoreSession.instance.storeId;
    if (storeId == _activeStoreId) return;
    _activeStoreId = storeId;
    _customerName = '';
    _customerId = '';
    _mobileNumber = '';
    _customerBalanceSummary = BalanceSummary(
      netBalance: 0.0,
      paymentCount: 0,
      paymentAmount: 0.0,
      creditCount: 0,
      creditAmount: 0.0,
    );
    notifyListeners();
  }

  void setCustomerDetails(String name, String id, String? mobileNumber) {
    _customerName = name;
    _customerId = id;
    _mobileNumber = mobileNumber ?? '';

    // Preserve numbers across identity changes (existing behaviour); the
    // stream subscription will refresh them on the next snapshot.
    _customerBalanceSummary = BalanceSummary(
      netBalance: _customerBalanceSummary.netBalance,
      paymentCount: _customerBalanceSummary.paymentCount,
      paymentAmount: _customerBalanceSummary.paymentAmount,
      creditCount: _customerBalanceSummary.creditCount,
      creditAmount: _customerBalanceSummary.creditAmount,
      totalCustomers: _customerBalanceSummary.totalCustomers,
      owingNumberOfCustomers: _customerBalanceSummary.owingNumberOfCustomers,
    );
  }

  void updateForCustomer(List<Map<String, dynamic>> transactions) {
    double netBalance = 0.0;
    TransactionStats stats = TransactionStats(
      paymentCount: 0,
      paymentAmount: 0.0,
      creditCount: 0,
      creditAmount: 0.0,
    );

    if (transactions.isNotEmpty) {
      netBalance = TransactionService.calculateBalance(transactions);
      stats =
          TransactionService.calculateCustomerTransactionStats(transactions);
    }

    _customerBalanceSummary = BalanceSummary(
      netBalance: netBalance,
      paymentCount: stats.paymentCount,
      paymentAmount: stats.paymentAmount,
      creditCount: stats.creditCount,
      creditAmount: stats.creditAmount,
    );

    notifyListeners();
  }

  @override
  void dispose() {
    StoreSession.instance.removeListener(_onStoreChanged);
    super.dispose();
  }
}
