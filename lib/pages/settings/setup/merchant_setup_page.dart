import 'package:flutter/material.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/contact/add_contact/add_contact.dart';
import 'package:pasella/pages/settings/share/share.dart';
import 'package:pasella/pages/wallet/tabs/info_center_tab.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/services/sales_intent_bus.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_setup_card.dart';
import 'package:provider/provider.dart';

/// Keeps the full setup workflow available without placing it above the
/// merchant's day-to-day customer list.
class MerchantSetupPage extends StatelessWidget {
  const MerchantSetupPage({super.key});

  void _openMainTab(BuildContext context, int index) {
    context.read<AppModel>().updateCurrentIndex(index);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final userId = StoreSession.instance.storeId;
    return Scaffold(
      appBar: const CustomAppBar(title: 'Shop setup'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        children: [
          MerchantSetupCard(
            userId: userId,
            allowCompletedLinkDismissal: false,
            actions: MerchantSetupActions(
              onAddCustomer: () => Navigator.of(context).pushNamed(
                AddContactPage.id,
              ),
              onAddProduct: () => _openMainTab(context, 1),
              onChooseWhatsAppProducts: () => _openMainTab(context, 1),
              onOpenOrderingLink: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SharePage(source: 'setup_guide'),
                ),
              ),
              onOpenBanking: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const WalletPage(
                    initialTab: WalletInitialTab.account,
                    initialAccountView: InfoView.banking,
                  ),
                ),
              ),
              onCreateTemplate: () {
                SalesIntentBus.instance.stash(
                  const SalesIntent.marketing(
                    marketingView: SalesIntentMarketingView.promotions,
                  ),
                );
                _openMainTab(context, 2);
              },
            ),
          ),
        ],
      ),
    );
  }
}
