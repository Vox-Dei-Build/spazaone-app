import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/pages/contact/view_model/customer_management_view_model.dart';
import 'package:pasella/pages/transactions/widgets/customer_balance_hero.dart';
import 'package:pasella/pages/transactions/widgets/pay_later_action_bar.dart';
import 'package:pasella/pages/transactions/widgets/transactions_list_view.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/shared/widgets/empty_state_onboarding.dart';
import 'package:provider/provider.dart';

/// Pay Later (a.k.a. Transactions Management) screen.
///
/// Layout (top -> bottom):
///   [report panel (collapsible)]
///   [transactions list — Expanded, scrollable, chat-style]
///   [compact balance hero]   <- always visible; states: Owing / In credit / Settled
///   [sticky action bar]      <- bottomNavigationBar slot; safe-area aware
///
/// Previous design rendered a heavy white BalanceSummaryCard footer with
/// the Credit/Payment CTAs injected into it via BalanceSummary.children
/// (a List<Widget> field on the data model). The hero + sticky bar split
/// removes that model leakage and gives the merchant a thumb-reachable
/// CTA that doesn't move while they scroll the ledger.
class TransactionsManagementPage extends StatefulWidget {
  final String customerName;
  final String customerId;
  final String? mobileNumber;

  const TransactionsManagementPage(
      {super.key,
      required this.customerName,
      required this.customerId,
      this.mobileNumber});

  @override
  _CustomerManagementPageState createState() => _CustomerManagementPageState();
}

class _CustomerManagementPageState extends State<TransactionsManagementPage> {
  late CustomerManagementViewModel customerManagementViewModel;
  late CustomerBalanceSummaryProvider customerBalanceSummaryProvider;

  @override
  void initState() {
    super.initState();
    customerBalanceSummaryProvider =
        Provider.of<CustomerBalanceSummaryProvider>(context, listen: false);
    customerBalanceSummaryProvider.setCustomerDetails(
        widget.customerName, widget.customerId, widget.mobileNumber);

    customerManagementViewModel = CustomerManagementViewModel(
        widget.customerId,
        widget.customerName,
        customerBalanceSummaryProvider,
        widget.mobileNumber);
  }

  void refreshPage(String? newProfileImageUrl) {
    if (newProfileImageUrl != null) {
      setState(() {
        customerManagementViewModel.profileImageUrl = newProfileImageUrl;
      });
    }
  }

  @override
  void dispose() {
    customerManagementViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final horizontalPadding = SizeConfig.imageSizeMultiplier * 4;

    return ValueListenableBuilder<bool>(
      valueListenable: customerManagementViewModel.sendingReminderNotifier,
      builder: (context, isSending, child) {
        return Stack(
          children: [
            child!,
            if (isSending)
              Positioned.fill(
                child: Container(
                  color: Colors.black45,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      },
      child: Scaffold(
        // Sticky CTAs — always reachable, safe-area aware.
        bottomNavigationBar: PayLaterActionBar(
          customerName: widget.customerName,
          customerId: widget.customerId,
          mobileNumber: widget.mobileNumber,
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: customerManagementViewModel.streamTransactions(
                        customerManagementViewModel.userId, widget.customerId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error: ${snapshot.error}',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: SizeConfig.textMultiplier * 2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        // PAS-AUTH-03: Stock-style empty state. The
                        // recovery actions (Credit / Payment) live in
                        // the sticky bottom action bar, so no third CTA
                        // here — just an explanatory line and the
                        // walkthrough link.
                        return EmptyStateOnboarding(
                          icon: Icons.receipt_long_outlined,
                          headline:
                              'No transactions yet for ${widget.customerName}',
                          subtitle:
                              'Tap Credit when this customer takes goods on '
                              'account, attach a product when stock matters, '
                              'or tap Payment when they settle up.',
                          tutorialKey: TutorialConfig.TUTORIAL_CAPTURE_BNPL,
                          tutorialTitle: 'How to record a credit transaction',
                        );
                      } else {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: SizeConfig.heightMultiplier * 0.5),
                            // The Customer Report panel previously rendered
                            // here is now reachable from the AppBar's
                            // insights icon button (see ProfileAppBar). The
                            // Pay Later tab is now: ledger -> hero -> CTAs.
                            Expanded(
                              child: TransactionsListView(
                                  customerManagementViewModel:
                                      customerManagementViewModel,
                                  transactions: snapshot.data!,
                                  customerId: widget.customerId,
                                  customerName: widget.customerName,
                                  mobileNumber: widget.mobileNumber),
                            ),
                          ],
                        );
                      }
                    },
                  ),
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 1.0),
                const CustomerBalanceHero(),
                SizedBox(height: SizeConfig.heightMultiplier * 0.8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
