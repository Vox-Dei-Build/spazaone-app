import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/profile/business_name_page.dart';
import 'package:pasella/pages/settings/help/help.dart';
import 'package:pasella/pages/settings/privacy/privacy_page.dart';
import 'package:pasella/pages/settings/setup/merchant_setup_page.dart';
import 'package:pasella/services/fcm_service.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:provider/provider.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/settings/widgets/setting_tile.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/pages/settings/stores/store_management_page.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/utils/feature_flags.dart';

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
                        ValueListenableBuilder<bool>(
                          valueListenable:
                              FeatureFlags.multiStoreOperatorsEnabled,
                          builder: (context, enabled, _) {
                            if (!enabled) {
                              return const SizedBox.shrink();
                            }

                            return SettingTile(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const StoreManagementPage(),
                                ),
                              ),
                              icon: Icons.storefront_outlined,
                              title: 'Stores & Operators',
                              subTitle:
                                  'Current: ${context.watch<StoreSession>().activeStoreName}',
                            );
                          },
                        ),
                        SettingTile(
                          onTap: () => Navigator.pushNamed(
                            context,
                            BusinessNamePage.id,
                          ),
                          icon: Icons.store,
                          title: 'Business Name',
                          subTitle: 'Shown on receipts and customer messages',
                        ),
                        SettingTile(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MerchantSetupPage(),
                            ),
                          ),
                          icon: Icons.checklist_rounded,
                          title: 'Setup Guide',
                          subTitle: 'Customers, products, WhatsApp and payouts',
                        ),
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
                          icon: Icons.storefront_outlined,
                          title: 'WhatsApp Ordering Link',
                          subTitle: 'Share your shop code and ordering link',
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
                          onTap: () => FCMService()
                              .showPermissionExplanationDialog(context),
                          icon: Icons.notifications_outlined,
                          title: 'Notifications',
                          subTitle:
                              'Enable payment reminders and account updates',
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
