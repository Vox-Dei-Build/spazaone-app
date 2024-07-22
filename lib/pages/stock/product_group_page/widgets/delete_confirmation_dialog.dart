import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';

class DeleteConfirmationDialog extends StatelessWidget {
  final String name;
  final StockViewModel viewModel;

  const DeleteConfirmationDialog({
    Key? key,
    required this.name,
    required this.viewModel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete Product Group'),
      content:
          const Text('Are you sure you want to delete this product group?'),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: const Text('Delete Products'),
          onPressed: () async {
            await viewModel.deleteProductGroup(name);
            Navigator.of(context).pop();
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: const Text('Move to "Uncategorized" Group'),
          onPressed: () async {
            await viewModel.moveProductsToAnotherGroup(name, 'Uncategorized');
            await viewModel.deleteProductGroup(name);
            SchedulerBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            });
          },
        ),
      ],
    );
  }
}
