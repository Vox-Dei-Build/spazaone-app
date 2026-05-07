import 'package:flutter/material.dart';

/// Shared confirm dialog used by transaction/sale edit + delete flows.
///
/// Replaces the previous pattern of unguarded destructive taps. Returns
/// `true` when the user confirms, `false` (or `null`) on dismiss/cancel —
/// callers should treat anything other than `true` as "do not proceed".
class ConfirmDialog {
  /// Shows a destructive confirmation (red confirm button). Use for delete
  /// or any action that mutates committed financial data.
  static Future<bool> showDestructive(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Delete',
    String cancelLabel = 'Cancel',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Shows a standard confirmation. Use for non-destructive but
  /// consequential commits (e.g. updating an existing sale or transaction).
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
