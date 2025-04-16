import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

class DeleteConfirmationDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const DeleteConfirmationDialog({Key? key, required this.onConfirm})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Delete Template',
          style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 2.2,
              fontWeight: FontWeight.bold)),
      content: Text('Are you sure you want to delete this template?',
          style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
      actions: [
        TextButton(
          child: Text('Cancel',
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          child: Text('Delete',
              style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 2, color: Colors.red)),
          onPressed: () {
            onConfirm();
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
