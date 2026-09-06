import 'package:flutter/material.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/profile/widgets/business_choice_list.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';

class BusinessTypePage extends StatelessWidget {
  const BusinessTypePage({super.key});
  static const id = '/businessTypePage';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const CustomAppBar(title: 'Business type'),
        body: SafeArea(
          child: Consumer<AppModel>(builder: (context, model, _) {
            return BusinessChoiceList(
              choices: model.businessTypes,
              assetFolder: 'assets/images/business_types',
              onSelected: (title) {
                model.updateBusinessType(title);
                Navigator.pop(context);
              },
            );
          }),
        ),
      );
}
