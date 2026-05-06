// All existing imports stay
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/sales/widgets/add_sale.dart';
import 'package:pasella/pages/sales/widgets/date_filter_bar.dart';
import 'package:pasella/pages/sales/widgets/sales_list.dart';
import 'package:pasella/pages/sales/widgets/sales_page_header.dart';
import 'package:pasella/pages/sales/widgets/online_sales_list.dart';
import 'package:pasella/pages/sales/widgets/sales_stats_card.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/telemetry_service.dart';
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

  late final SalesViewModel _salesVM;
  late final PromotionsViewModel _promoVM;

  SalesViewType _selectedSalesView = SalesViewType.cash;
  MarketingViewType _selectedMarketingView = MarketingViewType.promotions;

  @override
  void initState() {
    super.initState();
    _mainController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });

    _salesVM = SalesViewModel(); // construct once
    _promoVM = PromotionsViewModel(); // construct once
    // Kick off promo loading once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promoVM.loadInitialData();
      // Ensure cash list has fresh data immediately on first show
      _salesVM.updateSelectedDate(_selectedDay ?? DateTime.now());
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _promoVM.dispose();
    _salesVM.dispose();
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

  // Replace your helper with this:
  double _scrollBottomPadding(BuildContext context) {
    final m = MediaQuery.of(context);

    // Which FABs are visible?
    final onSalesTab = _mainController.index == 0;
    final onMarketingTab = _mainController.index == 1;

    final cashFabVisible =
        onSalesTab && _selectedSalesView == SalesViewType.cash;
    final marketingFabVisible =
        onMarketingTab; // both Marketing views show an extended FAB in your code

    final fabVisible = cashFabVisible || marketingFabVisible;

    // Material defaults: 56 for normal FAB (yours on Sales), ~48–56 for extended.
    final fabHeight = fabVisible ? 56.0 : 0.0;
    const fabMargin = 16.0;

    return m.padding.bottom + fabHeight + fabMargin;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _salesVM),
        ChangeNotifierProvider.value(value: _promoVM),
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
                              SizedBox(height: SizeConfig.heightMultiplier * 2),
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
                                    if (_selectedSalesView ==
                                        SalesViewType.cash) {
                                      // refresh using current date/range selection
                                      if (_selectedDay != null) {
                                        _salesVM
                                            .updateSelectedDate(_selectedDay!);
                                      } else if (_startDate != null &&
                                          _endDate != null) {
                                        _salesVM.updateSelectedDateRange(
                                            _startDate!, _endDate!);
                                      } else {
                                        _salesVM
                                            .updateSelectedDate(DateTime.now());
                                      }
                                    }
                                  },
                                ),
                              ),

                              DateFilterBar(
                                selectedDay: _selectedDay,
                                startDate: _startDate,
                                endDate: _endDate,
                                onDaySelect: (d) {
                                  _onDateSelected(d);
                                  if (_selectedSalesView ==
                                      SalesViewType.cash) {
                                    salesVM.updateSelectedDate(d);
                                  }
                                },
                                onRangeSelect: (s, e) {
                                  _onDateRangeSelected(s, e);
                                  if (_selectedSalesView ==
                                      SalesViewType.cash) {
                                    salesVM.updateSelectedDateRange(s, e);
                                  }
                                },
                              ),

                              // CASH-ONLY stats card: also loose flex
                              if (_selectedSalesView == SalesViewType.cash) ...[
                                SalesStatsCard(
                                  viewModel: salesVM,
                                  selectedDay: _selectedDay,
                                  startDate: _startDate,
                                  endDate: _endDate,
                                ),
                              ],

                              SizedBox(
                                  height: SizeConfig.heightMultiplier * 1.0),

                              Expanded(
                                child: _selectedSalesView == SalesViewType.cash
                                    ? SafeArea(
                                        top: false,
                                        left: false,
                                        right: false,
                                        bottom: true,
                                        child: SalesList(
                                          viewModel: salesVM,
                                        ),
                                      )
                                    : SafeArea(
                                        top: false,
                                        left: false,
                                        right: false,
                                        bottom: true,
                                        child: OnlineSalesList(
                                          key: ValueKey<String>(
                                            '${_selectedDay?.toIso8601String() ?? ''}|'
                                            '${_startDate?.toIso8601String() ?? ''}|'
                                            '${_endDate?.toIso8601String() ?? ''}',
                                          ),
                                          selectedDay: _selectedDay,
                                          startDate: _startDate,
                                          endDate: _endDate,
                                          // If Online list scrolls, add a similar bottom padding prop there too.
                                        )),
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
                                    if (_selectedMarketingView ==
                                        MarketingViewType.promotions) {
                                      promoVM.fetchPromotionsReports();
                                    } else {
                                      promoVM.loadTemplatesData();
                                    }
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
                TelemetryService.instance
                    .capture(const SaleStarted(entryPoint: 'fab'));
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
              onPressed: () async {
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
                            promoVM.loadTemplatesData();
                          },
                          child: const Text('Go to Templates'),
                        ),
                      ],
                    ),
                  );
                } else {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RunPromotionPage(),
                    ),
                  );
                  if (!mounted) return;
                  await promoVM.fetchPromotionsReports();
                }
              },
              icon: const Icon(Icons.campaign_outlined, color: Colors.white),
              label: const Text('Run Promotion',
                  style: TextStyle(color: Colors.white)),
            )
          : FloatingActionButton.extended(
              onPressed: () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CreateTemplatePage(viewModel: promoVM),
                  ),
                );
                if (!mounted) return;
                if (result == true) {
                  await promoVM.loadTemplatesData();
                }
              },
              icon:
                  const Icon(Icons.library_books_outlined, color: Colors.white),
              label: const Text('Create Template',
                  style: TextStyle(color: Colors.white)),
            );
    }
  }
}
