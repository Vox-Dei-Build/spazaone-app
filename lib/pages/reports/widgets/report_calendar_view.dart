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

  const ReportCalendarView(
      {super.key,
      required this.onDateSelected,
      required this.onDateRangeSelected,
      required this.selectedDay,
      required this.startDate,
      required this.endDate,
      this.onInternalDateSelect,
      this.onInternalRangeSelect});

  @override
  _SalesCalendarViewState createState() => _SalesCalendarViewState();
}

class _SalesCalendarViewState extends State<ReportCalendarView> {
  late DateTime _focusedDay;
  CalendarFormat _calendarFormat = CalendarFormat.week;

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.selectedDay ?? DateTime.now();
  }

  Future<void> _pickCustomDateRange(BuildContext context) async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: widget.startDate != null && widget.endDate != null
          ? DateTimeRange(start: widget.startDate!, end: widget.endDate!)
          : null,
    );

    if (picked != null) {
      widget.onDateRangeSelected(picked.start, picked.end); // updates UI state
      widget.onInternalRangeSelect
          ?.call(picked.start, picked.end); // triggers model update
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Column(
      children: [
        // Calendar
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: SizeConfig.heightMultiplier * 1,
              horizontal: SizeConfig.imageSizeMultiplier * 2,
            ),
            child: Column(
              children: [
                TableCalendar(
                  firstDay: DateTime(2020, 1, 1),
                  lastDay: DateTime.now(),
                  focusedDay: _focusedDay,
                  rangeStartDay: widget.startDate,
                  rangeEndDay: widget.endDate,
                  rangeSelectionMode: RangeSelectionMode.toggledOn,
                  selectedDayPredicate: (day) =>
                      widget.selectedDay != null &&
                      isSameDay(widget.selectedDay!, day),
                  calendarFormat: _calendarFormat,
                  availableCalendarFormats: const {
                    CalendarFormat.week: 'Week',
                    CalendarFormat.month: 'Month'
                  },
                  headerStyle: const HeaderStyle(
                    formatButtonShowsNext: false,
                    formatButtonVisible: true,
                    titleCentered: true,
                  ),
                  calendarStyle: const CalendarStyle(
                    selectedDecoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    todayDecoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    outsideDaysVisible: false,
                  ),
                  onDaySelected: (selectedDay, focusedDay) {
                    if (selectedDay.isAfter(DateTime.now())) return;
                    setState(() {
                      _focusedDay = selectedDay;
                    });
                    widget.onDateSelected(selectedDay);
                    widget.onInternalDateSelect?.call(selectedDay);
                  },
                  onFormatChanged: (format) {
                    setState(() {
                      _calendarFormat = format;
                    });
                  },
                ),
              ],
            ),
          ),
        ),

        // Custom Date Range Selection Button
        Padding(
          padding: EdgeInsets.only(top: SizeConfig.heightMultiplier * 0),
          child: ElevatedButton(
            onPressed: () => _pickCustomDateRange(context),
            child: Text("Select Date Range",
                style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
          ),
        ),
      ],
    );
  }
}
