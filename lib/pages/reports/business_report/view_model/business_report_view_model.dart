import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:pasella/models/reports/business_report_model.dart';

class BusinessReportViewModel {
  final String currentUser;

  BusinessReportViewModel(this.currentUser);

  final HttpsCallable reportCallable = FirebaseFunctions.instance.httpsCallable(
    'generateCashflowImpactReport',
  );

  // PAS-UX-06A: a separate, never date-filtered total-customers source for
  // the Pay Later / Summary view. Mixing this with the date-filtered
  // BalanceSummaryProvider produced impossible percentages (e.g. 130%
  // who owe you) because the numerator (NPAs) is all-time and the
  // denominator (totalCustomers) was today-only.
  final HttpsCallable _allTimeBalanceCallable = FirebaseFunctions.instance
      .httpsCallable('calculateUserBalance');

  ValueNotifier<Future<Report>?> reportFutureNotifier = ValueNotifier(null);
  final ValueNotifier<int?> allTimeTotalCustomersNotifier = ValueNotifier(null);

  Future<Report>? reportFuture;
  double? totalBalance;
  int yearlyPeriod = 365;

  /// Old method but now optional args
  Future<Report> fetchReport({DateTime? startDate, DateTime? endDate}) async {
    final DateTime safeStart =
        startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final DateTime safeEnd = endDate ?? DateTime.now();

    final periodInDays = safeEnd.difference(safeStart).inDays;

    try {
      final HttpsCallableResult result = await reportCallable
          .call(<String, dynamic>{
            'currentUser': currentUser,
            'startDate': safeStart.toIso8601String(),
            'endDate': safeEnd.toIso8601String(),
            'period': periodInDays,
            'yearlyPeriod': yearlyPeriod,
          });

      Map<String, dynamic> reportData = result.data as Map<String, dynamic>;

      return Report(
        totalNumberofNPAs: reportData['totalNumberofNPAs'],
        customersWithNPAs: reportData['customersWithNPAs'],
        nplRatio: reportData['nplRatio'].toDouble(),
        cashflowImpact: reportData['cashflowImpact']?.toDouble() ?? 0,
      );
    } catch (e) {
      print('Error fetching report: $e');
      throw Exception('Failed to fetch report: $e');
    }
  }

  /// For updating the notifier directly
  Future<Report> fetchReportWithRange(DateTime start, DateTime end) async {
    final future = fetchReport(startDate: start, endDate: end);
    reportFutureNotifier.value = future;
    return future;
  }

  /// PAS-UX-06A: all-time total customer count for the Summary / Pay Later
  /// tiles. Kept separate from the date-filtered BalanceSummaryProvider so
  /// the "% Who Owe You" denominator cannot drift with the date filter on
  /// the sibling Date View tab. Failures collapse to null (rendered as "—")
  /// rather than masquerading as 0 customers.
  Future<void> fetchAllTimeTotalCustomers() async {
    try {
      final HttpsCallableResult result = await _allTimeBalanceCallable.call({
        'startDate': DateTime(2000, 1, 1).toIso8601String(),
        'endDate': DateTime.now().toIso8601String(),
      });
      final data = result.data as Map<String, dynamic>;
      final int? total = data['totalCustomers'] as int?;
      allTimeTotalCustomersNotifier.value = total;
    } catch (e) {
      print('Error fetching all-time total customers: $e');
      // Leave notifier as null so the UI renders "—" instead of "0".
    }
  }

  void dispose() {
    reportFutureNotifier.dispose();
    allTimeTotalCustomersNotifier.dispose();
  }
}
