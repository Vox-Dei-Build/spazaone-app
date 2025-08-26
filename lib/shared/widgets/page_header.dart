import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/settings/settings.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/shared/widgets/connectivity_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PageHeader extends StatelessWidget {
  final VoidCallback? onSearchTap;
  final Widget? actionWidget;

  const PageHeader({
    Key? key,
    this.onSearchTap,
    this.actionWidget,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 1,
          vertical: SizeConfig.heightMultiplier * 0),
      child: Row(
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            color: Colors.orangeAccent,
            size: SizeConfig.imageSizeMultiplier * 7,
          ),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 1.3),
          Text(
            'Pasella',
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 4,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (onSearchTap != null)
            Expanded(
              child: IconButton(
                icon: Icon(Icons.search,
                    color: Colors.black,
                    size: SizeConfig.imageSizeMultiplier * 5),
                onPressed: onSearchTap,
                alignment: Alignment.centerRight,
              ),
            )
          else
            const Spacer(),
          const Spacer(),
          if (actionWidget != null) actionWidget!,
          const Spacer(),
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseAuth.instance.currentUser == null
                  ? null
                  : FirebaseFirestore.instance
                      .collection('users')
                      .doc(FirebaseAuth.instance.currentUser!.uid)
                      .collection('wallet')
                      .doc('current')
                      .snapshots(),
              builder: (context, snapshot) {
                double salesBalance = 0;
                if (snapshot.hasData && snapshot.data?.data() != null) {
                  final data = snapshot.data!.data()!;
                  final sb = data['salesVirtualBalance'];
                  if (sb is num) {
                    salesBalance = sb.toDouble();
                  }
                }

                final button = IconButton(
                  icon: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Colors.black,
                    size: SizeConfig.imageSizeMultiplier * 5,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const WalletPage(),
                      ),
                    );
                  },
                  alignment: Alignment.centerRight,
                );

                if (salesBalance > 0) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      button,
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Icon(
                          Icons.circle,
                          color: Colors.green,
                          size: SizeConfig.imageSizeMultiplier * 2.5,
                        ),
                      ),
                    ],
                  );
                }

                return button;
              },
            ),
          ),
          const Spacer(),
          Expanded(
            child: IconButton(
              icon: Icon(Icons.settings_outlined,
                  color: Colors.black,
                  size: SizeConfig.imageSizeMultiplier * 5),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SettingsPage(),
                  ),
                );
              },
              alignment: Alignment.centerRight,
            ),
          ),
          const Spacer(),
          const ConnectivityIndicator(),
        ],
      ),
    );
  }
}
