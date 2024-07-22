// icon_helper.dart
import 'package:flutter/material.dart';

Icon getIconForStatus(String status) {
  switch (status) {
    case 'pending':
      return Icon(Icons.hourglass_empty, color: Colors.orange);
    case 'processing':
      return Icon(Icons.autorenew, color: Colors.blue);
    case 'completed':
      return Icon(Icons.check_circle_outline, color: Colors.green);
    default:
      return Icon(Icons.error_outline, color: Colors.red);
  }
}
