import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotion_tab_item.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotions_tab.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/run_promotion_page.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/create_template.dart';
import 'package:pasella/pages/promote/widgets/promotions_page_header.dart';
import 'package:pasella/pages/promote/widgets/templates/templates_tab.dart';
import 'package:provider/provider.dart';

class PromotionsPage extends StatefulWidget {
  const PromotionsPage({Key? key}) : super(key: key);

  static const id = '/promotionsPage';

  @override
  _PromotionsPageState createState() => _PromotionsPageState();
}

class _PromotionsPageState extends State<PromotionsPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final List<TabItem> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      TabItem(
        title: 'Promotions',
        content: const PromotionsTab(),
        fabLabel: 'Run Promotion',
        fabIcon: Icons.campaign_outlined,
        onTap: (ctx, vm) async {
          await Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: vm..loadInitialData(),
              child: const RunPromotionPage(),
            ),
          ));
          _tabController.animateTo(0);
        },
      ),
      TabItem(
        title: 'Templates',
        content: const TemplatesTab(),
        fabLabel: 'Create Template',
        fabIcon: Icons.library_books_outlined,
        onTap: (ctx, vm) async {
          await Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => CreateTemplatePage(viewModel: vm),
          ));
          _tabController.animateTo(1);
        },
      ),
    ];

    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        setState(() {});
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return ChangeNotifierProvider(
      create: (_) {
        final vm = PromotionsViewModel();
        vm.loadInitialData(); // load everything once
        return vm;
      },
      child: Consumer<PromotionsViewModel>(
        builder: (context, viewModel, _) {
          final current = _tabs[_tabController.index];
          return Scaffold(
            floatingActionButton:
                _buildFloatingActionButton(viewModel, current),
            body: SafeArea(
              child: Padding(
                padding: LayoutConstants.padding10Horizontal,
                child: Column(
                  children: [
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    const PromotionsPageHeader(),
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    TabBar(
                      controller: _tabController,
                      labelStyle: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.8,
                        fontWeight: FontWeight.normal,
                      ),
                      unselectedLabelStyle: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.8,
                        fontWeight: FontWeight.normal,
                      ),
                      tabs: const [
                        Tab(text: 'Promotions'),
                        Tab(text: 'Templates'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: const [
                          PromotionsTab(),
                          TemplatesTab(),
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

  Widget? _buildFloatingActionButton(
      PromotionsViewModel viewModel, TabItem current) {
    return _buildFAB(
      label: current.fabLabel,
      icon: current.fabIcon,
      onPressed: () => current.onTap(context, viewModel),
    );
  }

  Widget _buildFAB({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: SizeConfig.heightMultiplier * 1,
        right: SizeConfig.imageSizeMultiplier * 1,
      ),
      child: SizedBox(
        height: SizeConfig.heightMultiplier * 7,
        child: FloatingActionButton.extended(
          elevation: 3.0,
          onPressed: onPressed,
          icon: Icon(
            icon,
            color: Colors.white,
            size: SizeConfig.heightMultiplier * 2.5,
          ),
          label: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: SizeConfig.textMultiplier * 2,
            ),
          ),
        ),
      ),
    );
  }
}
