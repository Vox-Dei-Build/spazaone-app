import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/stock/product_group_page/widgets/product_list.dart';
import 'package:pasella/pages/stock/product_report/product_report.dart';
import 'package:pasella/shared/widgets/primary_workspace_header.dart';
import 'package:pasella/shared/widgets/workspace_context_header.dart';
import 'package:pasella/shared/widgets/workspace_section_tabs.dart';
import 'package:pasella/pages/stock/search/global_search.dart';
import 'package:pasella/pages/stock/new_product_page/new_product_page.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/pages/stock/dropship/supplier_catalog_page.dart';
import 'package:provider/provider.dart';

class StockPage extends StatefulWidget {
  const StockPage({super.key, this.initialTab = 0});

  static const id = '/stockPage';
  static const legacyCommerceOrdersId = '/commerceOrders';
  final int initialTab;

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage>
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
    return ChangeNotifierProvider(
      create: (_) => StockViewModel()..loadProducts(),
      child: Consumer<StockViewModel>(
        builder: (context, viewModel, child) {
          return DefaultTabController(
            length: 3,
            child: Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: LayoutConstants.padding10Horizontal,
                  child: Column(
                    children: [
                      SizedBox(height: SizeConfig.heightMultiplier * 2),
                      const PrimaryWorkspaceHeader(
                        shareSource: 'products_header',
                      ),
                      SizedBox(height: SizeConfig.heightMultiplier * 2),
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
                                WorkspaceContextHeader(
                                  title: 'Your products',
                                  subtitle: 'Products you stock and sell',
                                  action: FilledButton.icon(
                                    key: const ValueKey('add-product-action'),
                                    onPressed: _openNewProduct,
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Add'),
                                  ),
                                ),
                                _ProductSearchLauncher(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const GlobalSearchPage(),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 6),
                                Expanded(
                                  child: ProductList(
                                    viewModel: viewModel,
                                    groupName: null,
                                    onAddProduct: _openNewProduct,
                                    showEmptyAction: false,
                                  ),
                                ),
                              ],
                            ),
                            SupplierCatalogPage(
                              onListingCreated: () {
                                _tabController.animateTo(0);
                              },
                            ),
                            Column(
                              children: [
                                const WorkspaceContextHeader(
                                  title: 'Stock report',
                                  subtitle: 'What your current stock is worth',
                                ),
                                Expanded(
                                  child:
                                      ProductReportsTab(viewModel: viewModel),
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
      ),
    );
  }

  /// Shared launcher used by the FAB and product empty state.
  void _openNewProduct() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => const NewProductPage()))
        .then((_) {
      // snap back to "Product Page" tab when you pop
      _tabController.animateTo(0);
    });
  }
}

class _ProductSearchLauncher extends StatelessWidget {
  const _ProductSearchLauncher({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: const ValueKey('search-products-launcher'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: const SizedBox(
              height: 48,
              child: Row(
                children: [
                  SizedBox(width: 14),
                  Icon(Icons.search_rounded),
                  SizedBox(width: 12),
                  Expanded(child: Text('Search products')),
                ],
              ),
            ),
          ),
        ),
      );
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
            icon: Icon(
              Icons.search,
              color: Colors.black87,
              size: SizeConfig.imageSizeMultiplier * 5,
            ),
            onPressed: onSearch,
          ),
        IconButton(
          key: const ValueKey('stock-help'),
          tooltip: 'How to capture stock',
          icon: Icon(
            Icons.help_outline,
            color: Colors.black87,
            size: SizeConfig.imageSizeMultiplier * 5,
          ),
          onPressed: onHelp,
        ),
      ],
    );
  }
}
