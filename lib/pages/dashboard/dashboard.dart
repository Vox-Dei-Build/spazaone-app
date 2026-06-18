import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/stock/new_product_page/new_product_page.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/suspension_paywall.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_onboarding_intro.dart';
import 'package:provider/provider.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  static const id = '/dashboard';

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  bool _introScheduled = false;

  /// PAS-GROWTH-03: the first-run telemetry consent modal is now triggered
  /// from `LoginPage.initState` (pre-login) instead of here. POPIA compliance
  /// requires us to capture the consent decision before any anonymous-auth
  /// or session events can fire to PostHog / Firebase Analytics. The
  /// previous "show on first Dashboard render" placement was friendlier UX
  /// but left a window where pre-consent events could leak.

  Future<void> _showOnboardingIntroIfNeeded(String userId) async {
    if (_introScheduled || userId.isEmpty) return;
    _introScheduled = true;

    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final box = Hive.box('appBox');
    final seenKey = 'merchant_onboarding_intro_seen:$userId';
    final seen = box.get(seenKey, defaultValue: false) as bool;
    if (seen) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => MerchantOnboardingIntro(
        onOpenProducts: () {
          if (!mounted) return;
          // PAS-UX-19: pre-select the Products tab so popping
          // NewProductPage lands the merchant on their catalogue,
          // then push the add-product form directly. The previous
          // behaviour only switched tabs, which dropped a fresh
          // merchant on the empty-state screen and required an
          // extra tap to reach the form the CTA had just promised.
          context.read<AppModel>().updateCurrentIndex(1);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const NewProductPage(),
            ),
          );
        },
      ),
    );

    // Persist only after the sheet was actually presented and dismissed.
    // Writing this before showModalBottomSheet allowed a short-lived
    // Dashboard during registration to consume onboarding invisibly behind
    // FinishProfilePage.
    await box.put(seenKey, true);
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
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
              // Consent is handled pre-login in LoginPage (PAS-GROWTH-03).
              // Only the merchant onboarding intro is scheduled here, gated
              // by its own "already seen" flag so it fires once per install.
              _showOnboardingIntroIfNeeded(userId);
            });
            // PAS-UI-01: the OnboardingChecklist that previously mounted
            // here (per PAS-UX-09) has been removed from the visible
            // dashboard chrome. Merchant feedback was that it consumed
            // persistent vertical space above every tab while delivering
            // little ongoing value once one or two items were auto-
            // ticked. The widget definition
            // (`lib/shared/widgets/onboarding/onboarding_checklist.dart`)
            // is intentionally retained un-mounted so its auto-detect
            // logic and Hive persistence can be reused by a future
            // activation surface (e.g. a dismissible empty-state).
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
