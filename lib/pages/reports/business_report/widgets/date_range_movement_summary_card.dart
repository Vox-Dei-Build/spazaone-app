import 'package:flutter/material.dart';
import 'package:pasella/models/common/balance_summary_model.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

class DateRangeMovementSummaryCard extends StatelessWidget {
  const DateRangeMovementSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BalanceSummaryProvider>(
      builder: (context, provider, child) {
        if (provider.isLedgerLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        return DateRangeMovementSummaryContent(
            summary: provider.balanceSummary);
      },
    );
  }
}

@visibleForTesting
class DateRangeMovementSummaryContent extends StatelessWidget {
  const DateRangeMovementSummaryContent({
    super.key,
    required this.summary,
  });

  final BalanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) >= 20;
    final metrics = <Widget>[
      _MovementMetric(
        label: '${summary.creditCount} transactions',
        amount: summary.creditAmount,
      ),
      _MovementMetric(
        label: '${summary.paymentCount} payments',
        amount: summary.paymentAmount,
      ),
    ];

    return Material(
      color: colors.primaryContainer.withValues(alpha: .26),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.primary.withValues(alpha: .15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Movement in this period',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              CurrencyUtil.format(summary.netBalance),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Payments received minus purchases added.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            if (largeText)
              for (var index = 0; index < metrics.length; index++) ...[
                if (index > 0) Divider(color: colors.outlineVariant),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: metrics[index],
                ),
              ]
            else
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(child: metrics.first),
                    VerticalDivider(color: colors.outlineVariant),
                    Expanded(child: metrics.last),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MovementMetric extends StatelessWidget {
  final String label;
  final double amount;

  const _MovementMetric({
    required this.label,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          CurrencyUtil.format(amount),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
