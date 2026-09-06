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
            const SizedBox(height: 8),
            const PrimaryWorkspaceHeader(
              shareSource: 'customers_header',
            ),
            const SizedBox(height: 8),
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
                  LedgerDeferredTab(
                    tabIndexNotifier: tabIndexNotifier,
                    tabIndex: 1,
                    builder: (_) => const BusinessReportPage(
                      view: ReportView.activity,
                    ),
                  ),
                  LedgerDeferredTab(
                    tabIndexNotifier: tabIndexNotifier,
                    tabIndex: 2,
                    builder: (_) => const BusinessReportPage(
                      view: ReportView.summary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Defers report construction until its tab is selected for the first time.
///
/// `TabBarView` may lay out a neighbouring page in advance. The Activity page
/// fans out across customer transaction subcollections, so constructing it
/// while the merchant is still on Customers creates avoidable Firestore reads.
class LedgerDeferredTab extends StatefulWidget {
  const LedgerDeferredTab({
    super.key,
    required this.tabIndexNotifier,
    required this.tabIndex,
    required this.builder,
  });

  final ValueNotifier<int> tabIndexNotifier;
  final int tabIndex;
  final WidgetBuilder builder;

  @override
  State<LedgerDeferredTab> createState() => _LedgerDeferredTabState();
}

class _LedgerDeferredTabState extends State<LedgerDeferredTab> {
  late bool _activated;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _activated = widget.tabIndexNotifier.value == widget.tabIndex;
    widget.tabIndexNotifier.addListener(_handleTabChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = DefaultTabController.maybeOf(context);
    if (!identical(_tabController, nextController)) {
      _tabController?.removeListener(_handleTabChanged);
      _tabController = nextController;
      _tabController?.addListener(_handleTabChanged);
    }
    _activateIfSelected();
  }

  @override
  void didUpdateWidget(covariant LedgerDeferredTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndexNotifier != widget.tabIndexNotifier) {
      oldWidget.tabIndexNotifier.removeListener(_handleTabChanged);
      widget.tabIndexNotifier.addListener(_handleTabChanged);
    }
    _activateIfSelected();
  }

  void _handleTabChanged() {
    if (!mounted || _activated || !_isSelected) return;
    setState(() => _activated = true);
  }

  bool get _isSelected =>
      widget.tabIndexNotifier.value == widget.tabIndex ||
      _tabController?.index == widget.tabIndex;

  void _activateIfSelected() {
    if (!_activated && _isSelected) _activated = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_activated) return const SizedBox.shrink();
    return widget.builder(context);
  }

  @override
  void dispose() {
    widget.tabIndexNotifier.removeListener(_handleTabChanged);
    _tabController?.removeListener(_handleTabChanged);
    super.dispose();
  }
}
