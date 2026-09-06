import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/profile/business_name_page.dart';
import 'package:pasella/pages/settings/help/help.dart';
import 'package:pasella/pages/settings/privacy/privacy_page.dart';
import 'package:pasella/pages/settings/setup/merchant_setup_page.dart';
import 'package:pasella/pages/settings/order_options/order_options_page.dart';
import 'package:pasella/pages/settings/stores/store_workspace_card.dart';
import 'package:pasella/services/fcm_service.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:provider/provider.dart';
import 'package:pasella/pages/settings/widgets/setting_tile.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/pages/settings/stores/store_management_page.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/utils/feature_flags.dart';
import '../../shared/widgets/custom_app_bar.dart';
import 'delete/delete_account_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _openDestination(BuildContext context, SettingsDestination destination) {
    switch (destination) {
      case SettingsDestination.businessName:
        Navigator.pushNamed(context, BusinessNamePage.id);
      case SettingsDestination.orderOptions:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => OrderOptionsPage()),
        );
      case SettingsDestination.shopSetup:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MerchantSetupPage()),
        );
      case SettingsDestination.wallet:
        Navigator.pushNamed(context, WalletPage.id);
      case SettingsDestination.notifications:
        FCMService().showPermissionExplanationDialog(context);
      case SettingsDestination.privacy:
        Navigator.pushNamed(context, PrivacyPage.id);
      case SettingsDestination.help:
        Navigator.pushNamed(context, HelpPage.id);
      case SettingsDestination.deleteAccount:
        Navigator.pushNamed(context, DeleteAccountPage.id);
      case SettingsDestination.logout:
        logout(context);
        Hive.box('deepLinkBox').delete('referrerUserId');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Settings'),
      body: SafeArea(
        child: SettingsMenu(
          onSelected: (destination) => _openDestination(context, destination),
          storeWorkspace: ValueListenableBuilder<bool>(
            valueListenable: FeatureFlags.multiStoreOperatorsEnabled,
            builder: (context, enabled, _) {
              if (!enabled) return const SizedBox.shrink();
              final session = context.watch<StoreSession>();
              return StoreWorkspaceCard(
                activeStoreName: session.activeStoreName,
                storeCount: session.stores.length,
                role: session.activeStore?.role.name ?? 'owner',
                loading: session.loading,
                connectionIssue: session.lastError != null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const StoreManagementPage(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

enum SettingsDestination {
  businessName,
  orderOptions,
  shopSetup,
  wallet,
  notifications,
  privacy,
  help,
  logout,
  deleteAccount,
}

/// The production settings layout, also usable with local preview callbacks.
class SettingsMenu extends StatelessWidget {
  const SettingsMenu({
    super.key,
    required this.onSelected,
    this.storeWorkspace,
  });

  final ValueChanged<SettingsDestination> onSelected;
  final Widget? storeWorkspace;

  Widget _destination(
    SettingsDestination destination,
    IconData icon,
    String title, [
    String? subtitle,
  ]) =>
      SettingTile(
        key: ValueKey('settings-${destination.name}'),
        icon: icon,
        title: title,
        subTitle: subtitle,
        hideDivider: true,
        isDestructive: destination == SettingsDestination.deleteAccount,
        onTap: () => onSelected(destination),
      );

  Widget _group(List<Widget> destinations) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: destinations),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('settings-menu'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (storeWorkspace != null) storeWorkspace!,
        const _SettingsSectionLabel('Shop'),
        _group([
          _destination(SettingsDestination.businessName, SpazaIcons.shop,
              'Business name', 'Shown on receipts and customer messages'),
          _destination(SettingsDestination.orderOptions, SpazaIcons.options,
              'Order options', 'Pickup, delivery fees and Pay Later'),
          _destination(SettingsDestination.shopSetup, Icons.checklist_outlined,
              'Shop setup', 'Checklist and WhatsApp ordering link'),
          _destination(SettingsDestination.wallet, SpazaIcons.wallet,
              'Wallet & payments', 'Balance, online payments and costs'),
        ]),
        const _SettingsSectionLabel('Preferences'),
        _group([
          _destination(
              SettingsDestination.notifications,
              SpazaIcons.notifications,
              'Notifications',
              'Customer requests and updates'),
          _destination(SettingsDestination.privacy, SpazaIcons.privacy,
              'Privacy', 'Analytics and crash reports'),
          _destination(SettingsDestination.help, SpazaIcons.help, 'Help',
              'Guides and support'),
        ]),
        const _SettingsSectionLabel('Account'),
        _group([
          _destination(
              SettingsDestination.logout, SpazaIcons.signOut, 'Log out'),
          _destination(SettingsDestination.deleteAccount, SpazaIcons.delete,
              'Delete account', 'Permanently remove your data'),
        ]),
      ],
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 12),
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: kTertiaryColor,
                fontWeight: FontWeight.w500,
              ),
        ),
      );
}
