import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

/// A reusable confirmation dialog.
///
/// Provides customizable title, message, and action labels.
class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final Color confirmColor;

  const ConfirmationDialog({
    Key? key,
    required this.title,
    required this.message,
    required this.onConfirm,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.confirmColor = Colors.red,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        title,
        style: TextStyle(
          fontSize: SizeConfig.textMultiplier * 2.2,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Text(
        message,
        style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
      ),
      actions: [
        TextButton(
          child: Text(
            cancelLabel,
            style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          child: Text(
            confirmLabel,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 2,
              color: confirmColor,
            ),
          ),
          onPressed: () {
            Navigator.pop(context);
            onConfirm();
          },
        ),
      ],
    );
  }
}
