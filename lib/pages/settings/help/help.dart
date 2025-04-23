import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/pages/settings/widgets/setting_tile.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';
import 'package:pasella/utils/support_util.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static const id = '/helpPage';

  Future<void> openLink(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      throw 'Could not launch $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Help'),
      body: SafeArea(
        child: Padding(
          padding: LayoutConstants.padding10Horizontal,
          child: Column(
            children: [
              SettingTile(
                icon: Icons.help,
                title: 'How to Capture Customers?',
                onTap: () {
                  final url = TutorialConfig.getTutorialUrl(
                      TutorialConfig.TUTORIAL_CAPTURE_CUSTOMERS);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => LoomVideoPage(
                        loomUrl: url, title: 'How to Capture Customers'),
                  ));
                },
              ),
              SettingTile(
                icon: Icons.help,
                title: 'How to Capture BNPL?',
                onTap: () {
                  final url = TutorialConfig.getTutorialUrl(
                      TutorialConfig.TUTORIAL_CAPTURE_BNPL);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => LoomVideoPage(
                        loomUrl: url,
                        title: 'How to Capture Buy Now Pay Later'),
                  ));
                },
              ),
              SettingTile(
                icon: Icons.help,
                title: 'How to Capture Stock?',
                onTap: () {
                  final url = TutorialConfig.getTutorialUrl(
                      TutorialConfig.TUTORIAL_CAPTURE_STOCK);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => LoomVideoPage(
                      loomUrl: url,
                      title: 'How to add stock and link it to transactions',
                    ),
                  ));
                },
              ),
              SettingTile(
                icon: Icons.help,
                title: 'How to Capture Sales?',
                onTap: () {
                  final url = TutorialConfig.getTutorialUrl(
                      TutorialConfig.TUTORIAL_CAPTURE_SALES);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => LoomVideoPage(
                        loomUrl: url, title: 'How to Capture Sales'),
                  ));
                },
              ),
              SettingTile(
                icon: Icons.help,
                title: 'Wallet?',
                onTap: () {
                  final url = TutorialConfig.getTutorialUrl(
                      TutorialConfig.TUTORIAL_WALLET);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => LoomVideoPage(
                      loomUrl: url,
                      title: 'Everything you need to know about your wallet',
                    ),
                  ));
                },
              ),
              SettingTile(
                icon: Icons.lock,
                title: 'Privacy Policy & Security',
                onTap: () => openLink(
                    'https://docs.google.com/document/d/1ZDN6urTnKex9i01IbwO5qv3NHv1FuE54XiyKa1FRJlY/edit?usp=sharing'),
              ),
              const Spacer(),
              CustomButton(
                icon: FontAwesomeIcons.whatsapp,
                title: 'Chat with support',
                onTap: () => SupportUtil.sendWhatsAppMessage(
                    context, WhatsAppMessageType.support),
              ),
              const SizedBox(height: 15.0),
            ],
          ),
        ),
      ),
    );
  }
}
