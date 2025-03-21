import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

Icon getIconForStatus(String status) {
  double iconSize =
      SizeConfig.imageSizeMultiplier * 5; // Adjust multiplier as needed

  switch (status) {
    // ✅ Withdrawal Statuses
    case 'pending':
      return Icon(Icons.hourglass_empty, color: Colors.orange, size: iconSize);
    case 'processing':
      return Icon(Icons.autorenew, color: Colors.blue, size: iconSize);
    case 'completed':
      return Icon(Icons.check_circle_outline,
          color: Colors.green, size: iconSize);
    case 'rejected':
      return Icon(Icons.cancel_outlined, color: Colors.red, size: iconSize);
    case 'failed':
      return Icon(Icons.warning_amber_outlined,
          color: Colors.deepOrange, size: iconSize);

    // ✅ Repayment Statuses
    case 'paid':
      return Icon(Icons.verified, color: Colors.green, size: iconSize);
    case 'overdue':
      return Icon(Icons.error_outline, color: Colors.redAccent, size: iconSize);
    case 'suspended':
      return Icon(Icons.lock_outline, color: Colors.black, size: iconSize);

    default:
      return Icon(Icons.help_outline, color: Colors.grey, size: iconSize);
  }
}
