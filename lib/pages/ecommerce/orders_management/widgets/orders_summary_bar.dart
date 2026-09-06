import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

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
    SizeConfig().init(context);
    final countLabel = '$count ${count == 1 ? 'order' : 'orders'}';
    final countText = Text(
      countLabel,
      style: TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: SizeConfig.textMultiplier * 1.8,
      ),
    );
    final totals = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          totalText,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: SizeConfig.textMultiplier * 2,
          ),
        ),
        Text(
          rangeText,
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 1.4,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
    return Container(
      key: const ValueKey('orders-summary-bar'),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 1.2,
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 1.2,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
          if (constraints.maxWidth < 280 || largeText) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                countText,
                SizedBox(height: SizeConfig.heightMultiplier * 0.7),
                Align(alignment: Alignment.centerRight, child: totals),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: countText),
              totals,
            ],
          );
        },
      ),
    );
  }
}
