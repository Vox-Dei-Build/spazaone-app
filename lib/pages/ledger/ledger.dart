import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/contact/add_contact/add_contact.dart';
import 'package:pasella/pages/ledger/view_model/ledger_view_model.dart';
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
      length: 3,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: LayoutConstants.workspacePadding,
            // The customer setup checklist now mounts inside
            // CustomerTab. Keeping it inside the Customers surface
            // makes the first action ("add a customer") match the
            // page context instead of competing with Products or
            // Sales.
            child: LedgerMainContent(
              ledgerViewModel: ledgerViewModel,
              tabIndexNotifier: _tabIndexNotifier,
              // PAS-UX-09: shared "add customer" handler so the empty
              // Customers tab can offer an inline CTA. The same
              // handler remains in the page header at every list state.
              onAddCustomer: () =>
                  Navigator.pushNamed(context, AddContactPage.id),
            ),
          ),
        ),
      ),
    );
  }
}
