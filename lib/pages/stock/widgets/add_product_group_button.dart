import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/pages/stock/widgets/add_product_group_dialog.dart';

class AddProductGroupButton extends StatelessWidget {
  final StockViewModel viewModel;

  const AddProductGroupButton({Key? key, required this.viewModel})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      elevation: 3.0,
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) {
            return AddProductGroupDialog(
              viewModel: viewModel,
            );
          },
        );
      },
      icon: Icon(
        Icons.add_outlined,
        color: Colors.white,
        size: SizeConfig.heightMultiplier * 3, // Smaller icon
      ),
      label: Text(
        'Create Group',
        style: TextStyle(
          color: Colors.white,
          fontSize: SizeConfig.textMultiplier * 2.5, // Adjust font size
        ),
      ),
    );
  }
}
