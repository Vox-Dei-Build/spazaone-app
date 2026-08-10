import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/stock/product_group_page/widgets/product_list.dart';
import 'package:pasella/pages/stock/product_report/product_report.dart';
import 'package:pasella/shared/widgets/contextual_tab_bar.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';
import 'package:pasella/shared/widgets/primary_workspace_header.dart';
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
              floatingActionButton: ValueListenableBuilder<int>(
                valueListenable: _tabIndexNotifier,
                builder: (context, tabIndex, child) {
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: SizeConfig.heightMultiplier * 1,
                      right: SizeConfig.imageSizeMultiplier * 1,
                    ),
                    child: SizedBox(
                      height: SizeConfig.heightMultiplier * 7,
                      child: _buildFloatingActionButton(tabIndex, viewModel),
                    ),
                  );
                },
              ),
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
                      ContextualTabBar(
                        controller: _tabController,
                        labelPadding: EdgeInsets.zero,
                        labelStyle: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 1.45,
                          fontWeight: FontWeight.normal,
                        ),
                        unselectedLabelStyle: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 1.45,
                          fontWeight: FontWeight.normal,
                        ),
                        tabs: const [
                          Tab(text: 'PRODUCTS'),
                          Tab(text: 'CATALOGUE'),
                          Tab(text: 'REPORT'),
                        ],
                        action: ValueListenableBuilder<int>(
                          valueListenable: _tabIndexNotifier,
                          builder: (context, tabIndex, _) => StockTabActions(
                            showProductSearch: tabIndex == 0,
                            onSearch: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const GlobalSearchPage(),
                                ),
                              );
                            },
                            onHelp: _openTutorial,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            ProductList(
                              viewModel: viewModel,
                              groupName:
                                  null, // Set groupname to null so that all products show up
                              // Keep one direct action in the empty state.
                              // Help remains available from the header menu.
                              onAddProduct: () => _openNewProduct(),
                            ),
                            SupplierCatalogPage(
                              onListingCreated: () {
                                _tabController.animateTo(0);
                              },
                            ),
                            ProductReportsTab(viewModel: viewModel),
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

  Widget _buildFloatingActionButton(int tabIndex, StockViewModel viewModel) {
    return tabIndex == 0 && viewModel.products.isNotEmpty
        ? FloatingActionButton.extended(
            elevation: 3.0,
            onPressed: _openNewProduct,
            icon: Icon(
              Icons.add_outlined,
              color: Colors.white,
              size: SizeConfig.heightMultiplier * 2.5, // Smaller icon
            ),
            label: Text(
              'Add Product',
              style: TextStyle(
                color: Colors.white,
                fontSize: SizeConfig.textMultiplier * 2, // Adjust font size
              ),
            ),
          )
        : Container();
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

  /// Launcher for the capture-stock walkthrough in the header menu.
  void _openTutorial() {
    final url = TutorialConfig.getTutorialUrl(
      TutorialConfig.TUTORIAL_CAPTURE_STOCK,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            LoomVideoPage(loomUrl: url, title: 'How to Capture Stock'),
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
