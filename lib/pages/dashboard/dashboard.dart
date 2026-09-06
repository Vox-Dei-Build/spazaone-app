import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/contact/add_contact/add_contact.dart';
import 'package:pasella/pages/transactions/add_credit/add_credit.dart';
import 'package:pasella/pages/stock/new_product_page/new_product_page.dart';
import 'package:pasella/pages/settings/share/share.dart';
import 'package:pasella/services/activation_nudge_intent_bus.dart';
import 'package:pasella/services/completed_signup_tracker.dart';
import 'package:pasella/services/consent_service.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/pages/wallet/widgets/suspension_paywall.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_onboarding_intro.dart';
import 'package:pasella/widgets/consent_modal.dart';
import 'package:provider/provider.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/services/startup_session_progress.dart';
import 'package:pasella/shared/widgets/responsive_app_layout.dart';

@visibleForTesting
bool shouldHoldDashboardForConsent({
  required ConsentState consent,
  required bool consentSurfaceCompleted,
}) =>
    !consent.hasDecided || !consentSurfaceCompleted;

@visibleForTesting
bool shouldShowMerchantOnboardingIntroForStore({
  required bool introSeen,
  required bool hasCustomers,
  required bool hasProducts,
  required bool isOwner,
  bool hasRecordedSales = false,
}) =>
    isOwner && !introSeen && !hasCustomers && !hasProducts && !hasRecordedSales;

/// Waits for the originating workspace and the closing overlay's transition.
/// The identity predicate cancels pending work after logout or a store switch.
@visibleForTesting
Future<bool> waitUntilStartupRouteReady(
  BuildContext context, {
  required bool Function() isCurrent,
}) async {
  while (isCurrent()) {
    if (!context.mounted) return false;
    final route = ModalRoute.of(context);
    if (route == null ||
        (route.isCurrent && (route.secondaryAnimation?.isDismissed ?? true))) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

/// Keeps the primary destinations available without sacrificing a quarter of
/// a phone's landscape height to the bottom navigation bar.
class ResponsiveDashboardShell extends StatelessWidget {
  const ResponsiveDashboardShell({
    super.key,
    required this.body,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final Widget body;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    if (usesCompactLandscapeLayout(context)) {
      final largeText = MediaQuery.textScalerOf(context).scale(12) >= 20;
      final railWidth = largeText ? 120.0 : 68.0;
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              right: false,
              child: SizedBox(
                width: railWidth,
                child: largeText
                    ? _AccessibleLandscapeNavigation(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: onDestinationSelected,
                      )
                    : NavigationRail(
                        key: const ValueKey('landscape-primary-navigation'),
                        selectedIndex: selectedIndex,
                        onDestinationSelected: onDestinationSelected,
                        labelType: NavigationRailLabelType.selected,
                        minWidth: railWidth,
                        groupAlignment: 0,
                        useIndicator: true,
                        indicatorColor: SpazaColors.navy,
                        selectedIconTheme:
                            const IconThemeData(color: SpazaColors.accent),
                        selectedLabelTextStyle: const TextStyle(
                          color: kTertiaryColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                        ),
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        destinations: const [
                          NavigationRailDestination(
                            icon: Tooltip(
                              message: 'Customers',
                              child: Icon(SpazaIcons.customers),
                            ),
                            selectedIcon: Icon(SpazaIcons.customers),
                            label: Text('Customers'),
                          ),
                          NavigationRailDestination(
                            icon: Tooltip(
                              message: 'Products',
                              child: Icon(SpazaIcons.products),
                            ),
                            selectedIcon: Icon(SpazaIcons.products),
                            label: Text('Products'),
                          ),
                          NavigationRailDestination(
                            icon: Tooltip(
                              message: 'Sales',
                              child: Icon(SpazaIcons.sales),
                            ),
                            selectedIcon: Icon(SpazaIcons.sales),
                            label: Text('Sales'),
                          ),
                        ],
                      ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SpazaColors.border, width: .5)),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: const [
            NavigationDestination(
              icon: Icon(
                SpazaIcons.customers,
                size: 22,
              ),
              selectedIcon: Icon(
                SpazaIcons.customers,
                size: 22,
              ),
              label: 'Customers',
            ),
            NavigationDestination(
              icon: Icon(
                SpazaIcons.products,
                size: 22,
              ),
              selectedIcon: Icon(
                SpazaIcons.products,
                size: 22,
              ),
              label: 'Products',
            ),
            NavigationDestination(
              icon: Icon(
                SpazaIcons.sales,
                size: 22,
              ),
              selectedIcon: Icon(
                SpazaIcons.sales,
                size: 22,
              ),
              label: 'Sales',
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessibleLandscapeNavigation extends StatelessWidget {
  const _AccessibleLandscapeNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _items = <(IconData, String)>[
    (SpazaIcons.customers, 'Customers'),
    (SpazaIcons.products, 'Products'),
    (SpazaIcons.sales, 'Sales'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey('landscape-primary-navigation'),
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            for (var index = 0; index < _items.length; index++)
              Expanded(
                child: _AccessibleLandscapeDestination(
                  icon: _items[index].$1,
                  label: _items[index].$2,
                  selected: selectedIndex == index,
                  onTap: () => onDestinationSelected(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccessibleLandscapeDestination extends StatelessWidget {
  const _AccessibleLandscapeDestination({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? Colors.white : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? kTertiaryColor : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    color: selected ? SpazaColors.accent : foreground,
                    size: 20),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  static const id = '/dashboard';

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final _startup = StartupSessionProgress.instance;
  StartupSessionToken? _startupToken;
  bool _activationIntentProcessing = false;
  late bool _consentSurfaceCompleted;

  @override
  void initState() {
    super.initState();
    _consentSurfaceCompleted = ConsentService.instance.state.hasDecided;
    _startup.addListener(_scheduleStartup);
  }

  @override
  void dispose() {
    _startup.removeListener(_scheduleStartup);
    final token = _startupToken;
    if (token != null) _startup.abandon(token);
    _startupToken = null;
    super.dispose();
  }

  void _scheduleStartup() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runStartupSequence(StoreSession.instance.storeId);
    });
  }

  bool _isCurrentStartup(StartupSessionToken token) =>
      mounted &&
      _startup.isCurrent(token) &&
      FirebaseAuth.instance.currentUser?.uid == token.userId &&
      StoreSession.instance.storeId == token.storeId;

  /// One route owns the sequence for this login and store. Optional guide
  /// failures complete only this session; the persistent intro remains unseen.
  Future<void> _runStartupSequence(String storeId) async {
    if (!mounted || storeId != StoreSession.instance.storeId) return;
    final token = _startup.bind(
      userId: FirebaseAuth.instance.currentUser?.uid,
      storeId: storeId,
    );
    if (token == null) return;
    if (!_startup.tryBegin(token)) {
      // A notification can open another Dashboard later in the same login.
      // Its pending action still belongs to this route, even though the
      // optional guide has already completed for the session.
      if (_startup.ready &&
          _isCurrentStartup(token) &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        try {
          await _processActivationIntentIfNeeded(token);
        } catch (error) {
          debugPrint('Activation navigation failed: $error');
        }
      }
      return;
    }
    _startupToken = token;
    var outcome = StartupOutcome.skipped;
    try {
      if (!await _waitUntilCurrentRoute(token) || !mounted) return;
      await ConsentModal.showPostAuthIfNeeded(context);
      if (!await _waitUntilCurrentRoute(token)) return;
      final consentDecided = ConsentService.instance.state.hasDecided;
      if (!consentDecided) return;
      setState(() => _consentSurfaceCompleted = true);
      _startup.consentSurfaceClosed(token, consentDecided: consentDecided);
      if (!await _waitUntilCurrentRoute(token)) return;

      // Attribution belongs to the signed-in person, even when an operator
      // opens a store whose ID differs from the auth UID.
      unawaited(CompletedSignupTracker.instance
          .resolveAfterConsent(merchantId: token.userId)
          .catchError((Object error) {
        debugPrint('Deferred signup measurement failed: $error');
      }));

      outcome = await _showOnboardingIntroIfNeeded(token);
      if (!await _waitUntilCurrentRoute(token)) return;
      await _processActivationIntentIfNeeded(token);
      if (!await _waitUntilCurrentRoute(token)) return;
      _startup.complete(token, outcome);
    } catch (error) {
      debugPrint('Dashboard startup sequence failed: $error');
      if (_isCurrentStartup(token) && _consentSurfaceCompleted) {
        _startup.complete(token, StartupOutcome.skipped);
      }
    } finally {
      if (identical(_startupToken, token)) _startup.abandon(token);
    }
  }

  Future<bool> _waitUntilCurrentRoute(StartupSessionToken token) =>
      waitUntilStartupRouteReady(context,
          isCurrent: () => _isCurrentStartup(token));

  bool _hasOwnerScope(StartupSessionToken token) =>
      _isCurrentStartup(token) &&
      !StoreSession.instance.loading &&
      StoreSession.instance.storeAccessResolved &&
      StoreSession.instance.activeStore?.role == StoreRole.owner;

  Future<StartupOutcome> _showOnboardingIntroIfNeeded(
    StartupSessionToken token,
  ) async {
    if (!FeatureFlags.enableMerchantOnboardingIntro) {
      return StartupOutcome.skipped;
    }

    // Bootstrap already has its own bounded network timeout. Do not infer
    // ownership from a temporary auth-UID fallback while it is unresolved.
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (_isCurrentStartup(token) &&
        StoreSession.instance.loading &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!_hasOwnerScope(token)) return StartupOutcome.skipped;

    final seenKey = 'merchant_onboarding_intro_seen:${token.storeId}';
    Box<dynamic>? box;
    try {
      box = Hive.isBoxOpen('appBox') ? Hive.box('appBox') : null;
      final seen = box?.get(seenKey, defaultValue: false) == true;
      if (seen) return StartupOutcome.skipped;
      final storeRef =
          FirebaseFirestore.instance.collection('users').doc(token.storeId);
      const server = GetOptions(source: Source.server);
      final activity = await Future.wait([
        storeRef.collection('customers').limit(1).get(server),
        storeRef.collection('products').limit(1).get(server),
        storeRef.collection('sales').limit(1).get(server),
      ]).timeout(const Duration(seconds: 8));
      if (!_hasOwnerScope(token)) return StartupOutcome.skipped;
      if (!shouldShowMerchantOnboardingIntroForStore(
        introSeen: seen,
        isOwner: true,
        hasCustomers: activity[0].docs.isNotEmpty,
        hasProducts: activity[1].docs.isNotEmpty,
        hasRecordedSales: activity[2].docs.isNotEmpty,
      )) {
        return StartupOutcome.skipped;
      }
    } catch (error) {
      // Offline/cached emptiness cannot identify a first-time owner. Skip this
      // login without consuming a future eligible store's welcome.
      debugPrint('Merchant onboarding eligibility check failed: $error');
      return StartupOutcome.skipped;
    }

    if (!await _waitUntilCurrentRoute(token) || !_hasOwnerScope(token)) {
      return StartupOutcome.skipped;
    }
    BuildContext? sheetContext;
    var dismissalScheduled = false;
    var abortedForScope = false;
    void dismissStaleSheet() {
      if (_hasOwnerScope(token) || dismissalScheduled) return;
      dismissalScheduled = true;
      abortedForScope = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentContext = sheetContext;
        if (_hasOwnerScope(token) ||
            currentContext == null ||
            !currentContext.mounted) {
          return;
        }
        final route = ModalRoute.of(currentContext);
        if (route != null && route.isCurrent) route.navigator?.pop();
      });
    }

    _startup.addListener(dismissStaleSheet);
    StoreSession.instance.addListener(dismissStaleSheet);
    MerchantOnboardingIntroAction? action;
    if (!mounted) return StartupOutcome.skipped;
    try {
      action = await showModalBottomSheet<MerchantOnboardingIntroAction>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(SpazaRadius.sheet)),
        ),
        builder: (context) {
          sheetContext = context;
          return MerchantOnboardingIntro(
            // Modal actions are returned, then dispatched once below after
            // the sheet closes. Inline fallback callbacks stay compatible.
            onOpenCustomers: () {},
            onOpenProducts: () {},
          );
        },
      );
    } finally {
      _startup.removeListener(dismissStaleSheet);
      StoreSession.instance.removeListener(dismissStaleSheet);
    }
    if (abortedForScope ||
        !await _waitUntilCurrentRoute(token) ||
        !_hasOwnerScope(token)) {
      return StartupOutcome.skipped;
    }
    try {
      await box?.put(seenKey, true);
    } catch (error) {
      debugPrint('Could not remember onboarding dismissal: $error');
    }
    if (!_hasOwnerScope(token) || !mounted) return StartupOutcome.skipped;
    switch (action) {
      case MerchantOnboardingIntroAction.openCustomers:
        context.read<AppModel>().updateCurrentIndex(0);
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const AddContactPage(returnToCallerAfterSave: true),
        ));
      case MerchantOnboardingIntroAction.openProducts:
        context.read<AppModel>().updateCurrentIndex(1);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const NewProductPage(),
        ));
      case null:
        break;
    }
    return StartupOutcome.completed;
  }

  Future<void> _processActivationIntentIfNeeded(
      StartupSessionToken token) async {
    if (_activationIntentProcessing || !_isCurrentStartup(token)) return;

    final intent = ActivationNudgeIntentBus.instance.take();
    if (intent == null) return;

    _activationIntentProcessing = true;
    try {
      switch (intent.action) {
        case ActivationNudgeAction.addCustomer:
        case ActivationNudgeAction.addTenCustomers:
          if (!mounted) return;
          context.read<AppModel>().updateCurrentIndex(0);
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const AddContactPage(returnToCallerAfterSave: true),
          ));
        case ActivationNudgeAction.addProduct:
          if (!mounted) return;
          context.read<AppModel>().updateCurrentIndex(1);
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const NewProductPage()));
        case ActivationNudgeAction.shareOrderingLink:
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SharePage(source: 'activation_nudge'),
            ),
          );
        case ActivationNudgeAction.linkProductTransaction:
        case ActivationNudgeAction.recordFirstTransaction:
          await _openCreditFromActivationIntent(token, intent);
      }
    } finally {
      _activationIntentProcessing = false;
    }
  }

  Future<void> _openCreditFromActivationIntent(
    StartupSessionToken token,
    ActivationNudgeIntent intent,
  ) async {
    final customerId = intent.customerId;
    if (customerId == null || customerId.isEmpty) {
      if (!_isCurrentStartup(token) || !mounted) return;
      context.read<AppModel>().updateCurrentIndex(0);
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(token.storeId)
        .collection('customers')
        .doc(customerId)
        .get()
        .timeout(const Duration(seconds: 8));

    if (!_isCurrentStartup(token) || !mounted) return;

    if (!doc.exists) {
      context.read<AppModel>().updateCurrentIndex(0);
      return;
    }

    final data = doc.data() ?? const <String, dynamic>{};
    final customerName = (data['name'] as String?)?.trim();
    if (customerName == null || customerName.isEmpty) {
      context.read<AppModel>().updateCurrentIndex(0);
      return;
    }

    final mobileNumber = (data['number'] as String?)?.trim();
    context.read<AppModel>().updateCurrentIndex(0);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddCreditScreen(
          customerName: customerName,
          customerId: customerId,
          mobileNumber: mobileNumber == null || mobileNumber.isEmpty
              ? null
              : mobileNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final userId = context.watch<StoreSession>().storeId;

    if (userId.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            "User not logged in.",
            style: TextStyle(fontSize: SizeConfig.textMultiplier * 2.5),
          ),
        ),
      );
    }

    return ValueListenableBuilder<ConsentState>(
      valueListenable: ConsentService.instance.notifier,
      builder: (context, consent, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _runStartupSequence(userId);
        });

        // Keep first-run coachmarks and empty-state guidance out of view until
        // the privacy choice closes. This removes the visual "two onboarding
        // cards at once" effect on small phones.
        if (shouldHoldDashboardForConsent(
          consent: consent,
          consentSurfaceCompleted: _consentSurfaceCompleted,
        )) {
          return const _PrivacyChoiceProgress();
        }

        final userRef =
            FirebaseFirestore.instance.collection('users').doc(userId);
        final walletRef = userRef.collection('wallet').doc('current');

        return StreamBuilder<DocumentSnapshot>(
          stream: walletRef.snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final data = snapshot.data?.data() as Map<String, dynamic>?;

            if (data == null) {
              // A new account's auth state can arrive a fraction before its
              // initial wallet document. Treat that as setup-in-progress instead
              // of exposing an internal data-state message to the merchant.
              return const _AccountSetupProgress();
            }

            final isSuspended = data['accountSuspended'] ?? false;

            if (isSuspended) {
              final walletState = WalletViewModel.fromFirestore(data);
              return SuspensionPaywall(walletState: walletState);
            }

            return Consumer<AppModel>(
              builder: (context, value, child) {
                // PAS-UI-01: the OnboardingChecklist that previously
                // mounted here (per PAS-UX-09) has been removed from the
                // visible dashboard chrome. Merchant feedback was that it
                // consumed persistent vertical space above every tab
                // while delivering little ongoing value once one or two
                // items were auto-ticked. Its role has been superseded
                // by Shop Setup in Settings, which covers the full setup
                // path (customer → product → WhatsApp listing → ordering link →
                // payout → template) without occupying daily workspace. The old widget
                // (`lib/shared/widgets/onboarding/onboarding_checklist.dart`)
                // is `@Deprecated` — retained only for the Hive-key
                // pattern; do not reintroduce.
                return ResponsiveDashboardShell(
                  body: value.navigationOptions[value.currentIndex],
                  selectedIndex: value.currentIndex,
                  onDestinationSelected: (index) =>
                      value.handleNavigation(context, index),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PrivacyChoiceProgress extends StatelessWidget {
  const _PrivacyChoiceProgress();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: const SafeArea(
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _AccountSetupProgress extends StatelessWidget {
  const _AccountSetupProgress();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 36,
                    color: Colors.green.shade700,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Setting up your account',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'We’re preparing your wallet and business workspace. '
                  'This usually takes a moment.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade700,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(minHeight: 6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
