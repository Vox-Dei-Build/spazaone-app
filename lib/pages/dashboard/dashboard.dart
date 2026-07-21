import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/contact/add_contact/add_contact.dart';
import 'package:pasella/pages/transactions/add_credit/add_credit.dart';
import 'package:pasella/pages/stock/new_product_page/new_product_page.dart';
import 'package:pasella/pages/settings/share/share.dart';
import 'package:pasella/services/activation_nudge_intent_bus.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/pages/wallet/widgets/suspension_paywall.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_onboarding_intro.dart';
import 'package:pasella/widgets/consent_modal.dart';
import 'package:provider/provider.dart';
import 'package:pasella/services/store_session.dart';

@visibleForTesting
bool shouldShowSpazaOneRebrandNotice({
  required DateTime? accountCreatedAt,
  DateTime? now,
}) {
  if (accountCreatedAt == null) return true;
  return (now ?? DateTime.now()).difference(accountCreatedAt) >=
      const Duration(hours: 1);
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  static const id = '/dashboard';

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  bool _introScheduled = false;
  bool _firstRunSurfacesScheduled = false;
  bool _rebrandNoticeScheduled = false;
  bool _activationIntentProcessing = false;

  /// First-run surfaces are sequenced here once deferred auth consent is on:
  /// consent sheet first, onboarding intro second. Telemetry stays disabled
  /// while consent is undecided, so this can happen after phone auth without
  /// leaking pre-consent analytics.

  Future<void> _showFirstRunSurfacesIfNeeded(String userId) async {
    if (_firstRunSurfacesScheduled || userId.isEmpty) return;
    _firstRunSurfacesScheduled = true;

    if (FeatureFlags.enableDeferAuthConsent) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await ConsentModal.showPostAuthIfNeeded(context);
      if (!mounted) return;
    }

    await _showRebrandNoticeIfNeeded(userId);
    if (!mounted) return;
    await _showOnboardingIntroIfNeeded(userId);
  }

  Future<void> _showRebrandNoticeIfNeeded(String userId) async {
    if (_rebrandNoticeScheduled || userId.isEmpty) return;
    _rebrandNoticeScheduled = true;

    final box = Hive.box('appBox');
    final seenKey = 'spazaone_rebrand_notice_seen:$userId';
    final seen = box.get(seenKey, defaultValue: false) as bool;
    if (seen) return;

    final accountCreatedAt =
        FirebaseAuth.instance.currentUser?.metadata.creationTime;
    if (!shouldShowSpazaOneRebrandNotice(
      accountCreatedAt: accountCreatedAt,
    )) {
      await box.put(seenKey, true);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _SpazaOneRebrandNotice(),
    );

    await box.put(seenKey, true);
  }

  Future<void> _showOnboardingIntroIfNeeded(String userId) async {
    if (_introScheduled || userId.isEmpty) return;
    _introScheduled = true;

    // The setup card on the Customers tab is the persistent guide;
    // the intro is a first-run supplement. When the flag is off we
    // skip the sheet entirely and let the card carry the load.
    if (!FeatureFlags.enableMerchantOnboardingIntro) return;

    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final box = Hive.box('appBox');
    final seenKey = 'merchant_onboarding_intro_seen:$userId';
    final seen = box.get(seenKey, defaultValue: false) as bool;
    if (seen) return;

    final action = await showModalBottomSheet<MerchantOnboardingIntroAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => MerchantOnboardingIntro(
        onOpenCustomers: () {
          if (!mounted) return;
          context.read<AppModel>().updateCurrentIndex(0);
          Navigator.of(context).pushNamed(AddContactPage.id);
        },
        onOpenProducts: () {
          if (!mounted) return;
          // PAS-UX-19: pre-select the Products tab so popping
          // NewProductPage lands the merchant on their catalogue,
          // then push the add-product form directly. The previous
          // behaviour only switched tabs, which dropped a fresh
          // merchant on the empty-state screen and required an
          // extra tap to reach the form the CTA had just promised.
          context.read<AppModel>().updateCurrentIndex(1);
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const NewProductPage()));
        },
      ),
    );

    // Persist only after the sheet was actually presented and dismissed.
    // Writing this before showModalBottomSheet allowed a short-lived
    // Dashboard during registration to consume onboarding invisibly behind
    // FinishProfilePage.
    await box.put(seenKey, true);

    if (!mounted) return;
    switch (action) {
      case MerchantOnboardingIntroAction.openCustomers:
        context.read<AppModel>().updateCurrentIndex(0);
        Navigator.of(context).pushNamed(AddContactPage.id);
      case MerchantOnboardingIntroAction.openProducts:
        context.read<AppModel>().updateCurrentIndex(1);
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NewProductPage()));
      case null:
        break;
    }
  }

  Future<void> _processActivationIntentIfNeeded(String userId) async {
    if (_activationIntentProcessing || userId.isEmpty) return;

    final intent = ActivationNudgeIntentBus.instance.take();
    if (intent == null) return;

    _activationIntentProcessing = true;
    try {
      switch (intent.action) {
        case ActivationNudgeAction.addCustomer:
        case ActivationNudgeAction.addTenCustomers:
          if (!mounted) return;
          context.read<AppModel>().updateCurrentIndex(0);
          Navigator.of(context).pushNamed(AddContactPage.id);
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
          await _openCreditFromActivationIntent(userId, intent);
      }
    } finally {
      _activationIntentProcessing = false;
    }
  }

  Future<void> _openCreditFromActivationIntent(
    String userId,
    ActivationNudgeIntent intent,
  ) async {
    final customerId = intent.customerId;
    if (customerId == null || customerId.isEmpty) {
      if (!mounted) return;
      context.read<AppModel>().updateCurrentIndex(0);
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('customers')
        .doc(customerId)
        .get();

    if (!mounted) return;

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
    final userId = StoreSession.instance.storeId;

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

    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showFirstRunSurfacesIfNeeded(userId);
              _processActivationIntentIfNeeded(userId);
            });
            // PAS-UI-01: the OnboardingChecklist that previously
            // mounted here (per PAS-UX-09) has been removed from the
            // visible dashboard chrome. Merchant feedback was that it
            // consumed persistent vertical space above every tab
            // while delivering little ongoing value once one or two
            // items were auto-ticked. Its role has been superseded
            // by MerchantSetupCard on the Customers tab, which
            // covers the full setup path (customer → product →
            // WhatsApp listing → ordering link → payout → template)
            // and scrolls with the customer list. The old widget
            // (`lib/shared/widgets/onboarding/onboarding_checklist.dart`)
            // is `@Deprecated` — retained only for the Hive-key
            // pattern; do not reintroduce.
            return Scaffold(
              body: value.navigationOptions[value.currentIndex],
              bottomNavigationBar: ClipRRect(
                borderRadius: BorderRadius.circular(
                  SizeConfig.imageSizeMultiplier * 5,
                ),
                child: NavigationBar(
                  selectedIndex: value.currentIndex,
                  onDestinationSelected: (index) =>
                      value.handleNavigation(context, index),
                  destinations: [
                    NavigationDestination(
                      icon: Icon(
                        Icons.contacts_outlined,
                        size: SizeConfig.imageSizeMultiplier * 5,
                      ),
                      selectedIcon: Icon(
                        Icons.contacts_outlined,
                        size: SizeConfig.imageSizeMultiplier * 5,
                      ),
                      label: 'Customers',
                    ),
                    NavigationDestination(
                      icon: Icon(
                        Icons.inventory_outlined,
                        size: SizeConfig.imageSizeMultiplier * 5,
                      ),
                      selectedIcon: Icon(
                        Icons.inventory_outlined,
                        size: SizeConfig.imageSizeMultiplier * 5,
                      ),
                      label: 'Products',
                    ),
                    NavigationDestination(
                      icon: Icon(
                        Icons.point_of_sale,
                        size: SizeConfig.imageSizeMultiplier * 5,
                      ),
                      selectedIcon: Icon(
                        Icons.point_of_sale,
                        size: SizeConfig.imageSizeMultiplier * 5,
                      ),
                      label: 'Sales',
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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

class _SpazaOneRebrandNotice extends StatelessWidget {
  const _SpazaOneRebrandNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          28,
          24,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3C4),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                color: Color(0xFFFFB300),
                size: 42,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Pasella is now SpazaOne',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Same app. Same account. All your customers, balances, products '
              'and sales are right where you left them.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.grey.shade700,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Only the name has changed.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.green.shade800,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Continue to SpazaOne'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
