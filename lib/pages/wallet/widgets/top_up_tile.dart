import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/utils/currency_util.dart';

/// Displays money added to the merchant's SpazaOne balance.
class TopUpTile extends StatelessWidget {
  final num amount;
  final DateTime date;

  const TopUpTile({super.key, required this.amount, required this.date});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: kHighLightColor,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.south_west_rounded, color: kPrimaryColor),
      ),
      title: Text(
        'Money added',
        style: TextStyle(
          fontSize: SizeConfig.textMultiplier * 1.8,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        DateFormat.yMMMd().format(date),
        style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 1.5, color: Colors.grey),
      ),
      trailing: Text(
        "+${CurrencyUtil.format(amount.toDouble())}",
        style: TextStyle(
            color: kPrimaryColor,
            fontWeight: FontWeight.bold,
            fontSize: SizeConfig.textMultiplier * 1.5),
      ),
    );
  }
}
