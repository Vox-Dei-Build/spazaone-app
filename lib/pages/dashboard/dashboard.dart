import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/suspenstion_paywall.dart';
import 'package:provider/provider.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  static const id = '/dashboard';

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text("User not logged in.")),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final isSuspended = data?['accountSuspended'] ?? false;

        if (isSuspended) {
          final walletState = WalletViewModel.fromFirestore(data!);
          return SuspensionPaywall(walletState: walletState);
        }

        return Consumer<AppModel>(
          builder: (context, value, child) {
            return Scaffold(
              body: value.navigationOptions[value.currentIndex],
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
                    NavigationDestination(
                      icon: Icon(Icons.wallet,
                          size: SizeConfig.imageSizeMultiplier * 5),
                      selectedIcon: Icon(Icons.wallet,
                          size: SizeConfig.imageSizeMultiplier * 5),
                      label: 'Billing',
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
