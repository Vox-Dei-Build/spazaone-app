import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/sales/widgets/add_sale.dart';
import 'package:pasella/pages/reports/widgets/report_calendar_view.dart';
import 'package:pasella/pages/sales/widgets/sales_list.dart';
import 'package:pasella/pages/sales/widgets/sales_page_header.dart';
import 'package:pasella/pages/sales/widgets/sales_stats_card.dart';
import 'package:pasella/pages/settings/coming_soon/coming_soon_tab.dart';
import 'package:provider/provider.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({Key? key}) : super(key: key);

  static const id = '/salesPage';

  @override
  _SalesPageState createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> with TickerProviderStateMixin {
  DateTime? _selectedDay = DateTime.now();
  DateTime? _startDate;
  DateTime? _endDate;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onDateSelected(DateTime selectedDay) {
    setState(() {
      _selectedDay = selectedDay;
      _startDate = null;
      _endDate = null;
    });
  }

  void _onDateRangeSelected(DateTime start, DateTime end) {
    setState(() {
      _startDate = start;
      _endDate = end;
      _selectedDay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return ChangeNotifierProvider(
      create: (_) => SalesViewModel(),
      child: Consumer<SalesViewModel>(
        builder: (context, viewModel, child) {
          return Scaffold(
            floatingActionButton: _tabController.index == 0
                ? Padding(
                    padding: EdgeInsets.only(
                      bottom: SizeConfig.heightMultiplier * 1,
                      right: SizeConfig.imageSizeMultiplier * 1,
                    ),
                    child: SizedBox(
                      height: SizeConfig.heightMultiplier * 7,
                      child: FloatingActionButton.extended(
                        elevation: 3.0,
                        onPressed: () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  AddSale(salesViewModel: viewModel),
                            ),
                          )
                              .then((_) {
                            // snap back to “Sales” tab when you pop
                            _tabController.animateTo(0);
                          });
                        },
                        icon: Icon(
                          Icons.add_outlined,
                          color: Colors.white,
                          size: SizeConfig.heightMultiplier * 2.5,
                        ),
                        label: Text(
                          'Add Sale',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: SizeConfig.textMultiplier * 2,
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
            body: SafeArea(
              child: Padding(
                padding: LayoutConstants.padding10Horizontal,
                child: Column(
                  children: [
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    const SalesPageHeader(),
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    TabBar(
                      controller: _tabController,
                      labelStyle: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.8,
                        fontWeight: FontWeight.normal,
                      ),
                      unselectedLabelStyle: TextStyle(
                        fontSize: SizeConfig.textMultiplier *
                            1.8, // Font size for unselected tabs
                        fontWeight: FontWeight
                            .normal, // Font weight for unselected tabs
                      ),
                      tabs: const [
                        Tab(text: 'Cash'),
                        Tab(text: 'Online'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // Cash tab content
                          SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Column(
                              children: <Widget>[
                                SizedBox(
                                    height: SizeConfig.heightMultiplier * 2),
                                ReportCalendarView(
                                  selectedDay: _selectedDay,
                                  startDate: _startDate,
                                  endDate: _endDate,
                                  onDateSelected: _onDateSelected,
                                  onDateRangeSelected: _onDateRangeSelected,
                                  onInternalDateSelect: (date) =>
                                      viewModel.updateSelectedDate(date),
                                  onInternalRangeSelect: (start, end) =>
                                      viewModel.updateSelectedDateRange(
                                          start, end),
                                ),
                                SizedBox(
                                    height: SizeConfig.heightMultiplier * 1.5),
                                SalesStatsCard(
                                  viewModel: viewModel,
                                  selectedDay: _selectedDay,
                                  startDate: _startDate,
                                  endDate: _endDate,
                                ),
                                SizedBox(
                                    height: SizeConfig.heightMultiplier * 1.5),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight:
                                        MediaQuery.of(context).size.height *
                                            0.5,
                                  ),
                                  child: SalesList(viewModel: viewModel),
                                ),
                              ],
                            ),
                          ),

                          // Online tab content
                          const ComingSoonTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
