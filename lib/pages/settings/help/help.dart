import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/constants/app_urls.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/pages/settings/widgets/setting_tile.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';
import 'package:pasella/utils/support_util.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static const id = '/helpPage';

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(AppUrls.privacyPolicy),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Keep link failures in this screen instead of throwing out of the tap.
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not open privacy policy. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const CustomAppBar(title: 'Help'),
        body: SafeArea(
          child: HelpMenu(
            onTutorial: (label, tutorial) => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LoomVideoPage(
                  loomUrl: TutorialConfig.getTutorialUrl(tutorial),
                  title: label,
                ),
              ),
            ),
            onPrivacy: () => _openPrivacyPolicy(context),
            onSupport: () => SupportUtil.sendWhatsAppMessage(
              context,
              WhatsAppMessageType.support,
            ),
          ),
        ),
      );
}

class HelpMenu extends StatelessWidget {
  const HelpMenu({
    super.key,
    required this.onTutorial,
    required this.onPrivacy,
    required this.onSupport,
  });
  final void Function(String label, String tutorial) onTutorial;
  final VoidCallback onPrivacy;
  final VoidCallback onSupport;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text('Tutorials', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              for (final tutorial in const [
                ('Add customers', TutorialConfig.TUTORIAL_CAPTURE_CUSTOMERS),
                ('Record Pay Later', TutorialConfig.TUTORIAL_CAPTURE_BNPL),
                ('Add products', TutorialConfig.TUTORIAL_CAPTURE_STOCK),
                ('Record sales', TutorialConfig.TUTORIAL_CAPTURE_SALES),
                ('Wallet & payments', TutorialConfig.TUTORIAL_WALLET),
              ])
                SettingTile(
                  icon: Icons.play_circle_outline_rounded,
                  title: tutorial.$1,
                  onTap: () => onTutorial(tutorial.$1, tutorial.$2),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          Card(
            child: SettingTile(
              icon: SpazaIcons.privacy,
              title: 'Privacy policy',
              hideDivider: true,
              onTap: onPrivacy,
            ),
          ),
          const SizedBox(height: 24),
          CustomButton(
            margin: EdgeInsets.zero,
            icon: FontAwesomeIcons.whatsapp,
            title: 'Chat with support',
            onTap: onSupport,
          ),
        ],
      );
}
