import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/promote_intent_bus.dart';
import 'package:pasella/pages/promote/utils/run_promotion_launcher.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotion_tab_item.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotions_tab.dart';
import 'package:pasella/pages/promote/widgets/promotions_page_header.dart';
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
        fabLabel: 'Promote a product',
        fabIcon: Icons.campaign_outlined,
        onTap: (ctx, vm) async {
          await RunPromotionLauncher.launch(
            ctx,
            viewModel: vm,
          );
          _tabController.animateTo(0);
        },
      ),
    ];

    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(_onTabChanged);

    // initial load for tab 0
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<PromotionsViewModel>();
      vm.loadInitialData().then((_) async {
        await vm.ensureProductPromotionTemplate();
        if (mounted) _handlePendingIntent();
      });
    });
  }

  /// Reacts to a deep-link intent stashed by the FCM handler. Called once
  /// after the first templates load so we can resolve the templateId.
  Future<void> _handlePendingIntent() async {
    final intent = PromoteIntentBus.instance.consume();
    if (intent == null || !mounted) return;

    _tabController.animateTo(0);

    final vm = context.read<PromotionsViewModel>();

    if (intent.action == 'run' && mounted) {
      await RunPromotionLauncher.launch(
        context,
        viewModel: vm,
      );
    }
  }

  void _onTabChanged() {
    // only fire once per real tab switch
    if (!_tabController.indexIsChanging &&
        _tabController.index != _previousTabIndex) {
      final vm = context.read<PromotionsViewModel>();

      vm.loadInitialData();

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
    vm.loadInitialData().then((_) => vm.ensureProductPromotionTemplate());
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    // PAS-CRASH-_dependents: the PromotionsViewModel is owned by the root
    // MultiProvider (main.dart). Re-wrapping with a page-scoped
    // ChangeNotifierProvider produced a second instance whose lifetime ended
    // mid-transition while pushed routes (e.g. RunPromotionPage) still held
    // dependents, tripping the framework's `_dependents.isEmpty` assertion.
    return Consumer<PromotionsViewModel>(
      builder: (context, viewModel, _) {
        final current = _tabs[_tabController.index];

        return Scaffold(
          floatingActionButton: _buildFloatingActionButton(viewModel, current),
          body: SafeArea(
            child: Padding(
              padding: LayoutConstants.padding10Horizontal,
              child: Column(
                children: [
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  const PromotionsPageHeader(),
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
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
      // PAS-CRASH-_dependents: explicit heroTag avoids the default
      // `<default FloatingActionButton tag>` Hero collision with FABs on
      // other surfaces. Collisions reparent the FAB subtree through the
      // Navigator overlay during transitions, which is one of the known
      // ways to leave an InheritedElement with non-empty `_dependents`.
      heroTag: 'promotions-page-fab',
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
