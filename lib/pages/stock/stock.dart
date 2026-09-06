import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/stock/product_group_page/widgets/product_list.dart';
import 'package:pasella/pages/stock/product_report/product_report.dart';
import 'package:pasella/shared/widgets/primary_workspace_header.dart';
import 'package:pasella/shared/widgets/workspace_section_tabs.dart';
import 'package:pasella/shared/widgets/workspace_search_field.dart';
import 'package:pasella/pages/stock/search/global_search.dart';
import 'package:pasella/pages/stock/new_product_page/new_product_page.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/pages/stock/dropship/supplier_catalog_page.dart';
import 'package:provider/provider.dart';
import 'package:pasella/services/whatsapp_catalog_status_service.dart';
import 'package:pasella/pages/stock/widgets/whatsapp_catalog_status_card.dart';

class StockPage extends StatelessWidget {
  const StockPage({super.key, this.initialTab = 0});

  static const id = '/stockPage';
  static const legacyCommerceOrdersId = '/commerceOrders';
  final int initialTab;

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => StockViewModel()..watchProducts(),
          ),
          ChangeNotifierProvider(
            create: (_) => WhatsAppCatalogStatusController()..start(),
          ),
        ],
        child: StockPageContent(initialTab: initialTab),
      );
}

/// The workspace lives below its owned providers. Presentation overrides let
/// route and lifecycle tests exercise the real Add action without cloud IO.
class StockPageContent extends StatefulWidget {
  const StockPageContent({
    super.key,
    this.initialTab = 0,
    this.header,
    this.supplierCatalog,
    this.newProductBuilder,
  });

  final int initialTab;
  final Widget? header;
  final Widget? supplierCatalog;
  final WidgetBuilder? newProductBuilder;

  @override
  State<StockPageContent> createState() => _StockPageContentState();
}

class _StockPageContentState extends State<StockPageContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ValueNotifier<int> _tabIndexNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    final initialTab =
        widget.initialTab >= 0 && widget.initialTab < 3 ? widget.initialTab : 0;
    _tabController = TabController(
      length: 3,
      initialIndex: initialTab,
      vsync: this,
    );
    _tabIndexNotifier.value = initialTab;
    _tabController.addListener(() {
      _tabIndexNotifier.value = _tabController.index;
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
    return Consumer2<StockViewModel, WhatsAppCatalogStatusController>(
      builder: (context, viewModel, catalogStatus, child) {
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: LayoutConstants.workspacePadding,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    widget.header ??
                        const PrimaryWorkspaceHeader(
                          shareSource: 'products_header',
                        ),
                    const SizedBox(height: 8),
                    WorkspaceSectionTabs(
                      controller: _tabController,
                      tabs: const <WorkspaceSectionTab>[
                        WorkspaceSectionTab(
                          label: 'Products',
                          semanticLabel: 'Your products',
                        ),
                        WorkspaceSectionTab(
                          label: 'Suppliers',
                          semanticLabel: 'Supplier catalogue',
                        ),
                        WorkspaceSectionTab(
                          label: 'Stock',
                          semanticLabel: 'Stock report',
                        ),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          Column(
                            children: [
                              ProductWorkspaceToolbar(
                                onAddProduct: () =>
                                    _openNewProduct(catalogStatus),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const GlobalSearchPage(),
                                    ),
                                  );
                                },
                              ),
                              Expanded(
                                child: ProductList(
                                  viewModel: viewModel,
                                  catalogSnapshot: catalogStatus.snapshot,
                                  onCatalogRefresh: catalogStatus.manualRefresh,
                                  onProductChanged: () =>
                                      catalogStatus.refresh(resetPolling: true),
                                  header: WhatsAppCatalogStatusCard(
                                      controller: catalogStatus),
                                  groupName: null,
                                  onAddProduct: () =>
                                      _openNewProduct(catalogStatus),
                                  showEmptyAction: false,
                                ),
                              ),
                            ],
                          ),
                          widget.supplierCatalog ??
                              SupplierCatalogPage(
                                onListingCreated: () {
                                  _tabController.animateTo(0);
                                },
                              ),
                          Column(
                            children: [
                              Expanded(
                                child: ProductReportsTab(viewModel: viewModel),
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
          ),
        );
      },
    );
  }

  /// Capture the controller from the provider's descendant before navigation.
  /// A route return may happen after the whole workspace has been removed.
  Future<void> _openNewProduct(
    WhatsAppCatalogStatusController catalogStatus,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: widget.newProductBuilder ?? (_) => const NewProductPage(),
      ),
    );
    if (!mounted) return;
    _tabController.animateTo(0);
    await catalogStatus.refresh(resetPolling: true);
  }
}

/// Content-first controls for the merchant's own catalogue.
///
/// The active Products tab supplies the title; search and Add share one row.
class ProductWorkspaceToolbar extends StatelessWidget {
  const ProductWorkspaceToolbar({
    super.key,
    required this.onTap,
    required this.onAddProduct,
  });

  final VoidCallback onTap;
  final VoidCallback onAddProduct;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: WorkspaceSearchField(
              key: const ValueKey('search-products-launcher'),
              hintText: 'Search products',
              semanticLabel: 'Open product search',
              readOnly: true,
              onTap: onTap,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: FilledButton.icon(
              key: const ValueKey('add-product-action'),
              onPressed: onAddProduct,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SpazaRadius.control),
                ),
              ),
              icon: const Icon(SpazaIcons.add, size: 20),
              label: const Text('Add'),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomFloatingActionButtonLocation extends FloatingActionButtonLocation {
  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final double fabX = scaffoldGeometry.scaffoldSize.width -
        16.0 -
        scaffoldGeometry.floatingActionButtonSize.width / 2;
    final double fabY = scaffoldGeometry.scaffoldSize.height -
        100.0 -
        scaffoldGeometry.floatingActionButtonSize.height / 2;
    return Offset(fabX, fabY);
  }
}

/// Product-local actions beside the Stock tabs.
///
/// Search is deliberately visible only while the merchant is viewing their
/// own Products tab. Catalogue has its own search field and Report has no
/// search, so neither surface inherits a misleading "global" overflow item.
class StockTabActions extends StatelessWidget {
  const StockTabActions({
    super.key,
    required this.showProductSearch,
    required this.onSearch,
    required this.onHelp,
  });

  final bool showProductSearch;
  final VoidCallback onSearch;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showProductSearch)
          IconButton(
            key: const ValueKey('search-my-products'),
            tooltip: 'Search my products',
            icon: const Icon(
              SpazaIcons.search,
              color: SpazaColors.muted,
              size: 22,
            ),
            onPressed: onSearch,
          ),
        IconButton(
          key: const ValueKey('stock-help'),
          tooltip: 'How to capture stock',
          icon: const Icon(
            SpazaIcons.help,
            color: SpazaColors.muted,
            size: 22,
          ),
          onPressed: onHelp,
        ),
      ],
    );
  }
}
