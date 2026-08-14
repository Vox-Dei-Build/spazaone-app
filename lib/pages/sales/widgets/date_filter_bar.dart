import 'package:flutter/material.dart';
import 'package:pasella/shared/widgets/workspace_date_filter.dart';

class DateFilterBar extends StatelessWidget {
  final DateTime? selectedDay;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<DateTime> onDaySelect;
  final void Function(DateTime, DateTime) onRangeSelect;
  final VoidCallback onClear;

  const DateFilterBar({
    super.key,
    required this.selectedDay,
    required this.startDate,
    required this.endDate,
    required this.onDaySelect,
    required this.onRangeSelect,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return WorkspaceDateFilter(
      selectedDay: selectedDay,
      startDate: startDate,
      endDate: endDate,
      onDaySelect: onDaySelect,
      onRangeSelect: onRangeSelect,
      onClear: onClear,
    );
  }
}
