import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/utils/currency_util.dart';

class TransactionCard extends StatelessWidget {
  final Map<String, dynamic> transaction;

  TransactionCard(this.transaction);

  @override
  Widget build(BuildContext context) {
    bool isCredit = transaction['type'] == 'Credit';
    return Align(
      alignment: isCredit ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        width:
            SizeConfig.screenWidth * (SizeConfig.screenWidth > 360 ? 0.7 : 0.9),
        child: Card(
          margin: EdgeInsets.symmetric(
            vertical: SizeConfig.heightMultiplier * 1,
            horizontal: SizeConfig.imageSizeMultiplier * 1,
          ),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
          ),
          child: ListTile(
            leading: isCredit
                ? Icon(Icons.arrow_downward,
                    color: Colors.red, size: SizeConfig.textMultiplier * 1.8)
                : Icon(Icons.arrow_upward,
                    color: Colors.green, size: SizeConfig.textMultiplier * 1.8),
            title: Text(
              CurrencyUtil.format(transaction['amount']),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isCredit ? Colors.red : Colors.green,
                fontSize: SizeConfig.textMultiplier * 2, // Responsive font size
              ),
            ),
            trailing: Text(
              transaction['type'],
              style: TextStyle(
                color: Color(0xff9a9a9a),
                fontSize:
                    SizeConfig.textMultiplier * 1.3, // Responsive font size
              ),
            ),
          ),
        ),
      ),
    );
  }
}
