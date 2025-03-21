import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/utils/currency_util.dart';

/// 🟢 Displays a Top-Up Transaction
class TopUpTile extends StatelessWidget {
  final num amount;
  final DateTime date;

  const TopUpTile({super.key, required this.amount, required this.date});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.wallet,
          color: Colors.green, size: SizeConfig.textMultiplier * 2),
      title: Text(
        "Top-Up",
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
            color: Colors.green,
            fontWeight: FontWeight.bold,
            fontSize: SizeConfig.textMultiplier * 1.5),
      ),
    );
  }
}
