import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/contact/add_contact/add_contact.dart';
import 'package:pasella/pages/ledger/view_model/ledger_view_model.dart';
import 'package:pasella/pages/ledger/widgets/ledger_floating_action_button.dart';
import 'package:pasella/pages/ledger/widgets/ledger_main_content.dart';
import 'package:pasella/pages/promote/promote_intent_bus.dart';
import 'package:pasella/pages/promote/promotions_page.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/shared/view_models/balance_summary_view_model.dart';
import 'package:pasella/shared/widgets/onboarding/onboarding_checklist.dart';
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
            child: LedgerMainContent(
              ledgerViewModel: ledgerViewModel,
              tabIndexNotifier: _tabIndexNotifier,
              // PAS-UX-02 (pre-release follow-up): the onboarding
              // checklist now mounts inside the page rhythm — below
              // the page header and tab bar — rather than as a
              // top-of-page banner. Release testers flagged the old
              // placement as visually disconnected from the rest of
              // the surface and treated it as an interstitial rather
              // than part of the page.
              //
              // The widget is still internally guarded (only paints
              // when the user hasn't dismissed it and at least one
              // item is incomplete) so existing merchants see no
              // visual change. Customers / Ledger remains the
              // highest-leverage placement because it's the default
              // landing surface after login.
              belowHeaderCard:
                  FirebaseAuth.instance.currentUser?.uid == null
                      ? null
                      : OnboardingChecklist(
                          userId: FirebaseAuth.instance.currentUser!.uid,
                          onAddProduct: () {
                            // Switch to Stock tab and push the New
                            // Product page so the merchant lands on
                            // the form, not the empty Stock tab.
                            final app = context.read<AppModel>();
                            app.updateCurrentIndex(1);
                          },
                          onAddCustomer: () => Navigator.pushNamed(
                              context, AddContactPage.id),
                          onRecordSale: () =>
                              context.read<AppModel>().updateCurrentIndex(2),
                          onApproveTemplate: () {
                            // Land the merchant on the Templates tab
                            // so they can create one. The shared
                            // PromoteIntentBus is the canonical way
                            // to pre-route the Promote surface.
                            PromoteIntentBus.instance.set(
                              const PromoteIntent(tab: 'templates'),
                            );
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PromotionsPage(),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ),
      ),
    );
  }
}
