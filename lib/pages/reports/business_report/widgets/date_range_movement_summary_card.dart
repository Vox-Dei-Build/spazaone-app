import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

class DateRangeMovementSummaryCard extends StatelessWidget {
  const DateRangeMovementSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Consumer<BalanceSummaryProvider>(
      builder: (context, provider, child) {
        if (provider.isLedgerLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final summary = provider.balanceSummary;
        final movementColor =
            summary.netBalance < 0 ? Colors.red : Colors.green;

        return Column(
          children: [
            Card(
              elevation: 4.0,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  SizeConfig.heightMultiplier * 1,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(SizeConfig.heightMultiplier * 1.2),
                child: Column(
                  children: [
                    _MovementTotal(
                      amount: summary.netBalance,
                      amountColor: movementColor,
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 1),
                    Text(
                      'Shows payments minus credits inside the selected date range.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: SizeConfig.textMultiplier * 1.3,
                      ),
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 1),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _MovementStat(
                          icon: Icons.credit_card,
                          iconColor: Colors.red,
                          label: '${summary.creditCount} Credits',
                          amount: summary.creditAmount,
                          amountColor: Colors.red,
                        ),
                        _MovementStat(
                          icon: Icons.payments,
                          iconColor: Colors.green,
                          label: '${summary.paymentCount} Payments',
                          amount: summary.paymentAmount,
                          amountColor: Colors.green,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MovementTotal extends StatelessWidget {
  final double amount;
  final Color amountColor;

  const _MovementTotal({
    required this.amount,
    required this.amountColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                SizedBox(
                  width: SizeConfig.imageSizeMultiplier * 7,
                  child: Icon(
                    Icons.account_balance_wallet,
                    color: amountColor,
                    size: SizeConfig.imageSizeMultiplier * 6,
                  ),
                ),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 1),
                Text(
                  'Net Movement',
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
              CurrencyUtil.format(amount),
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 2,
                fontWeight: FontWeight.bold,
                color: amountColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MovementStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final double amount;
  final Color amountColor;

  const _MovementStat({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.amount,
    required this.amountColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              color: iconColor,
              size: SizeConfig.imageSizeMultiplier * 4,
            ),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 1),
            Text(
              label,
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: SizeConfig.textMultiplier * 2,
              ),
            ),
          ],
        ),
        Text(
          CurrencyUtil.format(amount),
          style: TextStyle(
            color: amountColor,
            fontWeight: FontWeight.bold,
            fontSize: SizeConfig.textMultiplier * 2,
          ),
        ),
      ],
    );
  }
}
