import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A compact, visible date control shared by customer activity and sales.
///
/// The current period is always readable. Common ranges and the custom picker
/// live in a labelled bottom sheet instead of an easy-to-miss overflow menu.
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
    final largeText = MediaQuery.textScalerOf(context).scale(14) >= 20;
    final summary = Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: .42),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.calendar_today_outlined,
            size: 19,
            color: colors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Showing',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                _label(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
    final changeAction = TextButton(
      onPressed: () => _showDateChoices(context),
      child: const Text('Change dates'),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('workspace-date-filter'),
        onTap: () => _showDateChoices(context),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: largeText
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    summary,
                    Align(
                        alignment: Alignment.centerRight, child: changeAction),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 8),
                    changeAction,
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _showDateChoices(BuildContext context) async {
    final selected = await showModalBottomSheet<_DateChoice>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose dates',
              style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
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
              onTap: () => Navigator.pop(sheetContext, _DateChoice.thisWeek),
            ),
            _DateChoiceRow(
              icon: Icons.calendar_month_outlined,
              label: 'This month',
              onTap: () => Navigator.pop(sheetContext, _DateChoice.thisMonth),
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
                onTap: () => Navigator.pop(sheetContext, _DateChoice.allTime),
              ),
          ],
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
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: lastSelectableDate,
          initialDateRange: startDate != null && endDate != null
              ? DateTimeRange(start: startDate!, end: endDate!)
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
      return '${format(startDate!)} – ${format(endDate!)}';
    }
    if (selectedDay != null) return format(selectedDay!);
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
