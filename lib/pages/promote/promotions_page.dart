import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/promote_intent_bus.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotion_tab_item.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotions_tab.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/run_promotion_page.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/create_template.dart';
import 'package:pasella/pages/promote/widgets/promotions_page_header.dart';
import 'package:pasella/pages/promote/widgets/templates/templates_tab.dart';
import 'package:pasella/pages/promote/widgets/templates/view_template/template_detail_page.dart';
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
  int _previousTabIndex = 0;

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
            builder: (_) => const RunPromotionPage(),
          ));
          _tabController.animateTo(0);
          if (!mounted) return;
          await vm.fetchPromotionsReports();
        },
      ),
      TabItem(
        title: 'Templates',
        content: const TemplatesTab(),
        fabLabel: 'Create Template',
        fabIcon: Icons.library_books_outlined,
        onTap: (ctx, vm) async {
          final result = await Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => CreateTemplatePage(viewModel: vm),
          ));
          _tabController.animateTo(1);
          if (result == true) {
            if (!mounted) return;
            // Success / "what happens next" UX is now handled inside the
            // create flow via TemplateSubmittedSuccessPage. We only need to
            // refresh the list here.
            await vm.loadTemplatesData();
          }
        },
      ),
    ];

    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(_onTabChanged);

    // initial load for tab 0
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PromotionsViewModel>().loadInitialData().then((_) {
        if (mounted) _handlePendingIntent();
      });
    });
  }

  /// Reacts to a deep-link intent stashed by the FCM handler. Called once
  /// after the first templates load so we can resolve the templateId.
  Future<void> _handlePendingIntent() async {
    final intent = PromoteIntentBus.instance.consume();
    if (intent == null || !mounted) return;

    // Switch to the requested tab first so the UI is on-screen by the time
    // any follow-up navigation happens.
    final wantsTemplates = intent.tab == 'templates';
    _tabController.animateTo(wantsTemplates ? 1 : 0);

    final vm = context.read<PromotionsViewModel>();

    // Open a specific template's detail page if requested.
    if (intent.templateId != null) {
      final template = vm.templates.firstWhere(
        (t) => t['id'] == intent.templateId,
        orElse: () => <String, dynamic>{},
      );
      if (template.isNotEmpty && mounted) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TemplateDetailPage(
            viewModel: vm,
            template: template,
            shopName: vm.shopName,
            whatsappPrice: vm.whatsappPrice,
            smsPricePerSegment: vm.smsPricePerSegment,
          ),
        ));
        return;
      }
    }

    // Auto-trigger the Run Promotion flow if requested (and viable).
    if (intent.action == 'run' && !wantsTemplates && mounted) {
      final hasApproved = vm.templates.any((t) =>
          (t['channels']?['whatsapp']?['approvalStatus'] == 'approved') ||
          (t['channels']?['whatsapp']?['approved'] == true));
      if (hasApproved) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const RunPromotionPage(),
        ));
        if (mounted) await vm.fetchPromotionsReports();
      }
    }
  }

  void _onTabChanged() {
    // only fire once per real tab switch
    if (!_tabController.indexIsChanging &&
        _tabController.index != _previousTabIndex) {
      final vm = context.read<PromotionsViewModel>();

      if (_tabController.index == 0) {
        // Promotions tab
        vm.loadInitialData();
      } else {
        // Templates tab
        vm.loadTemplatesData();
      }

      _previousTabIndex = _tabController.index;
    }

    // update FAB, UI, etc.
    setState(() {});
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return ChangeNotifierProvider<PromotionsViewModel>(
      create: (context) {
        final vm = PromotionsViewModel();
        // Defer to after first frame so notifyListeners() isn't called during build:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          vm.loadInitialData();
        });
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
                      ),
                      unselectedLabelStyle: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.8,
                      ),
                      tabs: _tabs
                          .map((t) => Tab(text: t.title))
                          .toList(growable: false),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: _tabs.map((t) => t.content).toList(),
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

  Widget _buildFloatingActionButton(
    PromotionsViewModel vm,
    TabItem current,
  ) {
    final onPromotionsTab = current.title == 'Promotions';
    final hasApproved = vm.templates.any((t) =>
        (t['channels']?['whatsapp']?['approvalStatus'] == 'approved') ||
        (t['channels']?['sms']?['approved'] == true));

    return FloatingActionButton.extended(
      onPressed: () {
        if (onPromotionsTab && !hasApproved) {
          // Show dialog instead of running
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('No Approved Templates'),
              content: const Text(
                  'You need at least one approved template before you can run a promotion. '
                  'Head over to the Templates tab to create and approve one.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    // switch to Templates tab
                    _tabController.animateTo(1);
                  },
                  child: const Text('Go to Templates'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
        } else {
          // Normal behavior
          current.onTap(context, vm);
        }
      },
      icon: Icon(
        current.fabIcon,
        size: SizeConfig.heightMultiplier * 2.5,
        color: Colors.white,
      ),
      label: Text(
        current.fabLabel,
        style: TextStyle(
          fontSize: SizeConfig.textMultiplier * 2,
          color: Colors.white,
        ),
      ),
      elevation: 3,
    );
  }
}
