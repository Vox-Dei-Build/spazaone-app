// All existing imports stay
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/sales/widgets/add_sale.dart';
import 'package:pasella/pages/sales/widgets/date_filter_bar.dart';
import 'package:pasella/pages/sales/widgets/sales_list.dart';
import 'package:pasella/pages/sales/widgets/sales_page_header.dart';
import 'package:pasella/pages/sales/widgets/online_sales_list.dart';
import 'package:pasella/pages/sales/widgets/marketing_overview.dart';
import 'package:pasella/pages/sales/widgets/sales_stats_card.dart';
import 'package:pasella/services/sales_intent_bus.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:provider/provider.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/pages/promote/utils/run_promotion_launcher.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotions_tab.dart';

enum SalesViewType { cash, online }

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
  // PAS-CRASH-_dependents: the PromotionsViewModel is owned by the root
  // MultiProvider in main.dart. Constructing a second instance here and
  // exposing it via ChangeNotifierProvider.value created a page-scoped
  // InheritedElement that could be deactivated while pushed routes /
  // tab descendants still held dependents, tripping the framework's
  // `_dependents.isEmpty` assertion. We now resolve the canonical
  // instance via context.read in build().

  SalesViewType _selectedSalesView = SalesViewType.cash;
  bool _marketingLoaded = false;

  @override
  void initState() {
    super.initState();
    final intent = SalesIntentBus.instance.take();
    final initialMainIndex = intent == null ? 0 : 1;

    _mainController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialMainIndex,
    )..addListener(() {
        if (!mounted) return;
        setState(() {});
        if (!_mainController.indexIsChanging && _mainController.index == 1) {
          _loadMarketing();
        }
      });

    _salesVM = SalesViewModel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_mainController.index == 1) {
        _loadMarketing();
        return;
      }
      // Ensure cash list has fresh data immediately on first show.
      _salesVM.updateSelectedDate(_selectedDay ?? DateTime.now());
    });
  }

  void _loadMarketing() {
    if (_marketingLoaded || !mounted) return;
    _marketingLoaded = true;
    final promoVM = context.read<PromotionsViewModel>();
    promoVM.loadInitialData().then((_) {
      if (!mounted) return null;
      return promoVM.ensureProductPromotionTemplate();
    });
  }

  Future<void> _openProductPromotion(PromotionsViewModel promoVM) async {
    await RunPromotionLauncher.launch(context, viewModel: promoVM);
  }

  @override
  void dispose() {
    _mainController.dispose();
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

  void _clearDateFilter() {
    setState(() {
      _selectedDay = null;
      _startDate = null;
      _endDate = null;
    });
    _salesVM.updateSelectedDateRange(DateTime(2000), DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    // PAS-CRASH-_dependents: the root `PromotionsViewModel` is resolved
    // here via context.watch so this widget rebuilds on promo changes,
    // without introducing a page-scoped InheritedProvider whose
    // lifetime would race with descendant deactivation.
    final promoVM = context.watch<PromotionsViewModel>();
    final salesVM = _salesVM;
    // AnimatedBuilder rebuilds the subtree on _salesVM notifications
    // without an additional InheritedElement.
    return AnimatedBuilder(
      animation: salesVM,
      builder: (context, _) {
        return Scaffold(
          floatingActionButton: _buildFAB(salesVM),
          body: SafeArea(
            child: Padding(
              padding: LayoutConstants.padding10Horizontal,
              child: Column(
                children: [
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  SalesPageHeader(
                    showMarketingHelp: _mainController.index == 1,
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  TabBar(
                    controller: _mainController,
                    labelStyle: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.8,
                    ),
                    tabs: const [Tab(text: 'Sales'), Tab(text: 'Marketing')],
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
                                segmentedButtonTheme: SegmentedButtonThemeData(
                                  style: ButtonStyle(
                                    backgroundColor:
                                        WidgetStateProperty.resolveWith<Color?>(
                                      (states) => states.contains(
                                        WidgetState.selected,
                                      )
                                          ? Colors.green
                                          : Colors.white,
                                    ),
                                    foregroundColor:
                                        WidgetStateProperty.resolveWith<Color?>(
                                      (states) => states.contains(
                                        WidgetState.selected,
                                      )
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
                                    label: Text(
                                      'Cash',
                                      style: TextStyle(
                                        fontSize:
                                            SizeConfig.textMultiplier * 1.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    icon: Icon(
                                      Icons.attach_money,
                                      size: SizeConfig.textMultiplier * 1.5,
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: SalesViewType.online,
                                    label: Text(
                                      'Online',
                                      style: TextStyle(
                                        fontSize:
                                            SizeConfig.textMultiplier * 1.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    icon: Icon(
                                      Icons.wifi,
                                      size: SizeConfig.textMultiplier * 1.5,
                                    ),
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
                                      _salesVM.updateSelectedDate(
                                        _selectedDay!,
                                      );
                                    } else if (_startDate != null &&
                                        _endDate != null) {
                                      _salesVM.updateSelectedDateRange(
                                        _startDate!,
                                        _endDate!,
                                      );
                                    } else {
                                      _salesVM.updateSelectedDate(
                                        DateTime.now(),
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                            if (_selectedSalesView == SalesViewType.cash) ...[
                              const _SalesMeaningHint(),
                              const SizedBox(height: LayoutConstants.spaceMd),
                            ],

                            DateFilterBar(
                              selectedDay: _selectedDay,
                              startDate: _startDate,
                              endDate: _endDate,
                              onDaySelect: (d) {
                                _onDateSelected(d);
                                if (_selectedSalesView == SalesViewType.cash) {
                                  salesVM.updateSelectedDate(d);
                                }
                              },
                              onRangeSelect: (s, e) {
                                _onDateRangeSelected(s, e);
                                if (_selectedSalesView == SalesViewType.cash) {
                                  salesVM.updateSelectedDateRange(s, e);
                                }
                              },
                              onClear: _clearDateFilter,
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

                            SizedBox(height: SizeConfig.heightMultiplier * 1.0),

                            Expanded(
                              child: _selectedSalesView == SalesViewType.cash
                                  ? SafeArea(
                                      top: false,
                                      left: false,
                                      right: false,
                                      bottom: true,
                                      child: SalesList(
                                        viewModel: salesVM,
                                        // PAS-AUTH-03: wire the FAB
                                        // action into the empty-state
                                        // CTA so a new merchant lands
                                        // on a one-tap path to their
                                        // first sale.
                                        onAddSale: () {
                                          TelemetryService.instance.capture(
                                            const SaleStarted(
                                              entryPoint: 'empty_state',
                                            ),
                                          );
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => AddSale(
                                                salesViewModel: salesVM,
                                              ),
                                            ),
                                          );
                                        },
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
                                      ),
                                    ),
                            ),
                          ],
                        ),

                        // --- MARKETING ---
                        MarketingOverview(
                          onChooseProduct: () => _openProductPromotion(promoVM),
                          campaignHistory: const PromotionsTab(),
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
    );
  }

  Widget? _buildFAB(SalesViewModel salesVM) {
    if (_mainController.index == 0) {
      if (_selectedSalesView == SalesViewType.cash &&
          salesVM.cachedSales.isEmpty) {
        return null;
      }
      return _selectedSalesView == SalesViewType.cash
          ? FloatingActionButton.extended(
              heroTag: 'sales-cash-fab',
              onPressed: () {
                TelemetryService.instance.capture(
                  const SaleStarted(entryPoint: 'fab'),
                );
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AddSale(salesViewModel: salesVM),
                  ),
                );
              },
              icon: const Icon(Icons.add_outlined, color: Colors.white),
              label: const Text(
                'Record Sale',
                style: TextStyle(color: Colors.white),
              ),
            )
          : null;
    }
    // Marketing owns a prominent inline product CTA. Keeping a second FAB
    // would create two competing starts for the same simple journey.
    return null;
  }
}

class _SalesMeaningHint extends StatelessWidget {
  const _SalesMeaningHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: LayoutConstants.spaceSm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(LayoutConstants.spaceSm),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 18, color: Colors.green),
            const SizedBox(width: LayoutConstants.spaceSm),
            Expanded(
              child: Text(
                'Record day-end revenue totals here, or capture individual cash sales when stock and profit detail matters.',
                style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.4,
                  height: 1.25,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
