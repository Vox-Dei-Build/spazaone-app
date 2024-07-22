import 'package:flutter/material.dart';
import 'package:pasella/utils/currency_util.dart';

class ReferralDashboard extends StatelessWidget {
  final int referralCount;
  final double rewardsEarned;

  const ReferralDashboard({
    Key? key,
    required this.referralCount,
    required this.rewardsEarned,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(10),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 8),
            Text(
              'Total Referrals: $referralCount',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Rewards Earned: ${CurrencyUtil.format(rewardsEarned)}',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
