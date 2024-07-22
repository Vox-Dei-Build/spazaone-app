import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:pasella/models/reports/business_report_model.dart';
import 'package:pasella/shared/services/period_filter_services.dart';

class BusinessReportViewModel {
  final String currentUser;
  final PeriodFilterService periodFilterService;

  BusinessReportViewModel(this.currentUser, this.periodFilterService);

  final HttpsCallable reportCallable =
      FirebaseFunctions.instance.httpsCallable('generateCashflowImpactReport');

  ValueNotifier<Future<Report>?> reportFutureNotifier = ValueNotifier(null);

  Future<Report>? reportFuture;
  double? totalBalance;
  int yearly_period = 365;

  Future<Report> fetchReport() async {
    var startDate = periodFilterService.getStartDate();
    var endDate = DateTime.now();

    var periodInDays = endDate.difference(startDate).inDays;

    try {
      final HttpsCallableResult result =
          await reportCallable.call(<String, dynamic>{
        'currentUser': currentUser,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'period': periodInDays,
        'yearlyPeriod': yearly_period,
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

  void updateReport() {
    reportFutureNotifier.value = fetchReport();
  }

  void dispose() {
    reportFutureNotifier.dispose();
  }
}
