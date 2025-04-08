import 'package:pasella/providers/common/balance_summary_provider.dart';

class BalanceSummaryViewModel {
  final BalanceSummaryProvider balanceSummaryProvider;
  BalanceSummaryViewModel(this.balanceSummaryProvider);

  Future<void> fetchBalanceSummaryWithRange(
      DateTime start, DateTime end) async {
    await balanceSummaryProvider.fetchBalanceSummary(
        startDate: start, endDate: end);
  }
}
