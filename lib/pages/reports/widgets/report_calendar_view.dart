import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:pasella/config/size_config.dart';

class ReportCalendarView extends StatefulWidget {
  final Function(DateTime) onDateSelected;
  final Function(DateTime, DateTime) onDateRangeSelected;
  final DateTime? selectedDay;
  final DateTime? startDate;
  final DateTime? endDate;
  final void Function(DateTime)? onInternalDateSelect;
  final void Function(DateTime, DateTime)? onInternalRangeSelect;

  /// Compact = week by default with small rows
  final bool compact;

  /// When true, user can expand to month (still safe—no overflow)
  final bool collapsible;

  /// Row height for each calendar row. 18–22 is very compact; 24–30 is comfy.
  final double rowHeight;

  const ReportCalendarView({
    super.key,
    required this.onDateSelected,
    required this.onDateRangeSelected,
    required this.selectedDay,
    required this.startDate,
    required this.endDate,
    this.onInternalDateSelect,
    this.onInternalRangeSelect,
    this.compact = true,
    this.collapsible = true,
    this.rowHeight = 20,
  });

  @override
  State<ReportCalendarView> createState() => _ReportCalendarViewState();
}

class _ReportCalendarViewState extends State<ReportCalendarView> {
  late DateTime _focusedDay;
  bool _expanded = false; // collapsed (week) by default when compact=true

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.selectedDay ?? DateTime.now();
  }

  Future<void> _pickCustomDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: (widget.startDate != null && widget.endDate != null)
          ? DateTimeRange(start: widget.startDate!, end: widget.endDate!)
          : null,
    );
    if (picked != null) {
      widget.onDateRangeSelected(picked.start, picked.end);
      widget.onInternalRangeSelect?.call(picked.start, picked.end);
      setState(() => _expanded = false); // collapse after picking a range
    }
  }

  void _quickToday() {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    widget.onDateSelected(day);
    widget.onInternalDateSelect?.call(day);
    setState(() {
      _focusedDay = day;
      _expanded = false;
    });
  }

  void _quickThisWeek() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(monday.year, monday.month, monday.day);
    final end = start.add(const Duration(days: 6));
    widget.onDateRangeSelected(start, end);
    widget.onInternalRangeSelect?.call(start, end);
    setState(() => _expanded = false);
  }

  void _quickThisMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0);
    widget.onDateRangeSelected(start, end);
    widget.onInternalRangeSelect?.call(start, end);
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final header = Row(
      children: [
        const Icon(Icons.calendar_today, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Filter by date',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: SizeConfig.textMultiplier * 2,
            ),
          ),
        ),
        if (widget.collapsible)
          IconButton(
            tooltip: _expanded ? 'Collapse' : 'Expand',
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          ),
        TextButton.icon(
          onPressed: () => _pickCustomDateRange(context),
          icon: const Icon(Icons.date_range),
          label: const Text('Range'),
        ),
      ],
    );

    final chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(onPressed: _quickToday, child: const Text('Today')),
        OutlinedButton(
            onPressed: _quickThisWeek, child: const Text('This Week')),
        OutlinedButton(
            onPressed: _quickThisMonth, child: const Text('This Month')),
      ],
    );

    final calendarFormat = (_expanded || !widget.compact)
        ? CalendarFormat.month
        : CalendarFormat.week;

    final cal = TableCalendar(
      firstDay: DateTime(2020, 1, 1),
      lastDay: DateTime.now(),
      focusedDay: _focusedDay,
      calendarFormat: calendarFormat,
      availableCalendarFormats: const {
        CalendarFormat.week: 'Week',
        CalendarFormat.month: 'Month',
      },
      rangeStartDay: widget.startDate,
      rangeEndDay: widget.endDate,
      rangeSelectionMode: RangeSelectionMode.toggledOn,
      selectedDayPredicate: (day) =>
          widget.selectedDay != null && isSameDay(widget.selectedDay!, day),
      headerStyle: const HeaderStyle(
        titleCentered: true,
        formatButtonVisible: false, // we handle expand manually
      ),
      calendarStyle: const CalendarStyle(
        selectedDecoration:
            BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
        todayDecoration:
            BoxDecoration(color: Colors.green, shape: BoxShape.circle),
        outsideDaysVisible: false,
      ),
      rowHeight: widget.rowHeight,
      onDaySelected: (selectedDay, focusedDay) {
        if (selectedDay.isAfter(DateTime.now())) return;
        setState(() => _focusedDay = selectedDay);
        widget.onDateSelected(selectedDay);
        widget.onInternalDateSelect?.call(selectedDay);
      },
      onPageChanged: (focusedDay) => _focusedDay = focusedDay,
    );

    // How many calendar rows we expect to show (1 in week, up to ~6 in month)
    final rows = (calendarFormat == CalendarFormat.month) ? 6 : 1;

    // Height for the entire widget (header + chips + calendar).
    // Tweak the constant if your theme has different paddings.
    final totalHeight = (rows * widget.rowHeight) + 200;

    return SizedBox(
      // A firm, predictable height: never lets this section overflow its parent Column.
      height: totalHeight.clamp(140.0, 460.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          child: SingleChildScrollView(
            // If internal content *momentarily* grows (small phones / large text scale),
            // it scrolls here instead of overflowing the parent layout.
            physics: const ClampingScrollPhysics(),
            child: Card(
              elevation: 2,
              clipBehavior:
                  Clip.hardEdge, // safety for tiny overpaints during animation
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: SizeConfig.heightMultiplier * 1,
                  horizontal: SizeConfig.imageSizeMultiplier * 2,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min, // don’t over-claim height
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 8),
                    chips,
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: cal,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
