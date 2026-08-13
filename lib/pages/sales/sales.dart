// All existing imports stay
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/sales/widgets/add_sale.dart';
import 'package:pasella/pages/sales/widgets/date_filter_bar.dart';
import 'package:pasella/pages/sales/widgets/sales_list.dart';
import 'package:pasella/pages/sales/widgets/sales_page_header.dart';
import 'package:pasella/pages/sales/widgets/online_commerce_hub.dart';
import 'package:pasella/pages/sales/widgets/marketing_overview.dart';
import 'package:pasella/pages/sales/widgets/sales_stats_card.dart';
import 'package:pasella/shared/widgets/contextual_tab_bar.dart';
import 'package:pasella/shared/widgets/secondary_view_picker.dart';
import 'package:pasella/services/sales_intent_bus.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/utils/feature_flags.dart';
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
    final intentBus = SalesIntentBus.instance;
    final intent = intentBus.take();
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
    intentBus.addListener(_consumePendingIntent);
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

  void _consumePendingIntent() {
    final intent = SalesIntentBus.instance.take();
    if (intent == null || !mounted) return;

    if (_mainController.index != 1) {
      _mainController.animateTo(1);
    }
    _loadMarketing();
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
    SalesIntentBus.instance.removeListener(_consumePendingIntent);
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
                  const SalesPageHeader(),
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  ContextualTabBar(
                    controller: _mainController,
                    labelStyle: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.8,
                    ),
                    tabs: const [
                      Tab(text: 'Sales'),
                      Tab(text: 'Marketing'),
                    ],
                    action: SalesHelpAction(
                      showMarketingHelp: _mainController.index == 1,
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _mainController,
                      children: [
                        // --- SALES ---
                        Column(
                          children: [
                            SizedBox(height: SizeConfig.heightMultiplier * 1),
                            SecondaryViewPicker<SalesViewType>(
                              key: const ValueKey('sales-view-picker'),
                              semanticLabel: 'Sales view',
                              value: _selectedSalesView,
                              options: const [
                                SecondaryViewOption(
                                  value: SalesViewType.cash,
                                  label: 'Cash',
                                  icon: Icons.payments_outlined,
                                ),
                                SecondaryViewOption(
                                  value: SalesViewType.online,
                                  label: 'Online',
                                  icon: Icons.language_rounded,
                                ),
                              ],
                              onSelected: (view) {
                                setState(() {
                                  _selectedSalesView = view;
                                });
                                if (_selectedSalesView == SalesViewType.cash) {
                                  // Refresh using the current date/range.
                                  if (_selectedDay != null) {
                                    _salesVM.updateSelectedDate(_selectedDay!);
                                  } else if (_startDate != null &&
                                      _endDate != null) {
                                    _salesVM.updateSelectedDateRange(
                                      _startDate!,
                                      _endDate!,
                                    );
                                  } else {
                                    _salesVM.updateSelectedDate(DateTime.now());
                                  }
                                }
                              },
                            ),
                            if (_selectedSalesView == SalesViewType.cash) ...[
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
                                onClear: _clearDateFilter,
                              ),
                            ],
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
                                  : FeatureFlags.enableOnlineSales
                                      ? SafeArea(
                                          top: false,
                                          left: false,
                                          right: false,
                                          bottom: true,
                                          child: OnlineCommerceHub(
                                            selectedDay: _selectedDay,
                                            startDate: _startDate,
                                            endDate: _endDate,
                                            onDaySelect: _onDateSelected,
                                            onRangeSelect: _onDateRangeSelected,
                                            onClearDates: _clearDateFilter,
                                          ),
                                        )
                                      : const _OnlineSalesComingSoon(),
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

class _OnlineSalesComingSoon extends StatelessWidget {
  const _OnlineSalesComingSoon();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(LayoutConstants.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.payments_outlined,
                size: 38,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: LayoutConstants.spaceLg),
            const Text(
              'Online selling is currently off',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: LayoutConstants.spaceSm),
            Text(
              'Your existing sales records are unchanged. Spaza One will show '
              'each online capability here when it is enabled and ready for '
              'your store.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
