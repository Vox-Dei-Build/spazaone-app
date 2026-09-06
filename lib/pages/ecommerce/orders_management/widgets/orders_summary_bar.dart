import 'package:flutter/material.dart';

class OrdersSummaryBar extends StatelessWidget {
  const OrdersSummaryBar(
      {super.key,
      required this.count,
      required this.totalText,
      required this.rangeText});
  final int count;
  final String totalText;
  final String rangeText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$count order(s)',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                totalText,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                rangeText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
