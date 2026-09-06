// Local visual review using production widgets and example data only.
// flutter run -d web-server -t tool/workspace_design_preview.dart
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/models/stock/whatsapp_catalog_status.dart';
import 'package:pasella/pages/stock/widgets/whatsapp_catalog_status_card.dart';
import 'package:pasella/services/whatsapp_catalog_status_service.dart';
import 'package:pasella/pages/dashboard/dashboard.dart';
import 'package:pasella/pages/reports/business_report/widgets/customer_activity_timeline.dart';
import 'package:pasella/pages/reports/business_report/widgets/date_range_movement_summary_card.dart';
import 'package:pasella/pages/sales/widgets/sales_list.dart';
import 'package:pasella/pages/sales/widgets/sales_stats_card.dart';
import 'package:pasella/pages/stock/product_group_page/widgets/product_list.dart';
import 'package:pasella/pages/stock/stock.dart';
import 'package:pasella/shared/widgets/page_header.dart';
import 'package:pasella/shared/widgets/primary_workspace_header.dart';
import 'package:pasella/shared/widgets/workspace_date_filter.dart';
import 'package:pasella/shared/widgets/workspace_section_tabs.dart';

void main() => runApp(const WorkspaceDesignPreview());

class WorkspaceDesignPreview extends StatelessWidget {
  const WorkspaceDesignPreview({super.key, this.initialPage = 0});
  final int initialPage;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth > 600 ? 420.0 : constraints.maxWidth;
          return ColoredBox(
            color: const Color(0xFFE8ECEA),
            child: Center(
              child: SizedBox(
                width: width,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(width, constraints.maxHeight),
                  ),
                  child: MaterialApp(
                    title: 'Spaza One · Design preview',
                    debugShowCheckedModeBanner: false,
                    theme: kCustomThemeData,
                    home: WorkspacePreviewPage(initialPage: initialPage),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

class WorkspacePreviewPage extends StatefulWidget {
  const WorkspacePreviewPage(
      {super.key,
      this.initialPage = 0,
      this.showPreviewLabel = true,
      this.onSettingsTap,
      this.onFormTap,
      this.onPageChanged});
  final int initialPage;
  final bool showPreviewLabel;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onFormTap;
  final ValueChanged<int>? onPageChanged;

  @override
  State<WorkspacePreviewPage> createState() => _WorkspacePreviewPageState();
}

class _WorkspacePreviewPageState extends State<WorkspacePreviewPage> {
  late int _page = widget.initialPage;
  final _today = DateTime(2026, 9, 4);
  DateTime? _selectedDay;
  DateTime? _start;
  DateTime? _end;
  late final _PreviewCatalogController _catalog = _PreviewCatalogController(
    onRefresh: () => _notice('Catalogue status checked'),
  );

  final _products = <Product>[
    Product(
        id: 'maize',
        name: 'Maize meal · 2.5 kg',
        group: 'Pantry',
        sellingPrice: 39.90,
        quantity: 24,
        whatsappListed: true),
    Product(
        id: 'milk',
        name: 'Full cream milk · 1 L',
        group: 'Dairy',
        sellingPrice: 18.50,
        quantity: 3,
        whatsappListed: true),
    Product(
        id: 'bread',
        name: 'Brown bread · 700 g',
        group: 'Bakery',
        sellingPrice: 16,
        quantity: 0,
        whatsappListed: true),
    Product(
        id: 'sugar',
        name: 'White sugar · 1 kg',
        group: 'Pantry',
        sellingPrice: 28.90,
        quantity: 18),
    Product(
        id: 'oil',
        name: 'Sunflower oil · 750 ml',
        group: 'Pantry',
        sellingPrice: 32.50,
        quantity: 8),
  ];

  @override
  void initState() {
    super.initState();
    _selectedDay = _today;
  }

  @override
  void dispose() {
    _catalog.dispose();
    super.dispose();
  }

  void _notice(String action) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$action · Example data preview'),
    ));
  }

  Widget get _dateFilter => WorkspaceDateFilter(
        selectedDay: _selectedDay,
        startDate: _start,
        endDate: _end,
        onDaySelect: (day) => setState(() {
          _selectedDay = day;
          _start = _end = null;
        }),
        onRangeSelect: (start, end) => setState(() {
          _selectedDay = null;
          _start = start;
          _end = end;
        }),
        onClear: () => setState(() {
          _selectedDay = _start = _end = null;
        }),
      );

  bool _includes(DateTime date) {
    if (_selectedDay != null) return DateUtils.isSameDay(date, _selectedDay);
    if (_start != null && _end != null) {
      return !date.isBefore(DateUtils.dateOnly(_start!)) &&
          date.isBefore(DateUtils.dateOnly(_end!).add(const Duration(days: 1)));
    }
    return true;
  }

  List<CustomerActivityEntry> get _activity => [
        CustomerActivityEntry(
            id: '1',
            customerId: 'naledi',
            customerName: 'Naledi Mokoena',
            type: 'Payment',
            amount: 150,
            when: _today.add(const Duration(hours: 14, minutes: 32))),
        CustomerActivityEntry(
            id: '2',
            customerId: 'sipho',
            customerName: 'Sipho Dlamini',
            type: 'Credit',
            amount: 85,
            when: _today.add(const Duration(hours: 12, minutes: 10))),
        CustomerActivityEntry(
            id: '3',
            customerId: 'thandi',
            customerName: 'Thandi Nkosi',
            type: 'Payment',
            amount: 220,
            when: _today.add(const Duration(hours: 10, minutes: 45))),
        CustomerActivityEntry(
            id: '4',
            customerId: 'naledi',
            customerName: 'Naledi Mokoena',
            type: 'Credit',
            amount: 120,
            when: _today.add(const Duration(hours: 9, minutes: 15))),
      ].where((entry) => _includes(entry.when!)).toList();

  List<Sale> get _sales => [
        Sale(
            id: '1',
            amount: 850,
            stockAmount: 320,
            type: 'Cash',
            products: {},
            dateAdded: _today.add(const Duration(hours: 15, minutes: 30))),
        Sale(
            id: '2',
            amount: 620,
            stockAmount: 0,
            type: 'Cash',
            products: {},
            dateAdded: _today.add(const Duration(hours: 12, minutes: 45))),
        Sale(
            id: '3',
            amount: 980,
            stockAmount: 580,
            type: 'Cash',
            products: {},
            dateAdded: _today.add(const Duration(hours: 9, minutes: 10))),
      ].where((sale) => _includes(sale.dateAdded)).toList();

  Widget _body() {
    if (_page == 1) {
      return Column(children: [
        ProductWorkspaceToolbar(
          onTap: () => _notice('Search products'),
          onAddProduct: () => _notice('Add product'),
        ),
        Expanded(
            child: ProductCatalogueView(
          products: _products,
          header: WhatsAppCatalogStatusCard(controller: _catalog),
          catalogSnapshot: _catalog.snapshot,
          onCatalogAction: (product) => _notice('Review ${product.name}'),
          onOpenProduct: (product) => _notice(product.name!),
        )),
      ]);
    }
    if (_page == 2) {
      final sales = _sales;
      return ListView(padding: const EdgeInsets.only(top: 6), children: [
        _dateFilter,
        SalesSummaryCard(
          sales: sales.fold<double>(0, (total, sale) => total + sale.amount),
          stockAmount:
              sales.fold<double>(0, (total, sale) => total + sale.stockAmount),
          cost: 0,
          profit: 0,
          entryCount: sales.length,
          selectedDay: _selectedDay,
          startDate: _start,
          endDate: _end,
          onRecordSale: widget.onFormTap ?? () => _notice('Record sale'),
        ),
        const Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text('Entries',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kTertiaryColor))),
        for (final sale in sales)
          RecordedSaleTile(sale: sale, onTap: () => _notice('Sale details')),
        if (sales.isEmpty) const SalesListEmptyState(),
      ]);
    }
    final entries = _activity;
    final credits = entries.where((entry) => entry.type == 'Credit').toList();
    final payments = entries.where((entry) => entry.type == 'Payment').toList();
    final net =
        entries.fold<double>(0, (total, entry) => total + entry.movement);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _dateFilter,
        const SizedBox(height: 12),
        CustomerActivitySummary(
          netMovement: net,
          salesAmount:
              credits.fold<double>(0, (total, entry) => total + entry.amount),
          salesCount: credits.length,
          paymentsAmount:
              payments.fold<double>(0, (total, entry) => total + entry.amount),
          paymentsCount: payments.length,
        ),
        CustomerActivityTimeline(
            entries: entries,
            reportedNet: net,
            onOpenCustomer: (entry) => _notice('${entry.customerName} ledger')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final labels = _page == 0
        ? ['Customers', 'Activity', 'Overview']
        : _page == 1
            ? ['Products', 'Suppliers', 'Stock']
            : ['Recorded', 'Online', 'Marketing'];
    return ResponsiveDashboardShell(
      selectedIndex: _page,
      onDestinationSelected: (page) {
        setState(() => _page = page);
        widget.onPageChanged?.call(page);
      },
      body: SafeArea(
          child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(children: [
          if (widget.showPreviewLabel)
            const Text('DESIGN PREVIEW · EXAMPLE DATA',
                style: TextStyle(
                    fontSize: 10, letterSpacing: 1.2, color: kSecondaryAccent)),
          const SizedBox(height: 8),
          PageHeader(
              walletWidget: const SizedBox.shrink(),
              connectivityWidget: const SizedBox.shrink(),
              onSettingsTap: widget.onSettingsTap ?? () => _notice('Settings')),
          const SizedBox(height: 8),
          WorkspaceHeaderBar(
              storeName: 'Neighbourhood Store',
              onStorePressed: () => _notice('Your shop'),
              onShopPressed: () => _notice('Shop')),
          const SizedBox(height: 8),
          DefaultTabController(
              key: ValueKey(_page),
              length: 3,
              initialIndex: _page == 0 ? 1 : 0,
              child: WorkspaceSectionTabs(
                tabs: [
                  for (final label in labels)
                    WorkspaceSectionTab(label: label, semanticLabel: label)
                ],
                onSelected: (_) =>
                    _notice('Preview focuses on the redesigned tab'),
              )),
          Expanded(child: _body()),
        ]),
      )),
    );
  }
}

/// Data-only controller: this preview never constructs Firebase services or a
/// store session, and actions only display a local-preview notice.
class _PreviewCatalogController extends ChangeNotifier
    implements WhatsAppCatalogStatusController {
  _PreviewCatalogController({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  WhatsAppCatalogSnapshot? snapshot = WhatsAppCatalogSnapshot.fromMap({
    'schemaVersion': 2,
    'checkedAtMs': DateTime(2026, 9, 4, 10, 40).millisecondsSinceEpoch,
    'freshUntilMs': DateTime(2026, 9, 4, 10, 45).millisecondsSinceEpoch,
    'rollout': 'enabled',
    'summary': {
      'totalProducts': 5,
      'eligible': 3,
      'live': 1,
      'syncing': 1,
      'needsAttention': 1,
      'removalSyncing': 0,
      'supportReview': 0,
      'canBrowseFive': false,
      'canBrowseTen': false,
    },
    'products': [
      {'productId': 'maize', 'status': 'live', 'action': 'none'},
      {'productId': 'milk', 'status': 'syncing', 'action': 'refresh'},
      {
        'productId': 'bread',
        'status': 'needs_attention',
        'action': 'edit_product'
      },
    ],
    'catalogVersion': 'local-preview',
  });

  @override
  bool get enabled => true;
  @override
  bool get isStale => false;
  @override
  bool get canManualRefresh => true;
  @override
  bool get loading => false;
  @override
  String? get errorMessage => null;
  @override
  Future<void> manualRefresh() async => onRefresh();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
