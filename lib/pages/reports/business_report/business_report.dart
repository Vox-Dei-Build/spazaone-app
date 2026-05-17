import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/models/reports/business_report_model.dart';
import 'package:pasella/pages/ledger/widgets/ledger_stream_builder_section.dart';
import 'package:pasella/pages/reports/business_report/view_model/business_report_view_model.dart';
import 'package:pasella/pages/reports/business_report/widgets/date_range_ledger_drilldown.dart';
import 'package:pasella/pages/sales/widgets/date_filter_bar.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/pages/reports/widgets/customer_names_display.dart';
import 'package:pasella/pages/reports/widgets/metric_tile.dart';
import 'package:pasella/shared/view_models/balance_summary_view_model.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

enum ReportView { summary, payLater }

class BusinessReportPage extends StatefulWidget {
  const BusinessReportPage({super.key});
  static const id = '/businessReportPage';

  @override
  _BusinessReportPageState createState() => _BusinessReportPageState();
}

class _BusinessReportPageState extends State<BusinessReportPage> {
  late BusinessReportViewModel businessReportViewModel;
  late BalanceSummaryViewModel balanceSummaryViewModel;
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _selectedDay;
  ReportView _selectedView = ReportView.summary;

  @override
  void initState() {
    super.initState();
    var currentUser = FirebaseAuth.instance.currentUser?.uid ?? '';

    BalanceSummaryProvider balanceSummaryProvider =
        Provider.of<BalanceSummaryProvider>(context, listen: false);
    balanceSummaryViewModel = BalanceSummaryViewModel(balanceSummaryProvider);

    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _selectedDay = _endDate;

    balanceSummaryViewModel.fetchBalanceSummaryWithRange(
        _startDate!, _endDate!);
    businessReportViewModel = BusinessReportViewModel(currentUser);
    businessReportViewModel.reportFutureNotifier.value = businessReportViewModel
        .fetchReportWithRange(DateTime(2000, 1, 1), _endDate!);
  }

  void _onDateSelected(DateTime selectedDay) {
    final startOfDay =
        DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    final endOfDay = DateTime(
        selectedDay.year, selectedDay.month, selectedDay.day, 23, 59, 59);

    setState(() {
      _selectedDay = selectedDay;
      _startDate = startOfDay;
      _endDate = endOfDay;
    });

    balanceSummaryViewModel.fetchBalanceSummaryWithRange(
        _startDate!, _endDate!);
  }

  void _onDateRangeSelected(DateTime start, DateTime end) {
    setState(() {
      _startDate = start;
      _endDate = end;
      _selectedDay = null;
    });

    balanceSummaryViewModel.fetchBalanceSummaryWithRange(start, end);
  }

  @override
  void dispose() {
    businessReportViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final balanceSummary = Provider.of<BalanceSummaryProvider>(context);
    var totalCustomers = balanceSummary.balanceSummary.totalCustomers;

    return Consumer<BalanceSummaryProvider>(
      builder: (context, balanceSummary, child) {
        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                          vertical: SizeConfig.heightMultiplier * 1),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          segmentedButtonTheme: SegmentedButtonThemeData(
                            style: ButtonStyle(
                              backgroundColor:
                                  MaterialStateProperty.resolveWith<Color?>(
                                (Set<MaterialState> states) {
                                  if (states.contains(MaterialState.selected)) {
                                    return Colors
                                        .green; // <-- Your active color
                                  }
                                  return Colors.white; // <-- Inactive bg
                                },
                              ),
                              foregroundColor:
                                  MaterialStateProperty.resolveWith<Color?>(
                                (Set<MaterialState> states) {
                                  if (states.contains(MaterialState.selected)) {
                                    return Colors
                                        .white; // Text/icon color for active
                                  }
                                  return Colors
                                      .black87; // Text/icon color for inactive
                                },
                              ),
                            ),
                          ),
                        ),
                        child: SegmentedButton<ReportView>(
                          segments: <ButtonSegment<ReportView>>[
                            ButtonSegment(
                              value: ReportView.summary,
                              label: Text(
                                'Date View',
                                style: TextStyle(
                                  fontSize: SizeConfig.textMultiplier * 1.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              icon: Icon(
                                Icons.receipt_long,
                                size: SizeConfig.textMultiplier * 1.5,
                              ),
                            ),
                            ButtonSegment(
                              value: ReportView.payLater,
                              label: Text('Summary',
                                  style: TextStyle(
                                    fontSize: SizeConfig.textMultiplier * 1.5,
                                    fontWeight: FontWeight.bold,
                                  )),
                              icon: Icon(Icons.payment,
                                  size: SizeConfig.textMultiplier * 1.5),
                            ),
                          ],
                          selected: <ReportView>{_selectedView},
                          onSelectionChanged: (Set<ReportView> newSelection) {
                            setState(() {
                              _selectedView = newSelection.first;
                            });
                          },
                        ),
                      ),
                    ),
                    if (_selectedView == ReportView.summary) ...[
                      DateFilterBar(
                        selectedDay: _selectedDay,
                        startDate: _startDate,
                        endDate: _endDate,
                        onDaySelect: (d) {
                          _onDateSelected(d);
                        },
                        onRangeSelect: (s, e) {
                          _onDateRangeSelected(s, e);
                        },
                      ),
                      SizedBox(height: SizeConfig.heightMultiplier * 2),
                      LedgerStreamBuilderSection(
                        startDate: _startDate,
                        endDate: _endDate,
                      ),
                      SizedBox(height: SizeConfig.heightMultiplier * 1),
                      // PAS-UX-06A: drill-down. The Net Balance card above
                      // is a single aggregate number; before this widget,
                      // merchants could not see which transactions or
                      // customers produced it. The list below is the
                      // verification surface — same query shape as the
                      // backend, with an explicit reconciliation line.
                      // Scoped to Date View only (Summary tab is
                      // deliberately untouched per PAS-UX-06A scope).
                      if (_startDate != null && _endDate != null)
                        DateRangeLedgerDrilldown(
                          startDate: _startDate!,
                          endDate: _endDate!,
                        ),
                      SizedBox(height: SizeConfig.heightMultiplier * 2),
                    ] else if (_selectedView == ReportView.payLater) ...[
                      Card(
                        elevation: 4,
                        child: ValueListenableBuilder<Future<Report>?>(
                          valueListenable:
                              businessReportViewModel.reportFutureNotifier,
                          builder: (context, future, child) {
                            return FutureBuilder<Report>(
                              future: future,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const CircularProgressIndicator();
                                } else if (snapshot.hasError) {
                                  print('Error: ${snapshot.error}');
                                  return Padding(
                                      padding:
                                          LayoutConstants.padding10Horizontal,
                                      child: Column(children: [
                                        Text(
                                            'Oops something is wrong, please check your network or refresh the page',
                                            style: TextStyle(
                                                fontSize:
                                                    SizeConfig.textMultiplier *
                                                        2.5))
                                      ]));
                                } else {
                                  Report report = snapshot.data!;
                                  // PAS-UX-06A: derive Owing Customers from
                                  // the actual list length so the headline
                                  // count and the rendered list cannot
                                  // disagree on screen.
                                  final int owingCount =
                                      report.customersWithNPAs.length;
                                  return Padding(
                                    padding: EdgeInsets.all(
                                        SizeConfig.imageSizeMultiplier * 4),
                                    child: Column(
                                      children: [
                                        MetricTile(
                                            context,
                                            'Total Owed',
                                            () async => CurrencyUtil.format(
                                                report.cashflowImpact),
                                            false),
                                        MetricTile(
                                          context,
                                          'Owing Customers',
                                          () async => owingCount,
                                          false,
                                        ),
                                        MetricTile(
                                          context,
                                          'Total No Customers',
                                          () async => totalCustomers,
                                          false,
                                        ),
                                        MetricTile(
                                          context,
                                          '% Who Owe You',
                                          () async {
                                            final total = totalCustomers ?? 0;
                                            if (total == 0) {
                                              return owingCount == 0
                                                  ? '0%'
                                                  : '—';
                                            }
                                            // PAS-UX-06A: clamp guards
                                            // against impossible percentages
                                            // when numerator (all-time NPAs)
                                            // and denominator (date-filtered
                                            // total customers) drift apart.
                                            final raw =
                                                (owingCount / total) * 100;
                                            final ratio = raw.clamp(0.0, 100.0);
                                            return '${ratio.toStringAsFixed(1)}%';
                                          },
                                          false,
                                        ),
                                        SizedBox(
                                            height:
                                                SizeConfig.heightMultiplier *
                                                    2),
                                        Text(
                                          'Customers ($owingCount)',
                                          style: TextStyle(
                                              fontSize:
                                                  SizeConfig.textMultiplier * 2,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        SizedBox(
                                            height:
                                                SizeConfig.heightMultiplier *
                                                    1.5),
                                        CustomersWithBadLoansTile(
                                          customersWithBadLoansFuture:
                                              Future.value(
                                                  report.customersWithNPAs),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                      SizedBox(height: SizeConfig.heightMultiplier * 2),
                    ]
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
