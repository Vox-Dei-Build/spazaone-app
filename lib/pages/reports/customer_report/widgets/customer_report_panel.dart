// PAS-UX-06A (scope expansion, ack'd by user): per-customer mini-report.
//
// Drops in above the transactions list on the customer profile. Renders
// metrics derived entirely from the transactions list already streamed by
// CustomerManagementViewModel — no extra Firestore reads, no new model
// fields, no new cloud functions. The goal is "ledger truth at the
// customer level": every number shown here can be re-derived by hand from
// the visible transaction lines.
//
// Collapsed by default so the existing profile experience is unchanged
// for merchants who don't need it; expands to a single card with five
// trust-building metrics.

import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/transaction_util.dart';

class CustomerReportPanel extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;

  const CustomerReportPanel({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    if (transactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final stats = _CustomerReportStats.from(transactions);

    return Card(
      elevation: 1,
      margin: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 0.5,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          SizeConfig.heightMultiplier * 1,
        ),
      ),
      child: Theme(
        // ExpansionTile draws its own divider lines that fight the Card
        // border at small sizes; suppress them for a cleaner look.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 3,
            vertical: SizeConfig.heightMultiplier * 0.2,
          ),
          childrenPadding: EdgeInsets.only(
            left: SizeConfig.imageSizeMultiplier * 3,
            right: SizeConfig.imageSizeMultiplier * 3,
            bottom: SizeConfig.heightMultiplier * 1.5,
          ),
          leading: Icon(
            Icons.insights_outlined,
            color: kPrimaryColor,
            size: SizeConfig.imageSizeMultiplier * 5,
          ),
          title: Text(
            'Customer report',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: SizeConfig.textMultiplier * 1.8,
            ),
          ),
          subtitle: Text(
            _summarySubtitle(stats),
            style: TextStyle(
              color: Colors.black54,
              fontSize: SizeConfig.textMultiplier * 1.4,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            _MetricRow(
              icon: Icons.history,
              iconColor: Colors.black54,
              label: 'Customer since',
              value: stats.relationshipAgeLabel,
            ),
            _MetricRow(
              icon: Icons.schedule,
              iconColor:
                  stats.lastActivityIsStale ? Colors.orange : Colors.black54,
              label: 'Last activity',
              value: stats.lastActivityLabel,
              valueColor: stats.lastActivityIsStale ? Colors.orange : null,
            ),
            const Divider(height: 16),
            _MetricRow(
              icon: Icons.credit_card,
              iconColor: Colors.red,
              label: 'Total credited (${stats.creditCount})',
              value: CurrencyUtil.format(stats.creditAmount),
              valueColor: Colors.red,
            ),
            _MetricRow(
              icon: Icons.payments,
              iconColor: Colors.green,
              label: 'Total paid (${stats.paymentCount})',
              value: CurrencyUtil.format(stats.paymentAmount),
              valueColor: Colors.green,
            ),
            const Divider(height: 16),
            _MetricRow(
              icon: Icons.timer_outlined,
              iconColor: Colors.black54,
              label: 'Avg. days to repay',
              value: stats.avgRepaymentDaysLabel,
            ),
            _MetricRow(
              icon: Icons.account_balance_wallet,
              iconColor: stats.netBalance < 0 ? Colors.red : Colors.green,
              label: 'Net balance',
              value: CurrencyUtil.format(stats.netBalance),
              valueColor: stats.netBalance < 0 ? Colors.red : Colors.green,
              isBold: true,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 0.5),
            // PAS-UX-06A: honest provenance line. The ledger-truth lane
            // exists because merchants couldn't tell where numbers came
            // from; saying it out loud is cheap and earns trust.
            Text(
              'Derived from ${transactions.length} '
              'transaction${transactions.length == 1 ? '' : 's'} below.',
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.2,
                color: Colors.black45,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _summarySubtitle(_CustomerReportStats stats) {
    final parts = <String>[
      '${transactions.length} txns',
      stats.lastActivityLabel,
    ];
    if (stats.avgRepaymentDays != null) {
      parts.add('avg ${stats.avgRepaymentDays} day repay');
    }
    return parts.join(' • ');
  }
}

class _MetricRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;

  const _MetricRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 0.4,
      ),
      child: Row(
        children: [
          Icon(icon,
              color: iconColor, size: SizeConfig.imageSizeMultiplier * 4),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.6,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.6,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pure-Dart aggregator. No widget dependencies — kept here (rather than
/// `transaction_util.dart`) because the metrics it produces are
/// presentation-shaped (e.g. "Customer since 3 months ago") rather than
/// part of the canonical balance math. If a second surface needs the
/// same numbers later, move this into `lib/utils/`.
class _CustomerReportStats {
  final int creditCount;
  final double creditAmount;
  final int paymentCount;
  final double paymentAmount;
  final double netBalance;
  final DateTime? firstActivity;
  final DateTime? lastActivity;
  final int? avgRepaymentDays;

  _CustomerReportStats({
    required this.creditCount,
    required this.creditAmount,
    required this.paymentCount,
    required this.paymentAmount,
    required this.netBalance,
    required this.firstActivity,
    required this.lastActivity,
    required this.avgRepaymentDays,
  });

  factory _CustomerReportStats.from(List<Map<String, dynamic>> txns) {
    final txStats = TransactionService.calculateCustomerTransactionStats(txns);
    final net = TransactionService.calculateBalance(txns);

    DateTime? first;
    DateTime? last;
    // Walk chronologically for repayment-time estimation.
    final dated = <_DatedTx>[];
    for (final t in txns) {
      final raw = t['date'];
      DateTime? when;
      if (raw is String && raw.isNotEmpty) {
        when = DateTime.tryParse(raw);
      } else if (raw is DateTime) {
        when = raw;
      }
      if (when == null) continue;
      first = first == null || when.isBefore(first) ? when : first;
      last = last == null || when.isAfter(last) ? when : last;
      dated.add(_DatedTx(
        when: when,
        type: (t['type'] as String?) ?? '',
        amount: (t['amount'] as num?)?.toDouble() ?? 0.0,
      ));
    }
    dated.sort((a, b) => a.when.compareTo(b.when));

    // Approximate "days to repay": for each credit, find the first
    // subsequent payment of any amount and record the gap. This is a
    // deliberately simple heuristic — it's right often enough to be
    // useful, and the provenance line tells the merchant where it
    // came from. A FIFO-matching version is a follow-up.
    final gaps = <int>[];
    for (var i = 0; i < dated.length; i++) {
      if (dated[i].type != 'Credit') continue;
      for (var j = i + 1; j < dated.length; j++) {
        if (dated[j].type == 'Payment') {
          gaps.add(dated[j].when.difference(dated[i].when).inDays);
          break;
        }
      }
    }
    int? avg;
    if (gaps.isNotEmpty) {
      avg = (gaps.reduce((a, b) => a + b) / gaps.length).round();
    }

    return _CustomerReportStats(
      creditCount: txStats.creditCount,
      creditAmount: txStats.creditAmount,
      paymentCount: txStats.paymentCount,
      paymentAmount: txStats.paymentAmount,
      netBalance: net,
      firstActivity: first,
      lastActivity: last,
      avgRepaymentDays: avg,
    );
  }

  String get relationshipAgeLabel {
    if (firstActivity == null) return '—';
    return _humanizeAge(firstActivity!);
  }

  String get lastActivityLabel {
    if (lastActivity == null) return '—';
    final days = DateTime.now().difference(lastActivity!).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 30) return '$days days ago';
    if (days < 365) return '${(days / 30).round()} months ago';
    return '${(days / 365).round()} years ago';
  }

  /// Stale = no activity in 60+ days on a customer with a non-zero net
  /// balance. Drives the orange highlight on the row.
  bool get lastActivityIsStale {
    if (lastActivity == null) return false;
    final days = DateTime.now().difference(lastActivity!).inDays;
    return days >= 60 && netBalance.abs() > 0.0;
  }

  String get avgRepaymentDaysLabel {
    if (avgRepaymentDays == null) return '—';
    return avgRepaymentDays == 1 ? '1 day' : '$avgRepaymentDays days';
  }

  static String _humanizeAge(DateTime since) {
    final days = DateTime.now().difference(since).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return '1 day';
    if (days < 30) return '$days days';
    if (days < 365) {
      final months = (days / 30).round();
      return months == 1 ? '1 month' : '$months months';
    }
    final years = (days / 365).round();
    return years == 1 ? '1 year' : '$years years';
  }
}

class _DatedTx {
  final DateTime when;
  final String type;
  final double amount;
  _DatedTx({required this.when, required this.type, required this.amount});
}
