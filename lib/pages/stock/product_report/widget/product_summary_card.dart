import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/constants/constants.dart';

class SummaryCard extends StatelessWidget {
  final String title;
  final double amount;

  const SummaryCard({Key? key, required this.title, required this.amount})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              CurrencyUtil.format(amount),
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductValueSummary extends StatelessWidget {
  const ProductValueSummary({
    super.key,
    required this.costValue,
    required this.salesValue,
    required this.potentialProfit,
  });

  final double costValue;
  final double salesValue;
  final double potentialProfit;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: SpazaColors.surface,
              border: Border.all(color: SpazaColors.border),
              borderRadius: BorderRadius.circular(SpazaRadius.surface),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Possible profit',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: kSecondaryAccent,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  CurrencyUtil.format(potentialProfit),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: kPrimaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'If all current stock is sold',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: kSecondaryAccent,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final stacked = constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) >= 20;
            final metrics = [
              _ValueMetric(label: 'Stock cost', amount: costValue),
              _ValueMetric(label: 'Selling value', amount: salesValue),
            ];
            return stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        metrics[0],
                        const SizedBox(height: 10),
                        metrics[1]
                      ])
                : Row(children: [
                    Expanded(child: metrics[0]),
                    const SizedBox(width: 10),
                    Expanded(child: metrics[1])
                  ]);
          }),
        ],
      );
}

class _ValueMetric extends StatelessWidget {
  const _ValueMetric({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: .48),
          borderRadius: BorderRadius.circular(SpazaRadius.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: kSecondaryAccent,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              CurrencyUtil.format(amount),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: kTertiaryColor,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      );
}
