import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/balance_summary_model.dart';
import 'package:pasella/shared/widgets/balance_summary/balance_stats.dart';
import 'package:pasella/shared/widgets/balance_summary/net_balance.dart';

class BalanceSummaryCardContent extends StatelessWidget {
  final BalanceSummary balanceSummary;

  const BalanceSummaryCardContent({Key? key, required this.balanceSummary})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    Color balanceColor =
        balanceSummary.netBalance < 0 ? Colors.red : Colors.green;
    List<Widget>? children = balanceSummary.children;

    return Card(
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
            NetBalance(
              balanceSummary: balanceSummary,
              balanceColor: balanceColor,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            BalanceStats(
              balanceSummary: balanceSummary,
              balanceColor: balanceColor,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            if (children != null) ...children,
          ],
        ),
      ),
    );
  }
}
