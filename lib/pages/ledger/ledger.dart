import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/contact/add_contact/add_contact.dart';
import 'package:pasella/pages/ledger/view_model/ledger_view_model.dart';
import 'package:pasella/pages/ledger/widgets/ledger_floating_action_button.dart';
import 'package:pasella/pages/ledger/widgets/ledger_main_content.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/shared/view_models/balance_summary_view_model.dart';
import 'package:provider/provider.dart';

class LedgerPage extends StatefulWidget {
  const LedgerPage({Key? key}) : super(key: key);

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  late BalanceSummaryViewModel balanceSummaryViewModel;
  final ValueNotifier<int> _tabIndexNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    final ledgerViewModel =
        Provider.of<LedgerViewModel>(context, listen: false);
    ledgerViewModel.initialize(context);

    BalanceSummaryProvider balanceSummaryProvider =
        Provider.of<BalanceSummaryProvider>(context, listen: false);
    balanceSummaryViewModel = BalanceSummaryViewModel(balanceSummaryProvider);
  }

  @override
  void dispose() {
    _tabIndexNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    var ledgerViewModel = Provider.of<LedgerViewModel>(context, listen: false);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        floatingActionButton: ValueListenableBuilder<int>(
          valueListenable: _tabIndexNotifier,
          builder: (context, tabIndex, child) {
            return tabIndex == 0
                ? Padding(
                    padding: EdgeInsets.only(
                      bottom: SizeConfig.heightMultiplier * 1,
                      right: SizeConfig.imageSizeMultiplier * 1,
                    ),
                    child: LedgerFloatingActionButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, AddContactPage.id),
                    ))
                : Container(); // Return an empty container if it's the second tab
          },
        ),
        body: SafeArea(
          child: Padding(
            padding: LayoutConstants.padding10Horizontal,
            // PAS-UX-09: the OnboardingChecklist used to mount here as
            // `belowHeaderCard`. It has moved up to the Dashboard
            // scaffold (lib/pages/dashboard/dashboard.dart) so it's
            // visible across Customers / Products / Sales, matching
            // the industry pattern (Shopify, Stripe, Linear,
            // Intercom) where activation checklists are anchored to
            // the home/dashboard chrome rather than a single feature
            // tab.
            child: LedgerMainContent(
              ledgerViewModel: ledgerViewModel,
              tabIndexNotifier: _tabIndexNotifier,
              // PAS-UX-09: shared "add customer" handler so the empty
              // Customers tab can offer an inline CTA. The same
              // handler is used by the floating "+" FAB above, so
              // both entry points route through one place.
              onAddCustomer: () =>
                  Navigator.pushNamed(context, AddContactPage.id),
            ),
          ),
        ),
      ),
    );
  }
}
