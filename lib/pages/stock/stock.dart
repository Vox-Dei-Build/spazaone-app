import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/stock/product_group_page/widgets/product_list.dart';
import 'package:pasella/pages/stock/product_report/product_report.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';
import 'package:pasella/shared/widgets/page_header.dart';
import 'package:pasella/pages/stock/search/global_search.dart';
import 'package:pasella/pages/stock/new_product_page/new_product_page.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:provider/provider.dart';

class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  _StockPageState createState() => _StockPageState();
}

class _StockPageState extends State<StockPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ValueNotifier<int> _tabIndexNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
                      PageHeader(
                          onSearchTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const GlobalSearchPage(),
                              ),
                            );
                          },
                          actionWidget: Expanded(
                            child: IconButton(
                              icon: Icon(
                                Icons.help_outline,
                                color: Colors.black,
                                size: SizeConfig.imageSizeMultiplier * 5,
                              ),
                              onPressed: () {
                                final url = TutorialConfig.getTutorialUrl(
                                    TutorialConfig.TUTORIAL_CAPTURE_STOCK);
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => LoomVideoPage(
                                      loomUrl: url,
                                      title: 'How to Capture Stock',
                                    ),
                                  ),
                                );
                              },
                            ),
                          )),
                      SizedBox(height: SizeConfig.heightMultiplier * 2),
                      TabBar(
                        controller: _tabController,
                        labelStyle: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 1.8,
                          fontWeight: FontWeight.normal,
                        ),
                        unselectedLabelStyle: TextStyle(
                          fontSize: SizeConfig.textMultiplier *
                              1.8, // Font size for unselected tabs
                          fontWeight: FontWeight
                              .normal, // Font weight for unselected tabs
                        ),
                        tabs: const [
                          Tab(text: 'PRODUCTS'),
                          Tab(text: 'REPORT'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            ProductList(
                              viewModel: viewModel,
                              groupName:
                                  null, // Set groupname to null so that all products show up
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
    return tabIndex == 0
        ? FloatingActionButton.extended(
            elevation: 3.0,
            onPressed: () {
              Navigator.of(context)
                  .push(
                MaterialPageRoute(
                  builder: (context) => const NewProductPage(),
                ),
              )
                  .then((_) {
                // snap back to “Product Page” tab when you pop
                _tabController.animateTo(0);
              });
            },
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
