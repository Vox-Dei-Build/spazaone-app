import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';

class ReportDateFilterBar extends StatelessWidget {
  final DateTime? selectedDay;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<DateTime> onDaySelect;
  final void Function(DateTime, DateTime) onRangeSelect;

  const ReportDateFilterBar({
    super.key,
    required this.selectedDay,
    required this.startDate,
    required this.endDate,
    required this.onDaySelect,
    required this.onRangeSelect,
  });

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final rangeLabel = _label();
    final hPad = SizeConfig.imageSizeMultiplier * 2.5;
    final vPad = SizeConfig.heightMultiplier * .9;

    return Card(
      elevation: 1.5,
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SizeConfig.imageSizeMultiplier * 3),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 16),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
            Expanded(
              child: Text(
                rangeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: SizeConfig.textMultiplier * 1.6,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.date_range, size: 18),
              onPressed: () async {
                final now = DateTime.now();
                final lastSelectableDate =
                    endDate != null && endDate!.isAfter(now) ? endDate! : now;
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: lastSelectableDate,
                  initialDateRange: (startDate != null && endDate != null)
                      ? DateTimeRange(start: startDate!, end: endDate!)
                      : null,
                );
                if (picked != null) {
                  onRangeSelect(
                    DateTime(picked.start.year, picked.start.month,
                        picked.start.day),
                    DateTime(picked.end.year, picked.end.month, picked.end.day),
                  );
                }
              },
              tooltip: 'Pick range',
            ),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 2.5),
            PopupMenuButton<_QuickRange>(
              tooltip: 'Quick ranges',
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _QuickRange.today,
                  child: Text('Today'),
                ),
                const PopupMenuItem(
                  value: _QuickRange.thisWeek,
                  child: Text('This Week'),
                ),
                const PopupMenuItem(
                  value: _QuickRange.thisMonth,
                  child: Text('This Month'),
                ),
                if (selectedDay != null ||
                    (startDate != null && endDate != null))
                  const PopupMenuItem(
                    value: _QuickRange.clear,
                    child: Text('Clear'),
                  ),
              ],
              onSelected: (v) {
                final now = DateTime.now();
                switch (v) {
                  case _QuickRange.today:
                    onDaySelect(DateTime(now.year, now.month, now.day));
                    break;
                  case _QuickRange.thisWeek:
                    final monday =
                        now.subtract(Duration(days: now.weekday - 1));
                    final start =
                        DateTime(monday.year, monday.month, monday.day);
                    final end = start.add(const Duration(days: 6));
                    onRangeSelect(start, end);
                    break;
                  case _QuickRange.thisMonth:
                    final start = DateTime(now.year, now.month, 1);
                    final end = DateTime(now.year, now.month + 1, 0);
                    onRangeSelect(start, end);
                    break;
                  case _QuickRange.clear:
                    onRangeSelect(DateTime(2020, 1, 1), DateTime.now());
                    break;
                }
              },
              position: PopupMenuPosition.under,
              child: const Icon(Icons.more_horiz, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  String _label() {
    String fmt(DateTime d) => DateFormat('dd MMM yyyy').format(d);
    if (startDate != null && endDate != null) {
      return '${fmt(startDate!)} — ${fmt(endDate!)}';
    }
    if (selectedDay != null) return fmt(selectedDay!);
    return 'All time';
  }
}

enum _QuickRange { today, thisWeek, thisMonth, clear }
