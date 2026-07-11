import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/reports/business_report/view_model/business_report_view_model.dart';

void main() {
  test('customer report derives owing customers from negative balances', () {
    final report = BusinessReportViewModel.normalizeCashflowReport({
      'totalNumberofNPAs': 4,
      'nplRatio': 80,
      'cashflowImpact': -350,
      'customersWithNPAs': [
        {'id': 'owes', 'name': 'Owing customer', 'balance': -100},
        {'id': 'paid', 'name': 'Paid customer', 'balance': 0, 'isNPA': true},
        {'id': 'ahead', 'name': 'Ahead customer', 'balance': 50, 'isNPA': true},
        {'id': 'missing', 'name': 'Missing balance', 'isNPA': true},
      ],
    });

    expect(report.totalNumberofNPAs, 1);
    expect(report.customersWithNPAs, hasLength(1));
    expect(report.customersWithNPAs.single['id'], 'owes');
    expect(report.cashflowImpact, -100);
  });

  test('customer report accepts numeric balance strings safely', () {
    final report = BusinessReportViewModel.normalizeCashflowReport({
      'nplRatio': 0,
      'customersWithNPAs': [
        {'id': 'owes', 'balance': '-42.50'},
        {'id': 'settled', 'balance': '0'},
      ],
    });

    expect(report.totalNumberofNPAs, 1);
    expect(report.cashflowImpact, -42.5);
  });
}
