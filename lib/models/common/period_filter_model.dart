enum TimePeriod { today, weekly, monthly, quarter, allTime }

extension TimePeriodExtension on TimePeriod {
  String get name {
    switch (this) {
      case TimePeriod.today:
        return 'Day';
      case TimePeriod.weekly:
        return 'Week';
      case TimePeriod.monthly:
        return 'Month';
      case TimePeriod.quarter:
        return 'QTR';
      default:
        return 'All';
    }
  }
}
