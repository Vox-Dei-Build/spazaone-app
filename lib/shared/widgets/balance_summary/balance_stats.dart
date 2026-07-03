import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/balance_summary_model.dart';
import 'package:pasella/utils/currency_util.dart';

class BalanceStats extends StatelessWidget {
  final BalanceSummary balanceSummary;
  final Color balanceColor;

  const BalanceStats({
    Key? key,
    required this.balanceSummary,
    required this.balanceColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    var creditCount = balanceSummary.creditCount;
    var creditAmount = balanceSummary.creditAmount;
    var paymentCount = balanceSummary.paymentCount;
    var paymentAmount = balanceSummary.paymentAmount;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildCreditsColumn(creditCount, creditAmount),
        _buildPaymentsColumn(paymentCount, paymentAmount),
      ],
    );
  }

  Column _buildCreditsColumn(int creditCount, double creditAmount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.credit_card,
              color: Colors.red,
              size: SizeConfig.imageSizeMultiplier * 4,
            ),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 1),
            Text(
              "$creditCount Transactions",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: SizeConfig.textMultiplier * 2,
              ),
            ),
          ],
        ),
        Text(
          CurrencyUtil.format(creditAmount),
          style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: SizeConfig.textMultiplier * 2,
          ),
        ),
      ],
    );
  }

  Column _buildPaymentsColumn(int paymentCount, double paymentAmount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.payments,
              color: Colors.green,
              size: SizeConfig.imageSizeMultiplier * 4,
            ),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 1),
            Text(
              "$paymentCount Payments",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: SizeConfig.textMultiplier * 2,
              ),
            ),
          ],
        ),
        Text(
          CurrencyUtil.format(paymentAmount),
          style: TextStyle(
            color: Colors.green,
            fontWeight: FontWeight.bold,
            fontSize: SizeConfig.textMultiplier * 2,
          ),
        ),
      ],
    );
  }
}
