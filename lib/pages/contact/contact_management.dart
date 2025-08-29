import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/contact/connect/connect_manangement.dart';
import 'package:pasella/pages/ecommerce/orders_management/orders_management_page.dart';
import 'package:pasella/pages/transactions/transactions_management/transactions_management.dart';
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

      // ✅ Use the local instance, not Provider.of(...)
      if (_tabController.indexIsChanging == false &&
          _tabController.index == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          customerManagementViewModel.clearOrdersUnread();
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tabIndexNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return ChangeNotifierProvider(
      create: (_) => customerManagementViewModel,
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: ProfileAppBar(
            customerBalanceSummaryProvider: customerBalanceSummaryProvider,
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: Column(children: [
                TabBar(
                  controller: _tabController,
                  labelStyle: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.8,
                    fontWeight: FontWeight.normal,
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.8,
                    fontWeight: FontWeight.normal,
                  ),
                  tabs: [
                    const Tab(text: 'Pay Later'),
                    Consumer<CustomerManagementViewModel>(
                      builder: (context, model, child) {
                        final count = model.ordersUnreadCount;
                        return Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Orders'),
                              if (count > 0)
                                Padding(
                                  padding: EdgeInsets.only(
                                      left: SizeConfig.imageSizeMultiplier * 1),
                                  child: CircleAvatar(
                                    radius:
                                        SizeConfig.imageSizeMultiplier * 2.3,
                                    backgroundColor: Colors.red,
                                    child: Text(
                                      count.toString(),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize:
                                            SizeConfig.textMultiplier * 1.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    Consumer<CustomerManagementViewModel>(
                      // 🔥 Wrap this tab with Consumer
                      builder: (context, model, child) {
                        return Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Messages'),
                              if (model.unreadMessagesCount >
                                  0) // 🔥 Show badge only if unread messages exist
                                Padding(
                                  padding: EdgeInsets.only(
                                      left: SizeConfig.imageSizeMultiplier * 1),
                                  child: CircleAvatar(
                                    radius:
                                        SizeConfig.imageSizeMultiplier * 2.3,
                                    backgroundColor: Colors.green,
                                    child: Text(
                                      model.unreadMessagesCount.toString(),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize:
                                            SizeConfig.textMultiplier * 1.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
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
                      OrdersManagementPage(
                        customerId: widget.customerId,
                        customerName: widget.customerName,
                      ),
                      ConnectManagementPage(
                        customerId: widget.customerId,
                        profileImageUrl:
                            customerManagementViewModel.profileImageUrl,
                        customerName: widget.customerName,
                        mobileNumber: widget.mobileNumber,
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
