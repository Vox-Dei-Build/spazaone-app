import 'package:flutter/material.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/shared/widgets/balance_summary/balance_summary_card.dart';
import 'package:provider/provider.dart';

class LedgerStreamBuilderSection extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;

  const LedgerStreamBuilderSection({
    Key? key,
    this.startDate,
    this.endDate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final balanceSummary = Provider.of<BalanceSummaryProvider>(context);

    if (balanceSummary.isLedgerLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return BalanceSummaryCard(
      startDate: startDate,
      endDate: endDate,
    );
  }
}
