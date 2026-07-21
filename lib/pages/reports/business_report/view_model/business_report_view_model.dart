import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:pasella/models/reports/business_report_model.dart';
import 'package:pasella/services/crash_service.dart';

/// Typed failure for the Business Report fetch path so callers (FutureBuilder,
/// tests) can distinguish report fetch failures from arbitrary exceptions.
///
/// We intentionally do NOT subclass [Exception] with a generic message string
/// (as the old code did) because the FutureBuilder routes errors through
/// `FlutterError.onError`, which CrashService classifies based on the runtime
/// type. A generic `Exception('Failed to fetch report: ...')` was being
/// recorded as a fatal crash even though the underlying cause is a transient
/// Firebase Functions / network / App Check token failure.
class ReportFetchException implements Exception {
  final Object cause;
  final StackTrace? causeStack;
  ReportFetchException(this.cause, [this.causeStack]);

  @override
  String toString() => 'ReportFetchException: $cause';
}

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
  final HttpsCallable _allTimeBalanceCallable =
      FirebaseFunctions.instance.httpsCallable('calculateUserBalance');

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
    final payload = <String, dynamic>{
      'storeId': currentUser,
      'currentUser': currentUser,
      'startDate': safeStart.toIso8601String(),
      'endDate': safeEnd.toIso8601String(),
      'period': periodInDays,
      'yearlyPeriod': yearlyPeriod,
    };

    // One-shot retry for transient failures. The Android Functions plugin
    // surfaces failures from any of its underlying parallel sub-tasks
    // (auth token refresh, App Check token fetch, the HTTPS call itself)
    // as `ExecutionException: N out of M underlying tasks failed`. These are
    // almost always transient (token churn / brief network loss) and succeed
    // on a second attempt, so we retry once before failing the user-visible
    // future.
    Object? lastError;
    StackTrace? lastStack;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final HttpsCallableResult result = await reportCallable.call(payload);

        final Map<String, dynamic> reportData =
            Map<String, dynamic>.from(result.data as Map);

        return normalizeCashflowReport(reportData);
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        // Only retry transient FirebaseFunctions failures. Permission /
        // unauthenticated / invalid-argument errors won't get better on
        // retry, so fall through immediately.
        final isTransient = e is FirebaseFunctionsException &&
            (e.code == 'unknown' ||
                e.code == 'unavailable' ||
                e.code == 'deadline-exceeded' ||
                e.code == 'internal');
        if (!isTransient || attempt == 1) break;
        // Brief backoff before the second attempt.
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }

    // Record as NON-fatal: this is a recoverable backend/network failure,
    // not a crash. The UI surfaces it via FutureBuilder.snapshot.hasError.
    debugPrint('Error fetching report: $lastError');
    await CrashService.instance.recordNonFatal(
      lastError ?? 'unknown',
      lastStack,
      reason: 'BusinessReportViewModel.fetchReport',
      context: {
        'functions_code':
            lastError is FirebaseFunctionsException ? lastError.code : 'n/a',
        'period_days': periodInDays,
      },
    );
    throw ReportFetchException(lastError ?? 'unknown', lastStack);
  }

  /// Treat the stored balance as the source of truth for who owes money.
  ///
  /// Older customer documents can retain `isNPA: true` after payment, and
  /// the deployed report function historically queried that cached flag.
  /// Filtering again here keeps the merchant-facing count, total, and list
  /// correct immediately, even before the backend fix is deployed.
  @visibleForTesting
  static Report normalizeCashflowReport(Map<String, dynamic> reportData) {
    final rawCustomers = reportData['customersWithNPAs'];
    final owingCustomers = <dynamic>[];
    var outstandingBalance = 0.0;

    if (rawCustomers is List) {
      for (final rawCustomer in rawCustomers) {
        if (rawCustomer is! Map) continue;
        final customer = Map<String, dynamic>.from(rawCustomer);
        final rawBalance = customer['balance'];
        final balance = rawBalance is num
            ? rawBalance.toDouble()
            : double.tryParse(rawBalance?.toString() ?? '');
        if (balance == null || balance >= 0) continue;

        customer['balance'] = balance;
        customer['isNPA'] = true;
        owingCustomers.add(customer);
        outstandingBalance += balance;
      }
    }

    final rawRatio = reportData['nplRatio'];
    return Report(
      totalNumberofNPAs: owingCustomers.length,
      customersWithNPAs: owingCustomers,
      nplRatio: rawRatio is num ? rawRatio.toDouble() : 0,
      cashflowImpact: outstandingBalance,
    );
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
        'storeId': currentUser,
        'startDate': DateTime(2000, 1, 1).toIso8601String(),
        'endDate': DateTime.now().toIso8601String(),
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final int? total = data['totalCustomers'] as int?;
      allTimeTotalCustomersNotifier.value = total;
    } catch (e, st) {
      debugPrint('Error fetching all-time total customers: $e');
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'BusinessReportViewModel.fetchAllTimeTotalCustomers',
        context: {
          'functions_code': e is FirebaseFunctionsException ? e.code : 'n/a',
        },
      );
      // Leave notifier as null so the UI renders "—" instead of "0".
    }
  }

  void dispose() {
    reportFutureNotifier.dispose();
    allTimeTotalCustomersNotifier.dispose();
  }
}
