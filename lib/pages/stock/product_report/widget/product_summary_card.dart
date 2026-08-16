import 'package:flutter/material.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';

class SummaryCard extends StatelessWidget {
  final String title;
  final double amount;

  const SummaryCard({Key? key, required this.title, required this.amount})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return Card(
      margin: EdgeInsets.symmetric(vertical: SizeConfig.heightMultiplier * 1),
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.heightMultiplier * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 2,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            Text(
              CurrencyUtil.format(amount),
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
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
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: kHighLightColor,
              borderRadius: BorderRadius.circular(18),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: kPrimaryColor,
                        fontWeight: FontWeight.w900,
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
          Row(
            children: [
              Expanded(
                child: _ValueMetric(
                  label: 'Stock cost',
                  amount: costValue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ValueMetric(
                  label: 'Selling value',
                  amount: salesValue,
                ),
              ),
            ],
          ),
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
          borderRadius: BorderRadius.circular(14),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: kTertiaryColor,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      );
}
