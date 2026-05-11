import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/settings/help/help.dart';
import 'package:pasella/pages/settings/privacy/privacy_page.dart';
import 'package:pasella/pages/settings/subscription/subscription.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:provider/provider.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/settings/widgets/setting_tile.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/wallet.dart';

import '../../shared/widgets/custom_app_bar.dart';
import 'share/share.dart';
import 'delete/delete_account_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig for responsiveness

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const CustomAppBar(title: 'Settings'),
      body: SafeArea(
        child: Padding(
          padding: LayoutConstants.padding10Horizontal,
          child: Consumer<AppModel>(
            builder: (context, value, child) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: SizeConfig.heightMultiplier * 1),
                  Expanded(
                    child: ListView(
                      children: [
                        SettingTile(
                          onTap: () => Navigator.pushNamed(
                            context,
                            HelpPage.id,
                          ),
                          icon: Icons.help,
                          title: 'Help',
                          subTitle: 'FAQs, contact us, privacy policy',
                        ),
                        SettingTile(
                          onTap: () => Navigator.pushNamed(
                            context,
                            SharePage.id,
                          ),
                          icon: Icons.share,
                          title: 'Share',
                          subTitle: 'Share with friends and others',
                        ),
                        SettingTile(
                          onTap: () => Navigator.pushNamed(
                            context,
                            WalletPage.id,
                          ),
                          icon: Icons.wallet,
                          title: 'Billing',
                          subTitle: 'Manage your wallet and payments',
                        ),
                        // PAS-UX-10: Subscription page existed
                        // (registered as a route in main.dart) but
                        // had no entry point in Settings, so the
                        // page was effectively orphaned and
                        // merchants couldn't see what tier they
                        // were on. Surfaces the existing page.
                        SettingTile(
                          onTap: () => Navigator.pushNamed(
                            context,
                            SubscriptionPage.id,
                          ),
                          icon: Icons.workspace_premium_outlined,
                          title: 'Subscription',
                          subTitle: 'View and change your plan',
                        ),
                        SettingTile(
                          onTap: () => Navigator.pushNamed(
                            context,
                            PrivacyPage.id,
                          ),
                          icon: Icons.shield_outlined,
                          title: 'Privacy',
                          subTitle: 'Crash reports, analytics, session replay',
                        ),
                        SettingTile(
                          onTap: () => Navigator.pushNamed(
                            context,
                            DeleteAccountPage.id,
                          ),
                          icon: Icons.delete_forever,
                          title: 'Delete Account',
                          subTitle: 'Permanently remove your data',
                        ),
                        SettingTile(
                          onTap: () async {
                            logout(context);
                            var box = Hive.box('deepLinkBox');
                            await box.delete('referrerUserId');
                          },
                          icon: Icons.logout,
                          title: 'Logout',
                        ),
                      ],
                    ),
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
