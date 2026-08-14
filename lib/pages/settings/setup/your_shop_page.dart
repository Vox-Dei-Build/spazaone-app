import 'package:flutter/material.dart';
import 'package:pasella/pages/profile/business_name_page.dart';
import 'package:pasella/pages/settings/share/share.dart';
import 'package:pasella/pages/settings/stores/store_management_page.dart';
import 'package:pasella/pages/wallet/tabs/info_center_tab.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/feature_flags.dart';

class YourShopPage extends StatelessWidget {
  const YourShopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Your shop'),
      body: YourShopOverview(
        showStoresAndTeam: FeatureFlags.enableMultiStoreOperators,
        onShopLink: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SharePage(source: 'your_shop'),
          ),
        ),
        onStoreDetails: () =>
            Navigator.of(context).pushNamed(BusinessNamePage.id),
        onStoresAndTeam: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const StoreManagementPage(),
          ),
        ),
        onOnlinePayments: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const WalletPage(
              initialTab: WalletInitialTab.account,
              initialAccountView: InfoView.banking,
            ),
          ),
        ),
      ),
    );
  }
}

class YourShopOverview extends StatelessWidget {
  const YourShopOverview({
    super.key,
    required this.showStoresAndTeam,
    required this.onShopLink,
    required this.onStoreDetails,
    required this.onStoresAndTeam,
    required this.onOnlinePayments,
  });

  final bool showStoresAndTeam;
  final VoidCallback onShopLink;
  final VoidCallback onStoreDetails;
  final VoidCallback onStoresAndTeam;
  final VoidCallback onOnlinePayments;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('your-shop-overview'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _ShopDestination(
          icon: Icons.link_rounded,
          title: 'Shop link',
          subtitle: 'Share your WhatsApp ordering link',
          onTap: onShopLink,
        ),
        const SizedBox(height: 10),
        _ShopDestination(
          icon: Icons.storefront_outlined,
          title: 'Store details',
          subtitle: 'Update the name customers see',
          onTap: onStoreDetails,
        ),
        if (showStoresAndTeam) ...[
          const SizedBox(height: 10),
          _ShopDestination(
            icon: Icons.groups_outlined,
            title: 'Stores & team',
            subtitle: 'Switch stores and manage access',
            onTap: onStoresAndTeam,
          ),
        ],
        const SizedBox(height: 10),
        _ShopDestination(
          icon: Icons.account_balance_outlined,
          title: 'Online payments',
          subtitle: 'Set up your bank account for online sales',
          onTap: onOnlinePayments,
        ),
      ],
    );
  }
}

class _ShopDestination extends StatelessWidget {
  const _ShopDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: .42),
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          minVerticalPadding: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Icon(icon),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      );
}
