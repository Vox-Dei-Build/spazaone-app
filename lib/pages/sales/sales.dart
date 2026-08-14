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
import 'package:pasella/shared/widgets/workspace_section_tabs.dart';
import 'package:pasella/services/sales_intent_bus.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:provider/provider.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/pages/promote/utils/run_promotion_launcher.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotions_tab.dart';

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
  DateTime? _onlineSelectedDay = DateTime.now();
  DateTime? _onlineStartDate;
  DateTime? _onlineEndDate;

  late final TabController _mainController;

  late final SalesViewModel _salesVM;
  // PAS-CRASH-_dependents: the PromotionsViewModel is owned by the root
  // MultiProvider in main.dart. Constructing a second instance here and
  // exposing it via ChangeNotifierProvider.value created a page-scoped
  // InheritedElement that could be deactivated while pushed routes /
  // tab descendants still held dependents, tripping the framework's
  // `_dependents.isEmpty` assertion. We now resolve the canonical
  // instance via context.read in build().

  bool _marketingLoaded = false;

  @override
  void initState() {
    super.initState();
    final intentBus = SalesIntentBus.instance;
    final intent = intentBus.take();
    final initialMainIndex = intent == null ? 0 : 2;

    _mainController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialMainIndex,
    )..addListener(() {
        if (!mounted) return;
        setState(() {});
        if (!_mainController.indexIsChanging && _mainController.index == 2) {
          _loadMarketing();
        }
      });

    _salesVM = SalesViewModel();
    intentBus.addListener(_consumePendingIntent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_mainController.index == 2) {
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

    if (_mainController.index != 2) {
      _mainController.animateTo(2);
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

  void _onOnlineDateSelected(DateTime selectedDay) {
    setState(() {
      _onlineSelectedDay = selectedDay;
      _onlineStartDate = null;
      _onlineEndDate = null;
    });
  }

  void _onOnlineDateRangeSelected(DateTime start, DateTime end) {
    setState(() {
      _onlineStartDate = start;
      _onlineEndDate = end;
      _onlineSelectedDay = null;
    });
  }

  void _clearOnlineDateFilter() {
    setState(() {
      _onlineSelectedDay = null;
      _onlineStartDate = null;
      _onlineEndDate = null;
    });
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
                  WorkspaceSectionTabs(
                    controller: _mainController,
                    tabs: const [
                      WorkspaceSectionTab(
                        label: 'Recorded sales',
                        semanticLabel: 'Recorded sales',
                      ),
                      WorkspaceSectionTab(
                        label: 'Online orders',
                        semanticLabel: 'Online orders',
                      ),
                      WorkspaceSectionTab(
                        label: 'Marketing',
                        semanticLabel: 'Marketing',
                      ),
                    ],
                  ),
                  Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            switch (_mainController.index) {
                              0 => 'Sales recorded in SpazaOne',
                              1 => 'Orders placed through your shop',
                              _ => 'Promote products to your customers',
                            },
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                        SalesHelpAction(
                          showMarketingHelp: _mainController.index == 2,
                        ),
                      ],
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
                            DateFilterBar(
                              selectedDay: _selectedDay,
                              startDate: _startDate,
                              endDate: _endDate,
                              onDaySelect: (day) {
                                _onDateSelected(day);
                                salesVM.updateSelectedDate(day);
                              },
                              onRangeSelect: (start, end) {
                                _onDateRangeSelected(start, end);
                                salesVM.updateSelectedDateRange(start, end);
                              },
                              onClear: _clearDateFilter,
                            ),
                            SalesStatsCard(
                              viewModel: salesVM,
                              selectedDay: _selectedDay,
                              startDate: _startDate,
                              endDate: _endDate,
                            ),
                            SizedBox(height: SizeConfig.heightMultiplier * 1.0),
                            Expanded(
                              child: SafeArea(
                                top: false,
                                left: false,
                                right: false,
                                bottom: true,
                                child: SalesList(
                                  viewModel: salesVM,
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
                              ),
                            ),
                          ],
                        ),

                        // --- ONLINE ORDERS ---
                        FeatureFlags.enableOnlineSales
                            ? SafeArea(
                                top: false,
                                left: false,
                                right: false,
                                bottom: true,
                                child: OnlineCommerceHub(
                                  selectedDay: _onlineSelectedDay,
                                  startDate: _onlineStartDate,
                                  endDate: _onlineEndDate,
                                  onDaySelect: _onOnlineDateSelected,
                                  onRangeSelect: _onOnlineDateRangeSelected,
                                  onClearDates: _clearOnlineDateFilter,
                                ),
                              )
                            : const _OnlineSalesComingSoon(),

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
      if (salesVM.cachedSales.isEmpty) {
        return null;
      }
      return FloatingActionButton.extended(
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
      );
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
