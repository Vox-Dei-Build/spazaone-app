import 'package:pasella/providers/common/balance_summary_provider.dart';

class BalanceSummaryViewModel {
  final BalanceSummaryProvider balanceSummaryProvider;
  BalanceSummaryViewModel(this.balanceSummaryProvider);

  Future<void> fetchBalanceSummary(DateTime? startDate) async {
    await balanceSummaryProvider.fetchBalanceSummary(startDate: startDate);
  }
}
