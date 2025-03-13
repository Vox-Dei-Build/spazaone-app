import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/tabs/histroy_tab.dart';
import 'package:pasella/pages/wallet/tabs/pricing_tab.dart';
import 'package:pasella/pages/wallet/tabs/top_up_tab.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/shared/widgets/page_header.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/feature_flags.dart';

class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  static const id = '/walletPage';

  @override
  Widget build(BuildContext context) {
    final WalletViewModel walletVM = WalletViewModel();

    // 🔥 Dynamically generate the tab views based on feature flags
    final List<Widget> tabViews = [];
    final List<Tab> tabLabels = [];

    if (FeatureFlags.enableTopUp) {
      tabLabels.add(const Tab(text: 'Top-Up'));
      tabViews.add(const TopUpTab());
    }

    if (FeatureFlags.enableTransactionHistory) {
      tabLabels.add(const Tab(text: 'Transaction History'));
      tabViews.add(const TransactionHistoryTab());
    }

    if (FeatureFlags.enablePricingInfo) {
      tabLabels.add(const Tab(text: 'Pricing Info'));
      tabViews.add(const PricingInfoTab());
    }

    return DefaultTabController(
      length: tabLabels.length,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: SizeConfig.imageSizeMultiplier * 4),
            child: Column(
              children: [
                SizedBox(height: SizeConfig.heightMultiplier * 2),
                const PageHeader(),
                SizedBox(height: SizeConfig.heightMultiplier * 5),

                // 🟢 Always Visible Balance Section
                StreamBuilder<WalletState>(
                  stream: walletVM.walletStateStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final walletState = snapshot.data!;

                    return Column(
                      children: [
                        Text(
                          'Balance',
                          style:
                              Theme.of(context).textTheme.titleMedium!.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        SizedBox(height: SizeConfig.heightMultiplier * 2),
                        Text(
                          CurrencyUtil.format(walletState.balance),
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge!
                              .copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    );
                  },
                ),

                SizedBox(height: SizeConfig.heightMultiplier * 3),

                // 🟢 Tabs Section
                TabBar(
                  isScrollable: true,
                  labelStyle: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.8,
                    fontWeight: FontWeight.normal,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.8,
                    fontWeight: FontWeight.normal,
                  ),
                  tabs: tabLabels, // 🔥 Dynamically populated
                ),

                // 🟢 Expanded Tab Views
                Expanded(
                  child: TabBarView(
                    children: tabViews, // 🔥 Dynamically populated
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
