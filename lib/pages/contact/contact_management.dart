import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/contact/connect/connect_manangement.dart';
import 'package:pasella/pages/contact/transactions_management/transactions_management.dart';
import 'package:pasella/pages/contact/widgets/profile_actions_bar.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:provider/provider.dart';
import 'view_model/customer_management_view_model.dart';

class CustomerManagementPage extends StatefulWidget {
  final String customerName;
  final String customerId;
  final String? mobileNumber;

  const CustomerManagementPage(
      {super.key,
      required this.customerName,
      required this.customerId,
      this.mobileNumber});

  @override
  _CustomerManagementPageState createState() => _CustomerManagementPageState();
}

class _CustomerManagementPageState extends State<CustomerManagementPage>
    with SingleTickerProviderStateMixin {
  late CustomerManagementViewModel customerManagementViewModel;
  late CustomerBalanceSummaryProvider customerBalanceSummaryProvider;
  late TabController _tabController;
  final ValueNotifier<int> _tabIndexNotifier = ValueNotifier<int>(0);

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

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      _tabIndexNotifier.value = _tabController.index;
    });
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
    _tabController.dispose();
    _tabIndexNotifier.dispose();
    customerManagementViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: ProfileAppBar(
          customerId: widget.customerId,
          customerName: widget.customerName,
          customerBalanceSummaryProvider: customerBalanceSummaryProvider,
          mobileNumber: widget.mobileNumber,
          onProfileUpdated: refreshPage,
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: SizeConfig.imageSizeMultiplier * 4),
            child: Column(children: [
              TabBar(
                controller: _tabController,
                labelStyle: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.8,
                  fontWeight: FontWeight.normal,
                ),
                unselectedLabelStyle: TextStyle(
                  fontSize: SizeConfig.textMultiplier *
                      1.8, // Font size for unselected tabs
                  fontWeight:
                      FontWeight.normal, // Font weight for unselected tabs
                ),
                tabs: const [
                  Tab(text: 'Transcations'),
                  Tab(text: 'Messages'),
                  Tab(text: 'Report'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    TransactionsManagementPage(
                      customerName: widget.customerName,
                      customerId: widget.customerId,
                      mobileNumber: widget.mobileNumber,
                    ),
                    ConnectManagementPage(
                      customerId: widget.customerId,
                      profileImageUrl:
                          customerManagementViewModel.profileImageUrl,
                      customerName: widget.customerName,
                    ),
                    Container(),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
