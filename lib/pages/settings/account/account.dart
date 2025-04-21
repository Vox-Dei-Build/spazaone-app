import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/pages/settings/account/widgets/account_card.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  static const id = '/accountPage';

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: CustomAppBar(title: 'Account'),
      body: SafeArea(
        child: Padding(
          padding: LayoutConstants.padding10Horizontal,
          child: Column(
            children: [
              AccountCard(
                icon: Icons.book,
                accountType: 'Customer',
                paymentType: 'R',
                amount: '750',
              ),
              /* const AccountCard(
                icon: Icons.local_shipping_sharp,
                accountType: 'Supplier',
                paymentType: 'R',
                amount: '200',
              ), */
              /* Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(color: kHighLightColor),
                  ),
                  child: SettingTile(
                    icon: Icons.business,
                    title: 'Business Report',
                    hideDivider: true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => BusinessReportPage()),
                      );
                    },
                  ),
                ),
              ), */
              /* Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(color: kHighLightColor),
                ),
                child: const SettingTile(
                  icon: Icons.download,
                  title: 'Download Backup',
                  hideDivider: true,
                ),
              ), */
            ],
          ),
        ),
      ),
    );
  }
}
