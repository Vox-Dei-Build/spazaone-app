import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/pages/ledger/view_model/ledger_view_model.dart';
import 'package:pasella/pages/ledger/widgets/customer_tab.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';
import 'package:pasella/shared/widgets/page_header.dart';
import 'package:pasella/pages/ledger/widgets/ledger_tab_bar_with_filter.dart';
import 'package:pasella/pages/reports/business_report/business_report.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:provider/provider.dart';

class LedgerMainContent extends StatelessWidget {
  final LedgerViewModel ledgerViewModel;
  final ValueNotifier<int> tabIndexNotifier;

  /// Optional in-flow card rendered between the page header / tab bar
  /// and the tab content. Kept as a generic slot for future ledger
  /// surfaces that need page-level context above the tab body.
  final Widget? belowHeaderCard;

  /// PAS-UX-09: tap handler for the empty Customers-tab CTA. Passed
  /// down so the empty state can offer an inline primary action
  /// instead of relying solely on the floating "+" FAB.
  final VoidCallback? onAddCustomer;

  const LedgerMainContent({
    Key? key,
    required this.ledgerViewModel,
    required this.tabIndexNotifier,
    this.belowHeaderCard,
    this.onAddCustomer,
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
              actionWidget: IconButton(
                icon: Icon(
                  Icons.help_outline,
                  color: Colors.black,
                  size: SizeConfig.imageSizeMultiplier * 5,
                ),
                onPressed: () {
                  final url = TutorialConfig.getTutorialUrl(
                    TutorialConfig.TUTORIAL_CAPTURE_CUSTOMERS,
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => LoomVideoPage(
                        loomUrl: url,
                        title: 'How to Add Customers',
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            LedgerTabBarWithFilter(tabIndexNotifier: tabIndexNotifier),
            // In-flow slot for cards that should sit inside the page
            // rhythm (after the tab context) rather than crowning the
            // page above the header.
            if (belowHeaderCard != null) belowHeaderCard!,
            Expanded(
              child: TabBarView(
                children: [
                  CustomerTab(
                    searchTextNotifier: ledgerViewModel.searchTextNotifier,
                    hasCustomersNotifier: ledgerViewModel.hasCustomersNotifier,
                    onAddCustomer: onAddCustomer,
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
