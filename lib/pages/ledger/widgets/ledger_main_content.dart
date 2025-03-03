import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/ledger/view_model/ledger_view_model.dart';
import 'package:pasella/pages/ledger/widgets/customer_tab.dart';
import 'package:pasella/shared/widgets/page_header.dart';
import 'package:pasella/pages/ledger/widgets/ledger_tab_bar_with_filter.dart';
import 'package:pasella/pages/reports/business_report/business_report.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/shared/widgets/vimeo_video_player.dart';
import 'package:provider/provider.dart';

class LedgerMainContent extends StatelessWidget {
  final LedgerViewModel ledgerViewModel;
  final ValueNotifier<int> tabIndexNotifier;

  const LedgerMainContent({
    Key? key,
    required this.ledgerViewModel,
    required this.tabIndexNotifier,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Consumer<BalanceSummaryProvider>(
      builder: (context, balanceSummary, child) {
        return Column(
          children: [
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            PageHeader(
              actionWidget: Expanded(
                child: IconButton(
                  icon: Icon(
                    Icons.help_outline,
                    color: Colors.black,
                    size: SizeConfig.imageSizeMultiplier * 7,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => VimeoVideoPage(
                          videoId: '951892750',
                          title: 'How to Capture Sales & Credit',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            LedgerTabBarWithFilter(tabIndexNotifier: tabIndexNotifier),
            Expanded(
              child: TabBarView(
                children: [
                  CustomerTab(
                    searchTextNotifier: ledgerViewModel.searchTextNotifier,
                    hasCustomersNotifier: ledgerViewModel.hasCustomersNotifier,
                  ),
                  const BusinessReportPage(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
