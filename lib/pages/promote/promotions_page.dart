import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotions_tab.dart';
import 'package:pasella/pages/promote/widgets/promotions/steps/run_promotion_page.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/create_template.dart';
import 'package:pasella/pages/promote/widgets/promotions_page_header.dart';
import 'package:pasella/pages/promote/widgets/templates/templates_tab.dart';
import 'package:pasella/pages/settings/coming_soon/coming_soon_tab.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
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
      create: (_) => PromotionsViewModel(),
      child: Consumer<PromotionsViewModel>(
        builder: (context, viewModel, _) {
          return Scaffold(
            floatingActionButton: _buildFloatingActionButton(viewModel),
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
                        Tab(text: 'Reports'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: const [
                          PromotionsTab(),
                          TemplatesTab(),
                          ComingSoonTab(),
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

  Widget? _buildFloatingActionButton(PromotionsViewModel viewModel) {
    switch (_tabController.index) {
      case 0:
        return _buildFAB(
          label: 'Run Promotion',
          icon: Icons.campaign_outlined,
          onPressed: () {
            Navigator.of(context)
                .push(
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider(
                  create: (_) => PromotionsViewModel()
                    ..fetchTemplates()
                    ..fetchMessageShopName()
                    ..initializePricing()
                    ..fetchCustomers(),
                  child: const RunPromotionPage(),
                ),
              ),
            )
                .then((_) {
              // snap back to “Promotions” tab when you pop
              _tabController.animateTo(0);
            });
          },
        );
      case 1:
        return _buildFAB(
          label: 'Create Template',
          icon: Icons.library_books_outlined,
          onPressed: () {
            Navigator.of(context)
                .push(
              MaterialPageRoute(
                builder: (context) => CreateTemplatePage(
                  viewModel: viewModel,
                ),
              ),
            )
                .then((_) {
              // snap back to Templates tab when you pop
              _tabController.animateTo(1);
            });
          },
        );

      default:
        return null;
    }
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
