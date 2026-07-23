import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/services/store_session.dart';

class TopUpTab extends StatelessWidget {
  const TopUpTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final WalletViewModel walletVM = WalletViewModel();
    final shared = StoreSession.instance.usesSharedCampaignCredits;

    // PAS-AUTH-03: bring Top Up into the same icon → headline →
    // subtitle → CTA → walkthrough family as the other surfaces *without*
    // changing the actual top-up actions. The two CustomButtons stay
    // primary because:
    //   - Paystack is the compliance-approved on-platform path and must
    //     stay gated behind FeatureFlags.enableTopUpPaystack.
    //   - WhatsApp is the fallback for users where Paystack is off
    //     and is the only route that doesn't require the in-app card
    //     form.
    // We only add a heading, a short subtitle, and an optional
    // walkthrough link — i.e. the visual chrome that makes Top Up read
    // as part of the same empty-state language, while leaving the
    // Paystack/Mavinci compliance surface untouched.
    final tutorialUrl =
        TutorialConfig.getTutorialUrl(TutorialConfig.TUTORIAL_WALLET);

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 6,
        vertical: SizeConfig.heightMultiplier * 3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: SizeConfig.imageSizeMultiplier * 18,
            color: Colors.grey.withOpacity(0.5),
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 2),
          Text(
            shared
                ? 'Top up shared campaign credits'
                : 'Top up campaign credits',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 2.2,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 1),
          Text(
            shared
                ? 'This credit is available to all linked stores for WhatsApp, '
                    'SMS and campaign sends. Sales balances stay separate.'
                : 'Campaign credit pays for WhatsApp messages, SMS reminders '
                    'and promotion sends. Choose how you want to add credit.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.6,
              color: Colors.grey[700],
              height: 1.3,
            ),
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 3),

          // 🔥 Feature-flagged Paystack button (unchanged behaviour).
          if (FeatureFlags.enableTopUpPaystack)
            CustomButton(
              title: 'Top up via Paystack',
              onTap: () => walletVM.openPaystackForm(context),
              color: Colors.green,
              fontSize: SizeConfig.textMultiplier * 2,
              width: SizeConfig.imageSizeMultiplier * 60,
            ),

          SizedBox(height: SizeConfig.heightMultiplier * 2),

          CustomButton(
            title: 'Top up via WhatsApp',
            onTap: () => walletVM.sendTopUpWhatsAppMessage(context),
            color: Colors.green,
            icon: FontAwesomeIcons.whatsapp,
            fontSize: SizeConfig.textMultiplier * 2,
            width: SizeConfig.imageSizeMultiplier * 60,
          ),

          if (tutorialUrl.isNotEmpty) ...[
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LoomVideoPage(
                      loomUrl: tutorialUrl,
                      title: 'How wallet top-ups work',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Watch a 2-min walkthrough'),
            ),
          ],
        ],
      ),
    );
  }
}
