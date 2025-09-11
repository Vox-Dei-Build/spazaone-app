import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Ensures a permission is granted. If denied after request,
/// shows a dialog prompting the user to open app settings.
/// Returns true if granted, false otherwise.
Future<bool> ensurePermission(
  BuildContext context,
  Permission permission, {
  required String title,
  required String message,
  String settingsButtonText = 'Open Settings',
  String cancelButtonText = 'Not Now',
}) async {
  var status = await permission.status;

  if (!status.isGranted) {
    status = await permission.request();
  }

  if (status.isGranted) return true;

  // Show prompt guiding the user to enable the permission in Settings
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(cancelButtonText),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            await openAppSettings();
          },
          child: Text(settingsButtonText),
        ),
      ],
    ),
  );

  return false;
}

