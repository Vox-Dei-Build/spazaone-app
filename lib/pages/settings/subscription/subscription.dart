import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/settings/subscription/widgets/subscription_card.dart';

class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  static const id = '/subscriptionPage';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: 'Profile'),
      body: SafeArea(
        child: Padding(
          padding: LayoutConstants.padding20Horizontal,
          child: Consumer<AppModel>(
            builder: (context, value, child) {
              return Column(
                children: [
                  SubscriptionCard(
                    color: Colors.orange,
                    headerIcon: Icons.stars,
                    title: 'Premium',
                    price: 'R75/MO',
                    bulletIcon: const Icon(
                      Icons.star,
                      color: Colors.orange,
                      size: 20.0,
                    ),
                    bulletPoints: const [
                      'Ad Free',
                      'Unlimited SMS from Pasella',
                      'Unlimited Business Accounts',
                      'Priority Customer Support',
                    ],
                    isActive: value.activePlan == 'Premium',
                  ),
                  SubscriptionCard(
                    color: const Color(0xff4d4d4d),
                    title: 'Basic',
                    price: 'FREE',
                    bulletIcon: Container(
                      height: 8.0,
                      width: 8.0,
                      margin: const EdgeInsets.only(left: 5.0),
                      decoration: const BoxDecoration(
                        color: Color(0xff4d4d4d),
                        shape: BoxShape.circle,
                      ),
                    ),
                    bulletPoints: const [
                      'Contains Ads',
                      'Send SMS from your phone (SIM)',
                      'Maximum 1 Business Account',
                    ],
                    isActive: value.activePlan == 'FREE',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
