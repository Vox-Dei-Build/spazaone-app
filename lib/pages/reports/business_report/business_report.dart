import 'package:pasella/services/store_session.dart';
import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/utils/date_util.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/constants/constants.dart';
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

enum ReportView { activity, summary }

typedef CustomerActivityDrilldownBuilder = Widget Function(
  DateTime startDate,
  DateTime endDate,
  ValueChanged<bool>? onLoadingChanged,
);

class BusinessReportPage extends StatefulWidget {
  const BusinessReportPage({
    super.key,
    this.view = ReportView.activity,
  });
  static const id = '/businessReportPage';

  final ReportView view;

  @override
  State<BusinessReportPage> createState() => _BusinessReportPageState();
}

class _BusinessReportPageState extends State<BusinessReportPage> {
  late BusinessReportViewModel businessReportViewModel;
  late BalanceSummaryViewModel balanceSummaryViewModel;
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _selectedDay;
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
    _endDate = endOfCalendarDay(now);
    _selectedDay = _endDate;

    businessReportViewModel = BusinessReportViewModel(currentUser);
    if (widget.view == ReportView.activity) {
      balanceSummaryViewModel.fetchBalanceSummaryWithRange(
        _startDate!,
        _endDate!,
      );
    } else {
      businessReportViewModel.reportFutureNotifier.value =
          businessReportViewModel.fetchReportWithRange(
        DateTime(2000, 1, 1),
        _endDate!,
      );
      businessReportViewModel.fetchAllTimeTotalCustomers();
    }
  }

  void _onDateSelected(DateTime selectedDay) {
    final startOfDay = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
    );
    final endOfDay = endOfCalendarDay(selectedDay);

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
      _startDate = DateUtils.dateOnly(start);
      _endDate = endOfCalendarDay(end);
      _selectedDay = null;
      _isDateViewRowsLoading = true;
    });

    balanceSummaryViewModel.fetchBalanceSummaryWithRange(
        _startDate!, _endDate!);
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
                    if (widget.view == ReportView.activity) ...[
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
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(6, 12, 6, 16),
                          child: CustomerActivityRangeContent(
                            startDate: _startDate,
                            endDate: _endDate,
                            onLoadingChanged: _setDateViewRowsLoading,
                          ),
                        ),
                      ),
                    ] else ...[
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
                                      const Text(
                                        'Could not load the summary. Check your connection and try again.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 16,
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

/// Keeps the per-customer query behind an explicit date selection.
///
/// The all-time summary can be calculated by the aggregate backend endpoint,
/// but loading all customer ledgers would otherwise fan out into one Firestore
/// query per customer. Keeping the gate in this shared presentation component
/// makes the expensive drill-down impossible to mount with an open range.
class CustomerActivityRangeContent extends StatelessWidget {
  const CustomerActivityRangeContent({
    super.key,
    required this.startDate,
    required this.endDate,
    this.onLoadingChanged,
    this.drilldownBuilder,
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<bool>? onLoadingChanged;
  final CustomerActivityDrilldownBuilder? drilldownBuilder;

  @override
  Widget build(BuildContext context) {
    final start = startDate;
    final end = endDate;

    return Column(
      children: [
        const DateRangeMovementSummaryCard(),
        if (start != null && end != null)
          (drilldownBuilder ?? _buildDrilldown)(
            start,
            end,
            onLoadingChanged,
          ),
      ],
    );
  }

  static Widget _buildDrilldown(
    DateTime startDate,
    DateTime endDate,
    ValueChanged<bool>? onLoadingChanged,
  ) {
    return DateRangeLedgerDrilldown(
      startDate: startDate,
      endDate: endDate,
      showLoadingIndicator: false,
      onLoadingChanged: onLoadingChanged,
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
    final paidUpCount = totalCustomers == null
        ? null
        : (totalCustomers! - owingCount).clamp(0, totalCustomers!);

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: SpazaColors.successSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Customers owe you',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kPrimaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    CurrencyUtil.format(report.cashflowImpact.abs()),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: kTertiaryColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 30,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Across $owingCount customer ${owingCount == 1 ? 'account' : 'accounts'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kSecondaryAccent,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(
                  child: _InlineSummaryMetric(
                    label: 'Active customers',
                    value: totalCustomers?.toString() ?? '—',
                    color: kTertiaryColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InlineSummaryMetric(
                    label: 'Paid up',
                    value: paidUpCount?.toString() ?? '—',
                    color: kPrimaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Customers to follow up',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
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
                    borderRadius: BorderRadius.circular(SpazaRadius.surface),
                  ),
                  child: Text(
                    '$owingCount',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (owingCount == 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(SpazaRadius.control),
              ),
              child: const Column(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green),
                  SizedBox(height: 8),
                  Text(
                    'No outstanding customer balances',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w500),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .48),
        borderRadius: BorderRadius.circular(SpazaRadius.control),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: SpazaColors.muted,
            ),
          ),
        ],
      ),
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
