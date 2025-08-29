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
    return Container(
      padding: EdgeInsets.fromLTRB(
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 1.2,
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 1.2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count order(s)',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: SizeConfig.textMultiplier * 1.8,
              ),
            ),
          ),
          Column(
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
          ),
        ],
      ),
    );
  }
}
