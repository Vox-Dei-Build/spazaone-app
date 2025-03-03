import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:provider/provider.dart';

class LedgerTabBarWithFilter extends StatelessWidget {
  final ValueNotifier<int> tabIndexNotifier;

  const LedgerTabBarWithFilter({Key? key, required this.tabIndexNotifier})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Column(
      children: [
        TabBar(
          onTap: (index) {
            tabIndexNotifier.value = index;
          },
          labelStyle: TextStyle(
            fontSize: SizeConfig.textMultiplier * 1.8,
            fontWeight: FontWeight.normal,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: SizeConfig.textMultiplier *
                1.8, // Font size for unselected tabs
            fontWeight: FontWeight.normal, // Font weight for unselected tabs
          ),
          tabs: context.read<AppModel>().tabs,
        ),
      ],
    );
  }
}
