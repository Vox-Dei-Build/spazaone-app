// All existing imports stay
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/sales/widgets/add_sale.dart';
import 'package:pasella/pages/reports/widgets/report_calendar_view.dart';
import 'package:pasella/pages/sales/widgets/sales_list.dart';
import 'package:pasella/pages/sales/widgets/sales_page_header.dart';
import 'package:pasella/pages/sales/widgets/sales_stats_card.dart';
import 'package:pasella/pages/sales/widgets/online_sales_list.dart';
import 'package:provider/provider.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotions_tab.dart';
import 'package:pasella/pages/promote/widgets/templates/templates_tab.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/run_promotion_page.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/create_template.dart';

enum SalesViewType { cash, online }

enum MarketingViewType { promotions, templates }

class SalesPage extends StatefulWidget {
  const SalesPage({Key? key}) : super(key: key);
  static const id = '/salesPage';

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> with TickerProviderStateMixin {
  DateTime? _selectedDay = DateTime.now();
  DateTime? _startDate;
  DateTime? _endDate;

  late final TabController _mainController;

  SalesViewType _selectedSalesView = SalesViewType.cash;
  MarketingViewType _selectedMarketingView = MarketingViewType.promotions;

  @override
  void initState() {
    super.initState();
    _mainController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _mainController.dispose();
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
        builder: (context, salesVM, promoVM, child) {
          return Scaffold(
            floatingActionButton: _buildFAB(salesVM, promoVM),
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
                          // --- SALES ---
                          Column(
                            children: [
                              const SizedBox(height: 16),
                              Theme(
                                data: Theme.of(context).copyWith(
                                  segmentedButtonTheme:
                                      SegmentedButtonThemeData(
                                    style: ButtonStyle(
                                      backgroundColor: MaterialStateProperty
                                          .resolveWith<Color?>(
                                        (states) => states.contains(
                                                MaterialState.selected)
                                            ? Colors.green
                                            : Colors.white,
                                      ),
                                      foregroundColor: MaterialStateProperty
                                          .resolveWith<Color?>(
                                        (states) => states.contains(
                                                MaterialState.selected)
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                                child: SegmentedButton<SalesViewType>(
                                  segments: [
                                    ButtonSegment(
                                      value: SalesViewType.cash,
                                      label: Text('Cash',
                                          style: TextStyle(
                                              fontSize:
                                                  SizeConfig.textMultiplier *
                                                      1.5,
                                              fontWeight: FontWeight.bold)),
                                      icon: Icon(Icons.attach_money,
                                          size:
                                              SizeConfig.textMultiplier * 1.5),
                                    ),
                                    ButtonSegment(
                                      value: SalesViewType.online,
                                      label: Text('Online',
                                          style: TextStyle(
                                              fontSize:
                                                  SizeConfig.textMultiplier *
                                                      1.5,
                                              fontWeight: FontWeight.bold)),
                                      icon: Icon(Icons.wifi,
                                          size:
                                              SizeConfig.textMultiplier * 1.5),
                                    ),
                                  ],
                                  selected: {_selectedSalesView},
                                  onSelectionChanged: (val) {
                                    setState(() {
                                      _selectedSalesView = val.first;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: _selectedSalesView == SalesViewType.cash
                                    ? SingleChildScrollView(
                                        child: Column(
                                          children: [
                                            SizedBox(
                                                height: SizeConfig
                                                        .heightMultiplier *
                                                    2),
                                            ReportCalendarView(
                                              selectedDay: _selectedDay,
                                              startDate: _startDate,
                                              endDate: _endDate,
                                              onDateSelected: _onDateSelected,
                                              onDateRangeSelected:
                                                  _onDateRangeSelected,
                                              onInternalDateSelect:
                                                  salesVM.updateSelectedDate,
                                              onInternalRangeSelect: salesVM
                                                  .updateSelectedDateRange,
                                            ),
                                            SizedBox(
                                                height: SizeConfig
                                                        .heightMultiplier *
                                                    1.5),
                                            SalesStatsCard(
                                              viewModel: salesVM,
                                              selectedDay: _selectedDay,
                                              startDate: _startDate,
                                              endDate: _endDate,
                                            ),
                                            SizedBox(
                                                height: SizeConfig
                                                        .heightMultiplier *
                                                    1.5),
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxHeight:
                                                    MediaQuery.of(context)
                                                            .size
                                                            .height *
                                                        0.5,
                                              ),
                                              child:
                                                  SalesList(viewModel: salesVM),
                                            ),
                                          ],
                                        ),
                                      )
                                    : SingleChildScrollView(
                                        child: Column(
                                          children: [
                                            SizedBox(
                                                height: SizeConfig
                                                        .heightMultiplier *
                                                    2),
                                            ReportCalendarView(
                                              selectedDay: _selectedDay,
                                              startDate: _startDate,
                                              endDate: _endDate,
                                              onDateSelected: _onDateSelected,
                                              onDateRangeSelected:
                                                  _onDateRangeSelected,
                                              onInternalDateSelect: (_) {},
                                              onInternalRangeSelect: (_, __) {},
                                            ),
                                            SizedBox(
                                                height: SizeConfig
                                                        .heightMultiplier *
                                                    1.5),
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxHeight:
                                                    MediaQuery.of(context)
                                                            .size
                                                            .height *
                                                        0.5,
                                              ),
                                              child: OnlineSalesList(
                                                selectedDay: _selectedDay,
                                                startDate: _startDate,
                                                endDate: _endDate,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ],
                          ),

                          // --- MARKETING ---
                          Column(
                            children: [
                              const SizedBox(height: 16),
                              Theme(
                                data: Theme.of(context).copyWith(
                                  segmentedButtonTheme:
                                      SegmentedButtonThemeData(
                                    style: ButtonStyle(
                                      backgroundColor: MaterialStateProperty
                                          .resolveWith<Color?>(
                                        (states) => states.contains(
                                                MaterialState.selected)
                                            ? Colors.green
                                            : Colors.white,
                                      ),
                                      foregroundColor: MaterialStateProperty
                                          .resolveWith<Color?>(
                                        (states) => states.contains(
                                                MaterialState.selected)
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                                child: SegmentedButton<MarketingViewType>(
                                  segments: [
                                    ButtonSegment(
                                      value: MarketingViewType.promotions,
                                      label: Text('Promotions',
                                          style: TextStyle(
                                              fontSize:
                                                  SizeConfig.textMultiplier *
                                                      1.5,
                                              fontWeight: FontWeight.bold)),
                                      icon: Icon(Icons.campaign_outlined,
                                          size:
                                              SizeConfig.textMultiplier * 1.5),
                                    ),
                                    ButtonSegment(
                                      value: MarketingViewType.templates,
                                      label: Text('Templates',
                                          style: TextStyle(
                                              fontSize:
                                                  SizeConfig.textMultiplier *
                                                      1.5,
                                              fontWeight: FontWeight.bold)),
                                      icon: Icon(Icons.library_books_outlined,
                                          size:
                                              SizeConfig.textMultiplier * 1.5),
                                    ),
                                  ],
                                  selected: {_selectedMarketingView},
                                  onSelectionChanged: (val) {
                                    setState(() {
                                      _selectedMarketingView = val.first;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: _selectedMarketingView ==
                                        MarketingViewType.promotions
                                    ? const PromotionsTab()
                                    : const TemplatesTab(),
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

  Widget? _buildFAB(SalesViewModel salesVM, PromotionsViewModel promoVM) {
    if (_mainController.index == 0) {
      return _selectedSalesView == SalesViewType.cash
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AddSale(salesViewModel: salesVM),
                  ),
                );
              },
              icon: const Icon(Icons.add_outlined, color: Colors.white),
              label:
                  const Text('Add Sale', style: TextStyle(color: Colors.white)),
            )
          : null;
    } else {
      return _selectedMarketingView == MarketingViewType.promotions
          ? FloatingActionButton.extended(
              onPressed: () {
                final hasApproved = promoVM.templates.any((t) =>
                    (t['channels']?['whatsapp']?['approved'] == true) ||
                    (t['channels']?['sms']?['approved'] == true));
                if (!hasApproved) {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('No Approved Templates'),
                      content: const Text(
                          'You need at least one approved template before you can run a promotion.'),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            setState(() => _selectedMarketingView =
                                MarketingViewType.templates);
                          },
                          child: const Text('Go to Templates'),
                        ),
                      ],
                    ),
                  );
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RunPromotionPage(),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.campaign_outlined, color: Colors.white),
              label: const Text('Run Promotion',
                  style: TextStyle(color: Colors.white)),
            )
          : FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CreateTemplatePage(viewModel: promoVM),
                  ),
                );
              },
              icon:
                  const Icon(Icons.library_books_outlined, color: Colors.white),
              label: const Text('Create Template',
                  style: TextStyle(color: Colors.white)),
            );
    }
  }
}
