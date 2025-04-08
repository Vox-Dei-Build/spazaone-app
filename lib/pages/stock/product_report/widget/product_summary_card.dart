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
