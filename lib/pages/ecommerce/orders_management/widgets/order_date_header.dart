// PAS-UX-14: date-bucket header rendered above each cluster of orders
// in the redesigned Customer Orders list.
//
// Mirrors the visual language already used by the redesigned Pay Later
// transactions list (`TransactionDate` widget) — a centered, subtle
// pill chip with a humanised label (Today / Yesterday / weekday for
// the past week / short date otherwise). Keeping the two tabs visually
// in sync makes the AppBar's tab switch feel like a continuation of
// the same surface rather than two unrelated screens.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';

class OrderDateHeader extends StatelessWidget {
  const OrderDateHeader({super.key, required this.date});

  /// Local midnight of the bucket day. Pass `DateTime(0)` (epoch) to
  /// render the synthetic "Unknown" header for orders missing a
  /// `createdAt`.
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 1.4,
      ),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 3,
            vertical: SizeConfig.heightMultiplier * 0.55,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFE6EBEE),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _humanize(date),
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.35,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF4B5563),
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  static String _humanize(DateTime d) {
    if (d.millisecondsSinceEpoch == 0) return 'No date';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final delta = today.difference(d).inDays;
    if (delta == 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    if (delta > 1 && delta < 7) return DateFormat('EEEE').format(d);
    if (d.year == now.year) return DateFormat('EEE d MMM').format(d);
    return DateFormat('d MMM y').format(d);
  }
}
