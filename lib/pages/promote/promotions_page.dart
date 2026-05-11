import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/promote_intent_bus.dart';
import 'package:pasella/pages/promote/utils/run_promotion_launcher.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotion_tab_item.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotions_tab.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/create_template.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/template_submitted_success_page.dart';
import 'package:pasella/pages/promote/widgets/promotions_page_header.dart';
import 'package:pasella/pages/promote/widgets/templates/templates_tab.dart';
import 'package:pasella/pages/promote/widgets/templates/view_template/template_detail_page.dart';
import 'package:provider/provider.dart';

class PromotionsPage extends StatefulWidget {
  const PromotionsPage({Key? key}) : super(key: key);

  static const id = '/promotionsPage';

  @override
  State<PromotionsPage> createState() => _PromotionsPageState();
}

class _PromotionsPageState extends State<PromotionsPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  late final List<TabItem> _tabs;
  int _previousTabIndex = 0;

  @override
  void initState() {
    super.initState();

    // PAS-UX-rel: template approval state lives upstream of the app
    // (Twilio + WhatsApp review) and used to only refresh when the
    // user explicitly tab-switched or pulled the list. If a merchant
    // backgrounded the app while waiting on approval and then
    // returned, they'd still see the old "pending" state until they
    // poked the UI. Observing the lifecycle lets us reload templates
    // (and the promotions list, since template names hang off it)
    // the moment the app comes back to foreground while we're on
    // this surface.
    WidgetsBinding.instance.addObserver(this);

    _tabs = [
      TabItem(
        title: 'Promotions',
        content: const PromotionsTab(),
        fabLabel: 'Run Promotion',
        fabIcon: Icons.campaign_outlined,
        onTap: (ctx, vm) async {
          // PAS-UX-09: routed through RunPromotionLauncher so the
          // approval check, dialog, and post-return refresh stay in
          // one place. The launcher already handles the no-approved
          // dialog, so the FAB callback no longer needs the
          // duplicate guard that lived in _buildFloatingActionButton.
          await RunPromotionLauncher.launch(
            ctx,
            viewModel: vm,
            onGoToTemplates: () => _tabController.animateTo(1),
          );
          _tabController.animateTo(0);
        },
      ),
      TabItem(
        title: 'Templates',
        content: const TemplatesTab(),
        fabLabel: 'Create Template',
        fabIcon: Icons.library_books_outlined,
        onTap: (ctx, vm) async {
          final result =
              await Navigator.of(ctx).push<TemplateSubmitResult>(
                  MaterialPageRoute(
            builder: (_) => CreateTemplatePage(viewModel: vm),
          ));
          if (!mounted) return;
          // The two outcomes are distinct: "Done" returns the merchant
          // to the Templates tab they launched from; "View pending
          // templates" also lands on Templates (same tab) but we
          // explicitly switch so the contract is honoured even if a
          // future caller pushes from elsewhere.
          if (result == TemplateSubmitResult.viewPending) {
            _tabController.animateTo(1);
          } else {
            _tabController.animateTo(1);
          }
          if (result != null) {
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
      // PAS-UX-09: launcher owns the approval check + push + refresh.
      await RunPromotionLauncher.launch(
        context,
        viewModel: vm,
        onGoToTemplates: () => _tabController.animateTo(1),
      );
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
    WidgetsBinding.instance.removeObserver(this);
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;
    final vm = context.read<PromotionsViewModel>();
    // Refresh whatever is on-screen. Both lists are cheap one-shot
    // reads; we deliberately stop short of a Firestore stream
    // refactor because the audit (#3c) recommended the targeted
    // refresh first.
    if (_tabController.index == 0) {
      vm.loadInitialData();
    } else {
      vm.loadTemplatesData();
    }
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
    // PAS-UX-09: previously the FAB ran a second, drifted, copy of
    // the "any approved templates?" predicate and showed its own
    // dialog before delegating to the tab's onTap (which would then
    // push the page anyway). Both pieces are now owned by
    // RunPromotionLauncher, so the FAB just hands off to the tab's
    // onTap and the launcher decides whether to push or to show the
    // no-approved dialog. The Templates tab's onTap is unaffected
    // because it doesn't touch the launcher.
    return FloatingActionButton.extended(
      onPressed: () => current.onTap(context, vm),
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
