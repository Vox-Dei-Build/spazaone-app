import 'package:flutter/material.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/profile/widgets/business_choice_list.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';

class BusinessCategoryPage extends StatelessWidget {
  const BusinessCategoryPage({super.key});
  static const id = '/businessCategoryPage';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const CustomAppBar(title: 'Business category'),
        body: SafeArea(
          child: Consumer<AppModel>(builder: (context, model, _) {
            return BusinessChoiceList(
              choices: model.businessCategories,
              assetFolder: 'assets/images/business_categories',
              onSelected: (title) {
                model.updateBusinessCategory(title);
                Navigator.pop(context);
              },
            );
          }),
        ),
      );
}
