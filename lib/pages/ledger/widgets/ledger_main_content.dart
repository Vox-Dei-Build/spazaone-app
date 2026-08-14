import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/ledger/view_model/ledger_view_model.dart';
import 'package:pasella/pages/ledger/widgets/customer_tab.dart';
import 'package:pasella/pages/ledger/widgets/ledger_tab_bar_with_filter.dart';
import 'package:pasella/pages/reports/business_report/business_report.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/shared/widgets/primary_workspace_header.dart';
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
            const PrimaryWorkspaceHeader(
              shareSource: 'customers_header',
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            LedgerTabBarWithFilter(tabIndexNotifier: tabIndexNotifier),
            ValueListenableBuilder<int>(
              valueListenable: tabIndexNotifier,
              builder: (context, tabIndex, _) => Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: Text(
                  switch (tabIndex) {
                    0 => 'People who buy from you',
                    1 => 'Customer payments and purchases by date',
                    _ => 'Customer accounts at a glance',
                  },
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ),
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
                  const BusinessReportPage(view: ReportView.activity),
                  const BusinessReportPage(view: ReportView.summary),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
