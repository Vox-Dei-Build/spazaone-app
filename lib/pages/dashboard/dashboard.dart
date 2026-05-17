import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/contact/add_contact/add_contact.dart';
import 'package:pasella/pages/promote/promote_intent_bus.dart';
import 'package:pasella/pages/promote/promotions_page.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/suspension_paywall.dart';
import 'package:pasella/shared/widgets/onboarding/onboarding_checklist.dart';
import 'package:provider/provider.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  static const id = '/dashboard';

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return Scaffold(
        body: Center(
            child: Text("User not logged in.",
                style: TextStyle(fontSize: SizeConfig.textMultiplier * 2.5))),
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
                child: Text("Wallet data not found.",
                    style:
                        TextStyle(fontSize: SizeConfig.textMultiplier * 2.5))),
          );
        }

        final isSuspended = data['accountSuspended'] ?? false;

        if (isSuspended) {
          final walletState = WalletViewModel.fromFirestore(data);
          return SuspensionPaywall(walletState: walletState);
        }

        return Consumer<AppModel>(
          builder: (context, value, child) {
            // PAS-UX-09: mount OnboardingChecklist at the Dashboard
            // scaffold level, above the active tab body. Previously
            // it lived inside LedgerPage and was therefore only
            // visible on the Customers tab. Industry-standard
            // activation patterns (Shopify, Stripe, Linear,
            // Intercom) anchor the activation checklist to the
            // home/dashboard chrome so it stays visible across every
            // feature surface until activation is complete. Auto-
            // tick from real Firestore signals handled inside the
            // widget — see OnboardingChecklist.
            return Scaffold(
              body: Column(
                children: [
                  OnboardingChecklist(
                    userId: userId,
                    onAddProduct: () =>
                        context.read<AppModel>().updateCurrentIndex(1),
                    onAddCustomer: () =>
                        Navigator.pushNamed(context, AddContactPage.id),
                    onRecordSale: () =>
                        context.read<AppModel>().updateCurrentIndex(2),
                    onApproveTemplate: () {
                      // Land the merchant on the Templates tab so
                      // they can create one. The shared
                      // PromoteIntentBus is the canonical way to
                      // pre-route the Promote surface.
                      PromoteIntentBus.instance.set(
                        const PromoteIntent(tab: 'templates'),
                      );
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PromotionsPage(),
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: value.navigationOptions[value.currentIndex],
                  ),
                ],
              ),
              bottomNavigationBar: ClipRRect(
                borderRadius:
                    BorderRadius.circular(SizeConfig.imageSizeMultiplier * 5),
                child: NavigationBar(
                  selectedIndex: value.currentIndex,
                  onDestinationSelected: (index) =>
                      value.handleNavigation(context, index),
                  destinations: [
                    NavigationDestination(
                      icon: Icon(Icons.contacts_outlined,
                          size: SizeConfig.imageSizeMultiplier * 5),
                      selectedIcon: Icon(Icons.contacts_outlined,
                          size: SizeConfig.imageSizeMultiplier * 5),
                      label: 'Customers',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.inventory_outlined,
                          size: SizeConfig.imageSizeMultiplier * 5),
                      selectedIcon: Icon(Icons.inventory_outlined,
                          size: SizeConfig.imageSizeMultiplier * 5),
                      label: 'Products',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.point_of_sale,
                          size: SizeConfig.imageSizeMultiplier * 5),
                      selectedIcon: Icon(Icons.point_of_sale,
                          size: SizeConfig.imageSizeMultiplier * 5),
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
