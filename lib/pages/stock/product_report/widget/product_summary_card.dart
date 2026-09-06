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
  Widget build(BuildContext context) {
    final isLoss = potentialProfit < 0;
    return Column(
      key: const ValueKey('stock-value-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isLoss
                ? SpazaColors.error.withValues(alpha: .08)
                : SpazaColors.successSurface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Possible profit',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isLoss ? SpazaColors.error : kSecondaryAccent,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  CurrencyUtil.format(potentialProfit),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: isLoss ? SpazaColors.error : kPrimaryColor,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'If all current stock is sold',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isLoss ? SpazaColors.error : kSecondaryAccent,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 20;
            final cost = _ValueMetric(label: 'Stock cost', amount: costValue);
            final sales =
                _ValueMetric(label: 'Selling value', amount: salesValue);
            if (stack) {
              return Column(
                children: [cost, const SizedBox(height: 8), sales],
              );
            }
            return Row(
              children: [
                Expanded(child: cost),
                const SizedBox(width: 10),
                Expanded(child: sales),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ValueMetric extends StatelessWidget {
  const _ValueMetric({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                CurrencyUtil.format(amount),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: kTertiaryColor,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      );
}
