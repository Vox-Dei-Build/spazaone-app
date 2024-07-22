import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/balance_summary_model.dart';
import 'package:pasella/utils/currency_util.dart';

class NetBalance extends StatelessWidget {
  final BalanceSummary balanceSummary;
  final Color balanceColor;

  const NetBalance(
      {Key? key, required this.balanceSummary, required this.balanceColor})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    var netBalance = balanceSummary.netBalance;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  width: SizeConfig.imageSizeMultiplier * 7, // Adjusted width
                  child: Icon(
                    Icons.account_balance_wallet,
                    color: balanceColor,
                    size: SizeConfig.imageSizeMultiplier * 6, // Adjusted size
                  ),
                ),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 1),
                Text(
                  "Net Balance",
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 0.5),
            Text(
              "${CurrencyUtil.format(netBalance)}",
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 2,
                fontWeight: FontWeight.bold,
                color: balanceColor,
              ),
            ),
          ],
        )
      ],
    );
  }
}
