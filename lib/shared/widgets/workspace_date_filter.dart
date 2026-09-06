import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/design/spaza_tokens.dart';

/// A visible date control shared by customer activity and recorded sales.
class WorkspaceDateFilter extends StatelessWidget {
  const WorkspaceDateFilter({
    super.key,
    required this.selectedDay,
    required this.startDate,
    required this.endDate,
    required this.onDaySelect,
    required this.onRangeSelect,
    required this.onClear,
    this.allowFutureEndDate = false,
  });

  final DateTime? selectedDay;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<DateTime> onDaySelect;
  final void Function(DateTime, DateTime) onRangeSelect;
  final VoidCallback onClear;
  final bool allowFutureEndDate;

  bool get _hasFilter =>
      selectedDay != null || (startDate != null && endDate != null);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Change date, ${_label()}',
      onTap: () => _showDateChoices(context),
      excludeSemantics: true,
      child: Tooltip(
        message: 'Change date',
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(SpazaRadius.control),
          child: InkWell(
            key: const ValueKey('workspace-date-filter'),
            onTap: () => _showDateChoices(context),
            borderRadius: BorderRadius.circular(SpazaRadius.control),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 18, color: kTertiaryColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _label(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: kTertiaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: colors.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDateChoices(BuildContext context) async {
    final selected = await showModalBottomSheet<_DateChoice>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            key: const ValueKey('workspace-date-choices-scroll'),
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose dates',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        color: kTertiaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 12),
                _DateChoiceRow(
                  icon: Icons.today_outlined,
                  label: 'Today',
                  onTap: () => Navigator.pop(sheetContext, _DateChoice.today),
                ),
                _DateChoiceRow(
                  icon: Icons.date_range_outlined,
                  label: 'This week',
                  onTap: () =>
                      Navigator.pop(sheetContext, _DateChoice.thisWeek),
                ),
                _DateChoiceRow(
                  icon: Icons.calendar_month_outlined,
                  label: 'This month',
                  onTap: () =>
                      Navigator.pop(sheetContext, _DateChoice.thisMonth),
                ),
                _DateChoiceRow(
                  icon: Icons.edit_calendar_outlined,
                  label: 'Choose a date range',
                  onTap: () => Navigator.pop(sheetContext, _DateChoice.custom),
                ),
                if (_hasFilter)
                  _DateChoiceRow(
                    icon: Icons.all_inclusive_rounded,
                    label: 'Show all time',
                    onTap: () =>
                        Navigator.pop(sheetContext, _DateChoice.allTime),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (selected == null || !context.mounted) return;
    final now = DateTime.now();
    switch (selected) {
      case _DateChoice.today:
        onDaySelect(DateTime(now.year, now.month, now.day));
      case _DateChoice.thisWeek:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        final start = DateTime(monday.year, monday.month, monday.day);
        onRangeSelect(start, start.add(const Duration(days: 6)));
      case _DateChoice.thisMonth:
        onRangeSelect(
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0),
        );
      case _DateChoice.custom:
        final lastSelectableDate =
            allowFutureEndDate && endDate != null && endDate!.isAfter(now)
                ? endDate!
                : now;
        // A week/month preset can include future days. Keep the picker
        // selection inside its bounds when the merchant refines that range.
        final firstSelectableDate = DateTime(2020);
        DateTime clampDate(DateTime date) => date.isBefore(firstSelectableDate)
            ? firstSelectableDate
            : date.isAfter(lastSelectableDate)
                ? lastSelectableDate
                : date;
        final picked = await showDateRangePicker(
          context: context,
          firstDate: firstSelectableDate,
          lastDate: lastSelectableDate,
          initialDateRange: startDate != null && endDate != null
              ? DateTimeRange(
                  start: clampDate(startDate!), end: clampDate(endDate!))
              : null,
        );
        if (picked != null) {
          onRangeSelect(
            DateTime(picked.start.year, picked.start.month, picked.start.day),
            DateTime(picked.end.year, picked.end.month, picked.end.day),
          );
        }
      case _DateChoice.allTime:
        onClear();
    }
  }

  String _label() {
    String format(DateTime date) => DateFormat('dd MMM yyyy').format(date);
    if (startDate != null && endDate != null) {
      if (startDate!.year == endDate!.year &&
          startDate!.month == endDate!.month &&
          startDate!.day == endDate!.day) {
        return format(startDate!);
      }
      if (startDate!.year == endDate!.year) {
        final startFormat =
            startDate!.month == endDate!.month ? 'dd' : 'dd MMM';
        return '${DateFormat(startFormat).format(startDate!)} – ${format(endDate!)}';
      }
      return '${format(startDate!)} – ${format(endDate!)}';
    }
    if (selectedDay != null) {
      final now = DateTime.now();
      if (DateUtils.isSameDay(selectedDay, now)) return 'Today';
      if (DateUtils.isSameDay(
          selectedDay, now.subtract(const Duration(days: 1)))) {
        return 'Yesterday';
      }
      return format(selectedDay!);
    }
    return 'All time';
  }
}

class _DateChoiceRow extends StatelessWidget {
  const _DateChoiceRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 12,
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

enum _DateChoice { today, thisWeek, thisMonth, custom, allTime }
