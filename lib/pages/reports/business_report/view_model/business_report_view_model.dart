import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:pasella/models/reports/business_report_model.dart';

class BusinessReportViewModel {
  final String currentUser;

  BusinessReportViewModel(this.currentUser);

  final HttpsCallable reportCallable =
      FirebaseFunctions.instance.httpsCallable('generateCashflowImpactReport');

  ValueNotifier<Future<Report>?> reportFutureNotifier = ValueNotifier(null);

  Future<Report>? reportFuture;
  double? totalBalance;
  int yearlyPeriod = 365;

  /// Old method but now optional args
  Future<Report> fetchReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final DateTime safeStart =
        startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final DateTime safeEnd = endDate ?? DateTime.now();

    final periodInDays = safeEnd.difference(safeStart).inDays;

    try {
      final HttpsCallableResult result =
          await reportCallable.call(<String, dynamic>{
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

  void dispose() {
    reportFutureNotifier.dispose();
  }
}
