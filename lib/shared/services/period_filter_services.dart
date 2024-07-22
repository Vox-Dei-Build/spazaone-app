import 'package:flutter/foundation.dart';
import 'package:pasella/models/common/period_filter_model.dart';
import 'package:pasella/utils/date_util.dart';

class PeriodFilterService with ChangeNotifier {
  static final PeriodFilterService _instance = PeriodFilterService._internal();

  factory PeriodFilterService() {
    return _instance;
  }

  PeriodFilterService._internal() {
    // Initialization logic, if any.
  }

  TimePeriod _currentSelectedPeriod = TimePeriod.today;

  TimePeriod get currentSelectedPeriod => _currentSelectedPeriod;

  void resetPeriodFilter() {
    _currentSelectedPeriod = TimePeriod.today;
    notifyListeners();
  }

  void updatePeriodFilter(TimePeriod period) {
    if (_currentSelectedPeriod != period) {
      _currentSelectedPeriod = period;
      notifyListeners(); // Notify widgets about the change
    }
  }

  DateTime getStartDate() {
    return calculateStartDate(_currentSelectedPeriod);
  }
}
