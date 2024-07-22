import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:pasella/models/common/balance_summary_model.dart';
import 'package:pasella/models/common/period_filter_model.dart';
import 'package:pasella/shared/services/period_filter_services.dart';
import 'package:provider/provider.dart';

class BalanceSummaryProvider with ChangeNotifier {
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

  void updatePeriodFilter(BuildContext context, TimePeriod period) {
    final periodFilterService =
        Provider.of<PeriodFilterService>(context, listen: false);
    periodFilterService.updatePeriodFilter(period);
    DateTime startDate = periodFilterService.getStartDate();
    Future.delayed(Duration.zero, () {
      fetchBalanceSummary(startDate: startDate);
    });
  }

  Future<void> fetchBalanceSummary({DateTime? startDate}) async {
    if (!_isLedgerLoading) {
      isLedgerLoading = true;
    }

    final parameters =
        startDate != null ? {'startDate': startDate.toIso8601String()} : {};

    final HttpsCallable callable =
        FirebaseFunctions.instance.httpsCallable('calculateUserBalance');
    try {
      final HttpsCallableResult result = await callable.call(parameters);

      BalanceSummary newBalanceSummary = BalanceSummary(
        netBalance: (result.data['totalBalance'] as num).toDouble(),
        paymentCount: result.data['payment']['count'],
        paymentAmount: result.data['payment']['totalAmount'].toDouble(),
        creditCount: result.data['credit']['count'],
        creditAmount: result.data['credit']['totalAmount'].toDouble(),
        totalCustomers: result.data['totalCustomers'],
        owingNumberOfCustomers: result.data['outstandingCustomers'],
      );

      // Only update and notify if the balance summary actually changes
      if (!_balanceSummary.equals(newBalanceSummary)) {
        _balanceSummary = newBalanceSummary;
      }
    } catch (e) {
      print('Error fetching balance summary: $e');
    } finally {
      isLedgerLoading = false;
    }
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
    if (_isLedgerLoading != value) {
      Future.delayed(Duration.zero, () {
        _isLedgerLoading = value;
        notifyListeners();
      });
    }
  }
}
