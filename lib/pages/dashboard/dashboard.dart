import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/suspension_paywall.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_onboarding_intro.dart';
import 'package:pasella/widgets/consent_modal.dart';
import 'package:provider/provider.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  static const id = '/dashboard';

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  bool _introScheduled = false;
  bool _consentPromptScheduled = false;

  /// PAS-UX-DESIGN: the first-run telemetry consent modal used to be
  /// triggered from `main.dart` post-frame, which surfaced it *before*
  /// the user had any app context. Showing it here, on the first render
  /// of the authenticated Dashboard, means the user has just landed on
  /// a recognisable screen and the decision sits in context. The modal
  /// itself short-circuits via [ConsentService.state.hasDecided], so
  /// repeat builds are no-ops.
  Future<void> _showConsentModalIfNeeded() async {
    if (_consentPromptScheduled) return;
    _consentPromptScheduled = true;
    // One frame of breathing room so the Dashboard finishes painting
    // before the dialog occludes it — feels less like an ambush.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await ConsentModal.showIfNeeded(context);
  }

  Future<void> _showOnboardingIntroIfNeeded(String userId) async {
    if (_introScheduled || userId.isEmpty) return;
    _introScheduled = true;

    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final box = Hive.box('appBox');
    final seenKey = 'merchant_onboarding_intro_seen:$userId';
    final seen = box.get(seenKey, defaultValue: false) as bool;
    if (seen) return;

    await box.put(seenKey, true);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder:
          (_) => MerchantOnboardingIntro(
            onOpenProducts: () {
              if (!mounted) return;
              context.read<AppModel>().updateCurrentIndex(1);
            },
          ),
    );
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
          return Scaffold(
            body: Center(
              child: Text(
                "Wallet data not found.",
                style: TextStyle(fontSize: SizeConfig.textMultiplier * 2.5),
              ),
            ),
          );
        }

        final isSuspended = data['accountSuspended'] ?? false;

        if (isSuspended) {
          final walletState = WalletViewModel.fromFirestore(data);
          return SuspensionPaywall(walletState: walletState);
        }

        return Consumer<AppModel>(
          builder: (context, value, child) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Consent first (POPIA), then merchant onboarding intro.
              // Both are gated by their own "already seen" flags so they
              // only fire once per install.
              _showConsentModalIfNeeded();
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
                  onDestinationSelected:
                      (index) => value.handleNavigation(context, index),
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
