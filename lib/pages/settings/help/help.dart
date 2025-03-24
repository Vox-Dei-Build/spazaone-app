import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/pages/settings/widgets/setting_tile.dart';
import 'package:pasella/shared/widgets/vimeo_video_player.dart';
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
          padding: LayoutConstants.padding20Horizontal,
          child: Column(
            children: [
              SettingTile(
                icon: Icons.help,
                title: 'How to use Pasella?',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) =>
                      const VimeoVideoPage(videoId: '935735574', title: ''),
                )),
              ),
              SettingTile(
                icon: Icons.help,
                title: 'How to Capture Sales & Credit?',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) =>
                      const VimeoVideoPage(videoId: '951892750', title: ''),
                )),
              ),
              SettingTile(
                icon: Icons.help,
                title: 'How to Capture Stock?',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const VimeoVideoPage(
                      videoId: '951892750',
                      title: 'How to add stock and link it to transactions?'),
                )),
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
                onTap: () => SupportUtil.sendSupportWhatsAppMessage(context),
              ),
              const SizedBox(height: 15.0),
            ],
          ),
        ),
      ),
    );
  }
}
