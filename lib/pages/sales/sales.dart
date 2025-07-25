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
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotions_tab.dart';
import 'package:pasella/pages/promote/widgets/templates/templates_tab.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/run_promotion_page.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/create_template.dart';

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

  late final TabController _mainController;
  late final TabController _salesController;
  late final TabController _marketingController;

  @override
  void initState() {
    super.initState();
    _mainController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _salesController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _marketingController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _salesController.dispose();
    _marketingController.dispose();
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

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SalesViewModel()),
        ChangeNotifierProvider(
          create: (_) {
            final vm = PromotionsViewModel();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              vm.loadInitialData();
            });
            return vm;
          },
        ),
      ],
      child: Consumer2<SalesViewModel, PromotionsViewModel>(
        builder: (context, viewModel, promotionsVM, child) {
          return Scaffold(
            floatingActionButton:
                _buildFloatingActionButton(viewModel, promotionsVM),
            body: SafeArea(
              child: Padding(
                padding: LayoutConstants.padding10Horizontal,
                child: Column(
                  children: [
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    const SalesPageHeader(),
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    TabBar(
                      controller: _mainController,
                      labelStyle: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.8,
                        fontWeight: FontWeight.normal,
                      ),
                      unselectedLabelStyle: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.8,
                        fontWeight: FontWeight.normal,
                      ),
                      tabs: const [
                        Tab(text: 'Sales'),
                        Tab(text: 'Marketing'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _mainController,
                        children: [
                          // Sales Category
                          Column(
                            children: [
                              TabBar(
                                controller: _salesController,
                                labelStyle: TextStyle(
                                  fontSize: SizeConfig.textMultiplier * 1.8,
                                  fontWeight: FontWeight.normal,
                                ),
                                unselectedLabelStyle: TextStyle(
                                  fontSize: SizeConfig.textMultiplier * 1.8,
                                  fontWeight: FontWeight.normal,
                                ),
                                tabs: const [
                                  Tab(text: 'Cash'),
                                  Tab(text: 'Online'),
                                ],
                              ),
                              Expanded(
                                child: TabBarView(
                                  controller: _salesController,
                                  children: [
                                    SingleChildScrollView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      child: Column(
                                        children: <Widget>[
                                          SizedBox(
                                              height:
                                                  SizeConfig.heightMultiplier *
                                                      2),
                                          ReportCalendarView(
                                            selectedDay: _selectedDay,
                                            startDate: _startDate,
                                            endDate: _endDate,
                                            onDateSelected: _onDateSelected,
                                            onDateRangeSelected:
                                                _onDateRangeSelected,
                                            onInternalDateSelect: (date) =>
                                                viewModel
                                                    .updateSelectedDate(date),
                                            onInternalRangeSelect:
                                                (start, end) => viewModel
                                                    .updateSelectedDateRange(
                                                        start, end),
                                          ),
                                          SizedBox(
                                              height:
                                                  SizeConfig.heightMultiplier *
                                                      1.5),
                                          SalesStatsCard(
                                            viewModel: viewModel,
                                            selectedDay: _selectedDay,
                                            startDate: _startDate,
                                            endDate: _endDate,
                                          ),
                                          SizedBox(
                                              height:
                                                  SizeConfig.heightMultiplier *
                                                      1.5),
                                          ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxHeight: MediaQuery.of(context)
                                                      .size
                                                      .height *
                                                  0.5,
                                            ),
                                            child:
                                                SalesList(viewModel: viewModel),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const ComingSoonTab(),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // Marketing Category
                          Column(
                            children: [
                              TabBar(
                                controller: _marketingController,
                                labelStyle: TextStyle(
                                  fontSize: SizeConfig.textMultiplier * 1.8,
                                  fontWeight: FontWeight.normal,
                                ),
                                unselectedLabelStyle: TextStyle(
                                  fontSize: SizeConfig.textMultiplier * 1.8,
                                  fontWeight: FontWeight.normal,
                                ),
                                tabs: const [
                                  Tab(text: 'Promotions'),
                                  Tab(text: 'Templates'),
                                ],
                              ),
                              Expanded(
                                child: TabBarView(
                                  controller: _marketingController,
                                  children: const [
                                    PromotionsTab(),
                                    TemplatesTab(),
                                  ],
                                ),
                              ),
                            ],
                          ),
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

  Widget? _buildFloatingActionButton(
      SalesViewModel salesVM, PromotionsViewModel promoVM) {
    if (_mainController.index == 0) {
      switch (_salesController.index) {
        case 0:
          return Padding(
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
                      builder: (context) => AddSale(salesViewModel: salesVM),
                    ),
                  )
                      .then((_) {
                    _salesController.animateTo(0);
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
          );
        default:
          return null;
      }
    } else {
      switch (_marketingController.index) {
        case 0:
          final hasApproved = promoVM.templates.any((t) =>
              (t['channels']?['whatsapp']?['approved'] == true) ||
              (t['channels']?['sms']?['approved'] == true));
          return FloatingActionButton.extended(
            onPressed: () {
              if (!hasApproved) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('No Approved Templates'),
                    content: const Text(
                        'You need at least one approved template before you can run a promotion. '
                        'Head over to the Templates tab to create and approve one.'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _marketingController.animateTo(1);
                        },
                        child: const Text('Go to Templates'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                );
              } else {
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => const RunPromotionPage(),
                      ),
                    )
                    .then((_) => _marketingController.animateTo(0));
              }
            },
            icon: Icon(
              Icons.campaign_outlined,
              size: SizeConfig.heightMultiplier * 2.5,
              color: Colors.white,
            ),
            label: Text(
              'Run Promotion',
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 2,
                color: Colors.white,
              ),
            ),
          );
        case 1:
          return FloatingActionButton.extended(
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => CreateTemplatePage(viewModel: promoVM),
                    ),
                  )
                  .then((_) => _marketingController.animateTo(1));
            },
            icon: Icon(
              Icons.library_books_outlined,
              size: SizeConfig.heightMultiplier * 2.5,
              color: Colors.white,
            ),
            label: Text(
              'Create Template',
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 2,
                color: Colors.white,
              ),
            ),
          );
        default:
          return null;
      }
    }
  }
}
