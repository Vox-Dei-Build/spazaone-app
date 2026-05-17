import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/contact/view_model/customer_management_view_model.dart';
import 'package:pasella/pages/reports/customer_report/widgets/customer_report_panel.dart';
import 'package:pasella/pages/transactions/widgets/transactions_list_view.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/shared/widgets/balance_summary/balance_summary_card.dart';
import 'package:provider/provider.dart';

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

    // Initialize the view model
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
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 5,
            ),
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
                        ));
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(
                          child: Text(
                            'No transactions available.',
                            style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 2,
                            ),
                          ),
                        );
                      } else {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: SizeConfig.heightMultiplier * 1.5),
                            // PAS-UX-06A: per-customer report panel.
                            // Collapsed by default so the existing
                            // ledger-list experience is unchanged for
                            // merchants who don't expand it. Derived
                            // entirely from the same transactions list
                            // rendered below it — zero extra reads.
                            CustomerReportPanel(transactions: snapshot.data!),
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
                const BalanceSummaryCard(useCustomerProvider: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
