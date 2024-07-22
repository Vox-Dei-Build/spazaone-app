import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';

class SalesPeriodDropdown extends StatelessWidget {
  final SalesViewModel viewModel;

  SalesPeriodDropdown({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return DropdownButton<String>(
      value: viewModel.selectedPeriod,
      items: <String>['Today', 'Week', 'Month', 'Quarter', 'All Time']
          .map<DropdownMenuItem<String>>((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(
            value,
            style: TextStyle(fontSize: SizeConfig.textMultiplier * 2.5),
          ),
        );
      }).toList(),
      onChanged: (String? newValue) {
        if (newValue != null) {
          viewModel.updateSelectedPeriod(newValue);
        }
      },
    );
  }
}
