import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
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

        final summary = provider.balanceSummary;
        final movementColor = summary.netBalance < 0
            ? Theme.of(context).colorScheme.error
            : kPrimaryColor;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: kHighLightColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Net movement',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: kSecondaryAccent,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        CurrencyUtil.format(summary.netBalance),
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: movementColor,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -.5,
                                ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Payments received minus sales added for these dates.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: kSecondaryAccent,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(
                    child: _MovementMetric(
                      label: '${summary.creditCount} sales',
                      amount: summary.creditAmount,
                      color: kTertiaryColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MovementMetric(
                      label: '${summary.paymentCount} payments',
                      amount: summary.paymentAmount,
                      color: kPrimaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MovementMetric extends StatelessWidget {
  const _MovementMetric({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: .48),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            CurrencyUtil.format(amount),
            maxLines: 1,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: kSecondaryAccent,
                ),
          ),
        ],
      ),
    );
  }
}
