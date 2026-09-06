import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/pages/stock/widgets/add_product_group_dialog.dart';

class AddProductGroupButton extends StatelessWidget {
  final StockViewModel viewModel;

  const AddProductGroupButton({Key? key, required this.viewModel})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FloatingActionButton.extended(
        elevation: 0,
        backgroundColor: SpazaColors.action,
        foregroundColor: Colors.white,
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
        icon: const Icon(
          Icons.add_outlined,
          color: Colors.white,
          size: 20, // Smaller icon
        ),
        label: const Text(
          'Create group',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
