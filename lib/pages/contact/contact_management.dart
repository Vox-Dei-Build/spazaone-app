import 'package:flutter/material.dart';
import 'package:pasella/shared/widgets/workspace_section_tabs.dart';
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
  final int initialTabIndex;

  const CustomerManagementPage({
    super.key,
    required this.customerName,
    required this.customerId,
    this.mobileNumber,
    this.initialTabIndex = 0,
  });

  @override
  State<CustomerManagementPage> createState() => _CustomerManagementPageState();
}

class _CustomerManagementPageState extends State<CustomerManagementPage>
    with SingleTickerProviderStateMixin {
  late CustomerManagementViewModel customerManagementViewModel;
  late CustomerBalanceSummaryProvider customerBalanceSummaryProvider;
  late TabController _tabController;
  late final ValueNotifier<int> _tabIndexNotifier;

  @override
  void initState() {
    super.initState();
    customerBalanceSummaryProvider =
        Provider.of<CustomerBalanceSummaryProvider>(context, listen: false);
    customerBalanceSummaryProvider.setCustomerDetails(
      widget.customerName,
      widget.customerId,
      widget.mobileNumber,
    );

    // Initialize the view model
    customerManagementViewModel = CustomerManagementViewModel(
      widget.customerId,
      widget.customerName,
      customerBalanceSummaryProvider,
      widget.mobileNumber,
    );

    final initialTabIndex = widget.initialTabIndex < 0
        ? 0
        : widget.initialTabIndex > 2
            ? 2
            : widget.initialTabIndex;
    _tabIndexNotifier = ValueNotifier<int>(initialTabIndex);
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialTabIndex,
    );
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
              child: Column(
                children: [
                  Consumer<CustomerManagementViewModel>(
                    builder: (context, model, _) => WorkspaceSectionTabs(
                      controller: _tabController,
                      tabs: [
                        const WorkspaceSectionTab(
                          label: 'Pay later',
                          semanticLabel: 'Pay later',
                        ),
                        WorkspaceSectionTab(
                          label: 'Orders',
                          semanticLabel: 'Orders',
                          badgeCount: model.ordersUnreadCount,
                        ),
                        WorkspaceSectionTab(
                          label: 'Messages',
                          semanticLabel: 'Messages',
                          badgeCount: model.unreadMessagesCount,
                        ),
                      ],
                    ),
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
                          mobileNumber: widget.mobileNumber,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
