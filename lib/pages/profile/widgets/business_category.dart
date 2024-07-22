import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';

import 'package:pasella/constants/constants.dart';
import '../../../models/common/app_model.dart';

class BusinessCategoryPage extends StatelessWidget {
  const BusinessCategoryPage({super.key});

  static const id = '/businessCategoryPage';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: 'Select Business Category'),
      body: SafeArea(
        child: Padding(
          padding: LayoutConstants.padding20Horizontal,
          child: Consumer<AppModel>(
            builder: (context, value, child) {
              return Column(
                children: [
                  GridView.builder(
                    itemCount: value.businessCategories.length,
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 1 / 1.4,
                    ),
                    itemBuilder: (context, index) {
                      final String imageName =
                          value.businessCategories[index][1];
                      final String title = value.businessCategories[index][0];
                      final bool isSelected =
                          value.businessCategories[index][2];

                      return GestureDetector(
                        onTap: () {
                          value.updateBusinessCategory(title);
                          Navigator.pop(context);
                        },
                        child: Column(
                          children: [
                            Container(
                              width: 60.0,
                              padding: const EdgeInsets.all(10.0),
                              decoration: BoxDecoration(
                                color: kHighLightColor,
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              child: Image.asset(
                                  'assets/images/business_categories/$imageName.png'),
                            ),
                            const SizedBox(height: 10.0),
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 13.0,
                                fontWeight: isSelected ? FontWeight.bold : null,
                                height: 1.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  )
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
