import 'package:flutter/material.dart';

import 'package:pasella/constants/constants.dart';
import './business_tile.dart';
import 'package:pasella/pages/settings/widgets/setting_tile.dart';

class BusinessBottomSheet extends StatelessWidget {
  const BusinessBottomSheet({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 20.0, top: 15.0, right: 20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saved Businesses',
            style: TextStyle(
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 12.0),
          BusinessTile(
            isActive: true,
            imagePath: 'assets/images/user.jpg',
            businessName: 'Omar',
            userName: 'Vulindlela Supermarket',
          ),
          Divider(color: kHighLightColor),
          BusinessTile(
            imagePath: 'assets/images/user2.png',
            businessName: 'Muntu',
            userName: 'Vulindlela Supermarket 2',
          ),
          BusinessTile(
            imagePath: 'assets/images/user3.png',
            businessName: 'Shakil',
            userName: 'Vulindlela Supermarket 3',
          ),
          SettingTile(
            icon: Icons.add,
            title: 'Create New Business',
          )
        ],
      ),
    );
  }
}
