import 'package:flutter/material.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/config/size_config.dart';

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

/// One calm stock-value summary instead of three competing cards.
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
    final colors = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(14);
    final stack = textScale >= 20;

    return Material(
      color: colors.primaryContainer.withValues(alpha: .28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.primary.withValues(alpha: .16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stock value',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            if (stack)
              Column(
                children: _metrics(context, vertical: true),
              )
            else
              Row(children: _metrics(context, vertical: false)),
          ],
        ),
      ),
    );
  }

  List<Widget> _metrics(BuildContext context, {required bool vertical}) {
    final items = <({String label, double value})>[
      (label: 'What stock cost', value: costValue),
      (label: 'Selling value', value: salesValue),
      (label: 'Possible profit', value: potentialProfit),
    ];
    return [
      for (var index = 0; index < items.length; index++) ...[
        if (index > 0)
          vertical
              ? Divider(color: Theme.of(context).colorScheme.outlineVariant)
              : SizedBox(
                  height: 48,
                  child: VerticalDivider(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
        _StockValueMetric(
          expanded: !vertical,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: vertical ? 8 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  items[index].label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  CurrencyUtil.format(items[index].value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    ];
  }
}

class _StockValueMetric extends StatelessWidget {
  const _StockValueMetric({required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return expanded ? Expanded(child: child) : child;
  }
}
