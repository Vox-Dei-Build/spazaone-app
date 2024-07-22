import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

class DeleteConfirmationDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const DeleteConfirmationDialog({Key? key, required this.onConfirm})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return AlertDialog(
      title: Text(
        'Delete Product',
        style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 2.5,
            fontWeight: FontWeight.w600),
      ),
      content: Text(
        'Are you sure you want to delete this product?',
        style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(
            'Cancel',
            style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
          ),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: Text(
            'Delete',
            style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
          ),
          onPressed: () {
            onConfirm();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
