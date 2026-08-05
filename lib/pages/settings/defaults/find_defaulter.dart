import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/pages/settings/defaults/widgets/defaulter_card.dart';
import 'package:pasella/pages/settings/defaults/widgets/defaulter_info_tile.dart';

class FindDefaulterPage extends StatelessWidget {
  const FindDefaulterPage({super.key});

  static const id = '/findDefaulterPage';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Defaulters'),
      body: SafeArea(
        child: Padding(
          padding: LayoutConstants.padding10Horizontal,
          child: Column(
            children: [
              const Row(
                children: [
                  DefaulterCard(
                    title: 'Transactions Due',
                    subtitle: 'R28 000.00',
                  ),
                  DefaulterCard(
                    title: '#Defaulters',
                    subtitle: '8',
                  ),
                ],
              ),
              const SizedBox(height: 20.0),
              Container(
                decoration: BoxDecoration(
                  color: kHighLightColor,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                margin: const EdgeInsets.symmetric(horizontal: 10.0),
                child: const Column(
                  children: [
                    DefaulterInfoTile(
                      imagePath: 'assets/images/star.png',
                      contentMap: {
                        '2.65 thousand ':
                            TextStyle(fontWeight: FontWeight.bold),
                        'merchants have marked ': null,
                        '250 ': TextStyle(fontWeight: FontWeight.bold),
                        'customers as defaulters.': null,
                      },
                    ),
                    DefaulterInfoTile(
                      imagePath: 'assets/images/rands.png',
                      contentMap: {
                        'Merchants marking defaulters on Spaza One are saving up to ':
                            null,
                        'R15 000.00 monthly.':
                            TextStyle(fontWeight: FontWeight.bold),
                      },
                    ),
                    DefaulterInfoTile(
                      hasDivider: false,
                      imagePath: 'assets/images/defaulter.png',
                      contentMap: {
                        'Start adding your customers to ': null,
                        'defaulters list and save ':
                            TextStyle(fontWeight: FontWeight.bold),
                        'your hard earned money.': null,
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15.0),
              const Text('For any related to defaulter feature'),
              const Text(
                'Reach is on WhatsApp',
                style: TextStyle(
                  color: kPrimaryColor,
                  decoration: TextDecoration.underline,
                ),
              ),
              const Spacer(),
              CustomButton(
                onTap: () {},
                icon: Icons.add,
                title: 'Add new defaulter',
                color: Colors.red,
              ),
              const SizedBox(height: 10.0)
            ],
          ),
        ),
      ),
    );
  }
}
