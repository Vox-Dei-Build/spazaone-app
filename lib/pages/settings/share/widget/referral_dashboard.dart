import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/utils/currency_util.dart';

class ReferralDashboard extends StatelessWidget {
  final int referralCount;
  final double? rewardsEarned;

  const ReferralDashboard({
    Key? key,
    required this.referralCount,
    this.rewardsEarned,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(10),
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Total Referrals: $referralCount',
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
            ),
            if (rewardsEarned != null) ...[
              SizedBox(height: SizeConfig.heightMultiplier * 2),
              Text(
                'Rewards Earned: ${CurrencyUtil.format(rewardsEarned!)}',
                style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
