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
      // PAS-UX-10: AppBar said "Profile" — left over from a copy of
      // the Profile page. Now matches the page purpose and the
      // Settings tile that opens it.
      appBar: const CustomAppBar(title: 'Subscription'),
      body: SafeArea(
        child: Padding(
          padding: LayoutConstants.padding10Horizontal,
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
                      // PAS-UX-10: 'Send SMS from your phone (SIM)'
                      // claimed a feature the app does not actually
                      // provide on the Free tier — there is no
                      // SIM-send code path anywhere in the app. The
                      // line was a marketing aspiration that read,
                      // to a real merchant, as a working feature
                      // they should be able to find. Removed until
                      // the feature ships.
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
