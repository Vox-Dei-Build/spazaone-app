import 'package:flutter/material.dart';
import 'package:pasella/pages/profile/business_name_page.dart';
import 'package:pasella/pages/settings/setup/merchant_setup_page.dart';
import 'package:pasella/pages/settings/share/share.dart';
import 'package:pasella/pages/settings/stores/store_management_page.dart';
import 'package:pasella/pages/wallet/tabs/info_center_tab.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_setup_state.dart';
import 'package:pasella/utils/feature_flags.dart';

class YourShopPage extends StatelessWidget {
  const YourShopPage({super.key});

  @override
  Widget build(BuildContext context) {
    final storeId = StoreSession.instance.storeId;
    return Scaffold(
      appBar: const CustomAppBar(title: 'Your shop'),
      body: StreamBuilder<MerchantSetupState>(
        stream: watchMerchantSetup(storeId),
        initialData: const MerchantSetupState.loading(),
        builder: (context, snapshot) {
          final state = snapshot.data ?? const MerchantSetupState.loading();
          return YourShopOverview(
            state: state,
            showStoresAndTeam: FeatureFlags.enableMultiStoreOperators,
            onSetup: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MerchantSetupPage(),
              ),
            ),
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
          );
        },
      ),
    );
  }
}

class YourShopOverview extends StatelessWidget {
  const YourShopOverview({
    super.key,
    required this.state,
    required this.showStoresAndTeam,
    required this.onSetup,
    required this.onShopLink,
    required this.onStoreDetails,
    required this.onStoresAndTeam,
    required this.onOnlinePayments,
  });

  final MerchantSetupState state;
  final bool showStoresAndTeam;
  final VoidCallback onSetup;
  final VoidCallback onShopLink;
  final VoidCallback onStoreDetails;
  final VoidCallback onStoresAndTeam;
  final VoidCallback onOnlinePayments;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('your-shop-overview'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        _SetupProgressCard(state: state, onTap: onSetup),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              _ShopDestination(
                icon: Icons.link_rounded,
                title: 'Shop link',
                subtitle: 'Share your WhatsApp ordering link',
                onTap: onShopLink,
              ),
              const Divider(height: 1),
              _ShopDestination(
                icon: Icons.storefront_outlined,
                title: 'Store details',
                subtitle: 'Update the name customers see',
                onTap: onStoreDetails,
              ),
              if (showStoresAndTeam) ...[
                const Divider(height: 1),
                _ShopDestination(
                  icon: Icons.groups_outlined,
                  title: 'Stores & team',
                  subtitle: 'Switch stores and manage access',
                  onTap: onStoresAndTeam,
                ),
              ],
              const Divider(height: 1),
              _ShopDestination(
                icon: Icons.account_balance_outlined,
                title: 'Online payments',
                subtitle: 'Set up your bank account for online sales',
                onTap: onOnlinePayments,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SetupProgressCard extends StatelessWidget {
  const _SetupProgressCard({required this.state, required this.onTap});

  final MerchantSetupState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final completed = state.completedSteps;
    final total = state.totalSteps;
    final complete = state.isComplete && !state.loading;
    return Card(
      key: const ValueKey('your-shop-setup-progress'),
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    complete
                        ? Icons.check_circle_outline_rounded
                        : Icons.rocket_launch_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          complete
                              ? 'Shop setup complete'
                              : 'Finish setting up your shop',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(state.loading
                            ? 'Checking progress…'
                            : '$completed of $total done'),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              if (!complete) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: state.loading || total == 0 ? null : completed / total,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(99),
                ),
              ],
            ],
          ),
        ),
      ),
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
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}
