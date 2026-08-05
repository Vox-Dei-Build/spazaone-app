import 'package:pasella/services/store_session.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/models/reports/business_report_model.dart';
import 'package:pasella/pages/reports/business_report/view_model/business_report_view_model.dart';
import 'package:pasella/pages/reports/business_report/widgets/date_range_ledger_drilldown.dart';
import 'package:pasella/pages/reports/business_report/widgets/date_range_movement_summary_card.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/pages/reports/widgets/customer_names_display.dart';
import 'package:pasella/pages/reports/widgets/report_date_filter_bar.dart';
import 'package:pasella/shared/view_models/balance_summary_view_model.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

enum ReportView { summary, payLater }

class BusinessReportPage extends StatefulWidget {
  const BusinessReportPage({super.key});
  static const id = '/businessReportPage';

  @override
  State<BusinessReportPage> createState() => _BusinessReportPageState();
}

class _BusinessReportPageState extends State<BusinessReportPage> {
  late BusinessReportViewModel businessReportViewModel;
  late BalanceSummaryViewModel balanceSummaryViewModel;
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _selectedDay;
  ReportView _selectedView = ReportView.summary;
  bool _isDateViewRowsLoading = true;

  @override
  void initState() {
    super.initState();
    var currentUser = StoreSession.instance.storeId;

    BalanceSummaryProvider balanceSummaryProvider =
        Provider.of<BalanceSummaryProvider>(context, listen: false);
    balanceSummaryViewModel = BalanceSummaryViewModel(balanceSummaryProvider);

    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _selectedDay = _endDate;

    balanceSummaryViewModel.fetchBalanceSummaryWithRange(
      _startDate!,
      _endDate!,
    );
    businessReportViewModel = BusinessReportViewModel(currentUser);
    businessReportViewModel.reportFutureNotifier.value = businessReportViewModel
        .fetchReportWithRange(DateTime(2000, 1, 1), _endDate!);
    businessReportViewModel.fetchAllTimeTotalCustomers();
  }

  void _onDateSelected(DateTime selectedDay) {
    final startOfDay = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
    );
    final endOfDay = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
      23,
      59,
      59,
    );

    setState(() {
      _selectedDay = selectedDay;
      _startDate = startOfDay;
      _endDate = endOfDay;
      _isDateViewRowsLoading = true;
    });

    balanceSummaryViewModel.fetchBalanceSummaryWithRange(
      _startDate!,
      _endDate!,
    );
  }

  void _onDateRangeSelected(DateTime start, DateTime end) {
    setState(() {
      _startDate = start;
      _endDate = end;
      _selectedDay = null;
      _isDateViewRowsLoading = true;
    });

    balanceSummaryViewModel.fetchBalanceSummaryWithRange(start, end);
  }

  void _clearDateFilter() {
    final now = DateTime.now();
    setState(() {
      _startDate = null;
      _endDate = null;
      _selectedDay = null;
      _isDateViewRowsLoading = false;
    });
    balanceSummaryViewModel.fetchBalanceSummaryWithRange(DateTime(2000), now);
  }

  void _retrySummary() {
    final end = _endDate ?? DateTime.now();
    businessReportViewModel.reportFutureNotifier.value =
        businessReportViewModel.fetchReportWithRange(DateTime(2000), end);
    businessReportViewModel.fetchAllTimeTotalCustomers();
  }

  void _setDateViewRowsLoading(bool isLoading) {
    if (!mounted || _isDateViewRowsLoading == isLoading) return;
    setState(() {
      _isDateViewRowsLoading = isLoading;
    });
  }

  @override
  void dispose() {
    businessReportViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Consumer<BalanceSummaryProvider>(
      builder: (context, balanceSummary, child) {
        final hasDateRange = _startDate != null && _endDate != null;
        final isDateViewLoading = balanceSummary.isLedgerLoading ||
            (hasDateRange && _isDateViewRowsLoading);

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
                        vertical: SizeConfig.heightMultiplier * 1,
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          segmentedButtonTheme: SegmentedButtonThemeData(
                            style: ButtonStyle(
                              backgroundColor:
                                  WidgetStateProperty.resolveWith<Color?>(
                                      (Set<WidgetState> states) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.green; // <-- Your active color
                                }
                                return Colors.white; // <-- Inactive bg
                              }),
                              foregroundColor:
                                  WidgetStateProperty.resolveWith<Color?>(
                                      (Set<WidgetState> states) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors
                                      .white; // Text/icon color for active
                                }
                                return Colors
                                    .black87; // Text/icon color for inactive
                              }),
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
                              label: Text(
                                'Summary',
                                style: TextStyle(
                                  fontSize: SizeConfig.textMultiplier * 1.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              icon: Icon(
                                Icons.payment,
                                size: SizeConfig.textMultiplier * 1.5,
                              ),
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
                      ReportDateFilterBar(
                        selectedDay: _selectedDay,
                        startDate: _startDate,
                        endDate: _endDate,
                        onDaySelect: (d) {
                          _onDateSelected(d);
                        },
                        onRangeSelect: (s, e) {
                          _onDateRangeSelected(s, e);
                        },
                        onClear: _clearDateFilter,
                      ),
                      if (isDateViewLoading)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: SizeConfig.heightMultiplier * 5,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      Offstage(
                        offstage: isDateViewLoading,
                        child: Column(
                          children: [
                            SizedBox(height: SizeConfig.heightMultiplier * 2),
                            const DateRangeMovementSummaryCard(),
                            SizedBox(height: SizeConfig.heightMultiplier * 1),
                            // PAS-UX-06A: drill-down. The Net Movement card
                            // above is a single aggregate number; before this
                            // widget, merchants could not see which
                            // transactions or customers produced it. The list
                            // below is the verification surface — same query
                            // shape as the backend, with an explicit
                            // reconciliation line.
                            // Scoped to Date View only (Summary tab is
                            // deliberately untouched per PAS-UX-06A scope).
                            if (hasDateRange)
                              DateRangeLedgerDrilldown(
                                startDate: _startDate!,
                                endDate: _endDate!,
                                showLoadingIndicator: false,
                                onLoadingChanged: _setDateViewRowsLoading,
                              ),
                            SizedBox(height: SizeConfig.heightMultiplier * 2),
                          ],
                        ),
                      ),
                    ] else if (_selectedView == ReportView.payLater) ...[
                      ValueListenableBuilder<Future<Report>?>(
                        valueListenable:
                            businessReportViewModel.reportFutureNotifier,
                        builder: (context, future, child) {
                          if (future == null) {
                            return const _ReportSectionLoader();
                          }
                          return FutureBuilder<Report>(
                            future: future,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const _ReportSectionLoader();
                              } else if (snapshot.hasError) {
                                debugPrint('Error: ${snapshot.error}');
                                return Padding(
                                  padding: LayoutConstants.padding10Horizontal,
                                  child: Column(
                                    children: [
                                      const Icon(
                                        Icons.cloud_off_outlined,
                                        size: 40,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Could not load the summary. Check your connection and try again.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize:
                                              SizeConfig.textMultiplier * 1.8,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                        onPressed: _retrySummary,
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Try again'),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                return ValueListenableBuilder<int?>(
                                  valueListenable: businessReportViewModel
                                      .allTimeTotalCustomersNotifier,
                                  builder: (context, totalCustomers, _) {
                                    return CustomerBalanceSummary(
                                      report: snapshot.data!,
                                      totalCustomers: totalCustomers,
                                    );
                                  },
                                );
                              }
                            },
                          );
                        },
                      ),
                      SizedBox(height: SizeConfig.heightMultiplier * 2),
                    ],
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

class CustomerBalanceSummary extends StatelessWidget {
  const CustomerBalanceSummary({
    super.key,
    required this.report,
    required this.totalCustomers,
  });

  final Report report;
  final int? totalCustomers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final owingCount = report.customersWithNPAs.length;
    final ratio = totalCustomers == null || totalCustomers == 0
        ? null
        : ((owingCount / totalCustomers!) * 100).clamp(0.0, 100.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8ECE8)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_outlined,
                        color: primary,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Outstanding balance',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              CurrencyUtil.format(
                                report.cashflowImpact.abs(),
                              ),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: primary,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1, color: Color(0xFFEDEFEA)),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _InlineSummaryMetric(
                        label: 'Owing',
                        value: '$owingCount',
                        color: Colors.orange.shade800,
                      ),
                    ),
                    const _SummaryDivider(),
                    Expanded(
                      child: _InlineSummaryMetric(
                        label: 'Customers',
                        value: totalCustomers?.toString() ?? '—',
                        color: Colors.blueGrey.shade700,
                      ),
                    ),
                    const _SummaryDivider(),
                    Expanded(
                      child: _InlineSummaryMetric(
                        label: 'Owing rate',
                        value: ratio == null
                            ? '—'
                            : '${ratio.toStringAsFixed(0)}%',
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Customers to follow up',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (owingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$owingCount',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (owingCount == 0)
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green),
                  SizedBox(height: 8),
                  Text(
                    'No outstanding customer balances',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            )
          else
            CustomersWithBadLoansTile(
              customersWithBadLoansFuture: Future.value(
                report.customersWithNPAs,
              ),
            ),
        ],
      ),
    );
  }
}

class _InlineSummaryMetric extends StatelessWidget {
  const _InlineSummaryMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38,
      color: Colors.grey.shade200,
    );
  }
}

class _ReportSectionLoader extends StatelessWidget {
  const _ReportSectionLoader();

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return SizedBox(
      width: double.infinity,
      height: SizeConfig.heightMultiplier * 18,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}
