// PAS-UX-06A (refactored): per-customer mini-report.
//
// History: this used to be a collapsible Card pinned above the transactions
// list on the customer profile (`CustomerReportPanel`). With the Pay Later
// redesign the page surface is reserved for the ledger itself + the new
// compact balance hero + the sticky CTA; a third panel above the list
// fought all three for attention.
//
// New shape: the same metrics are rendered inside a bottom sheet opened
// from an "insights" icon button in the ProfileAppBar. Same numbers, same
// provenance line, same staleness highlight — but only visible when a
// merchant explicitly asks for them.
//
// Data ownership: the sheet fetches its own transactions on open via
// `CurrencyUtil.fetchTransactionsForCustomer`. This makes it independent
// of render-order timing on the host page — previously the sheet read
// `viewModel.transactions`, which is only populated when the ledger list
// renders, so opening the insights before the list painted (or while the
// stream was still in `ConnectionState.waiting`) showed an empty state
// even when the customer had a full history. One read per insights tap
// is cheap and correct.

import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/transaction_util.dart';

/// Opens the customer-report bottom sheet. Returns a Future that resolves
/// when the sheet is dismissed.
Future<void> showCustomerReportSheet(
  BuildContext context, {
  required String userId,
  required String customerId,
  required String customerName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => CustomerReportSheet(
      userId: userId,
      customerId: customerId,
      customerName: customerName,
    ),
  );
}

class CustomerReportSheet extends StatefulWidget {
  final String userId;
  final String customerId;
  final String customerName;

  const CustomerReportSheet({
    super.key,
    required this.userId,
    required this.customerId,
    required this.customerName,
  });

  @override
  State<CustomerReportSheet> createState() => _CustomerReportSheetState();
}

class _CustomerReportSheetState extends State<CustomerReportSheet> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = CurrencyUtil.fetchTransactionsForCustomer(
      widget.userId,
      widget.customerId,
    );
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _LoadingShell();
        }
        if (snapshot.hasError) {
          return _ErrorShell(message: '${snapshot.error}');
        }
        final txs = snapshot.data ?? const [];
        if (txs.isEmpty) {
          return _EmptyShell(customerName: widget.customerName);
        }
        return _ReportBody(
          customerName: widget.customerName,
          transactions: txs,
        );
      },
    );
  }
}

class _ReportBody extends StatelessWidget {
  final String customerName;
  final List<Map<String, dynamic>> transactions;

  const _ReportBody({
    required this.customerName,
    required this.transactions,
  });

  @override
  Widget build(BuildContext context) {
    final stats = _CustomerReportStats.from(transactions);
    final balanceState = _BalanceTone.from(stats.netBalance);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          SizeConfig.imageSizeMultiplier * 5,
          SizeConfig.heightMultiplier * 1,
          SizeConfig.imageSizeMultiplier * 5,
          SizeConfig.heightMultiplier * 2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetChrome.grabber(),
            SizedBox(height: SizeConfig.heightMultiplier * 1.6),

            // ── HEADER ──
            _SheetHeader(customerName: customerName),
            SizedBox(height: SizeConfig.heightMultiplier * 2.2),

            // ── HERO BALANCE ──
            _BalanceHeroBlock(
              tone: balanceState,
              amount: stats.netBalance,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2.8),

            // ── RELATIONSHIP ──
            const _SectionEyebrow(label: 'RELATIONSHIP'),
            _MetricRow(
              label: 'Customer since',
              value: stats.relationshipAgeLabel,
            ),
            _MetricRow(
              label: 'Last activity',
              value: stats.lastActivityLabel,
              valueColor:
                  stats.lastActivityIsStale ? const Color(0xFFE65100) : null,
              valueBadge: stats.lastActivityIsStale ? 'stale' : null,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2.4),

            // ── TOTALS ──
            const _SectionEyebrow(label: 'TOTALS'),
            _MetricRow(
              label: 'Credited',
              valueLeading: '${stats.creditCount}×',
              value: CurrencyUtil.format(stats.creditAmount),
              valueColor: const Color(0xFFC62828),
            ),
            _MetricRow(
              label: 'Paid',
              valueLeading: '${stats.paymentCount}×',
              value: CurrencyUtil.format(stats.paymentAmount),
              valueColor: const Color(0xFF1B5E20),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2.4),

            // ── BEHAVIOUR ──
            const _SectionEyebrow(label: 'BEHAVIOUR'),
            _MetricRow(
              label: 'Avg. days to repay',
              value: stats.avgRepaymentDaysLabel,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2.4),

            // ── PROVENANCE ──
            _ProvenanceLine(count: transactions.length),
          ],
        ),
      ),
    );
  }
}

/// Top of the sheet: green-tinted insights chip + uppercase eyebrow +
/// the customer name on a clear scale jump.
class _SheetHeader extends StatelessWidget {
  final String customerName;
  const _SheetHeader({required this.customerName});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: SizeConfig.imageSizeMultiplier * 11,
          height: SizeConfig.imageSizeMultiplier * 11,
          decoration: BoxDecoration(
            color: kPrimaryColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.insights_outlined,
            color: kPrimaryColor,
            size: SizeConfig.imageSizeMultiplier * 6,
          ),
        ),
        SizedBox(width: SizeConfig.imageSizeMultiplier * 3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'INSIGHTS',
                style: TextStyle(
                  color: kPrimaryColor,
                  fontSize: SizeConfig.textMultiplier * 1.25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 0.3),
              Text(
                customerName,
                style: TextStyle(
                  color: const Color(0xFF1A1F2B),
                  fontSize: SizeConfig.textMultiplier * 2.4,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded),
          color: Colors.black54,
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close',
        ),
      ],
    );
  }
}

/// The headline number. State-aware: red Owing / green In credit / slate
/// Settled. Big tabular-figure amount, eyebrow label, and a tiny direction
/// chip ("They owe you" / "You owe them" / "All square").
class _BalanceHeroBlock extends StatelessWidget {
  final _BalanceTone tone;
  final double amount;
  const _BalanceHeroBlock({required this.tone, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        SizeConfig.imageSizeMultiplier * 4,
        SizeConfig.heightMultiplier * 1.6,
        SizeConfig.imageSizeMultiplier * 4,
        SizeConfig.heightMultiplier * 1.8,
      ),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                tone.eyebrow,
                style: TextStyle(
                  color: tone.accent,
                  fontSize: SizeConfig.textMultiplier * 1.25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: SizeConfig.imageSizeMultiplier * 2,
                  vertical: SizeConfig.heightMultiplier * 0.3,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tone.directionLabel,
                  style: TextStyle(
                    color: tone.accent,
                    fontSize: SizeConfig.textMultiplier * 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 0.6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              CurrencyUtil.format(amount.abs()),
              style: TextStyle(
                color: tone.accent,
                fontSize: SizeConfig.textMultiplier * 4.2,
                fontWeight: FontWeight.w800,
                height: 1.0,
                letterSpacing: -0.8,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionEyebrow extends StatelessWidget {
  final String label;
  const _SectionEyebrow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: SizeConfig.heightMultiplier * 0.6),
      child: Text(
        label,
        style: TextStyle(
          color: const Color(0xFF6B7280),
          fontSize: SizeConfig.textMultiplier * 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _ProvenanceLine extends StatelessWidget {
  final int count;
  const _ProvenanceLine({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 3,
        vertical: SizeConfig.heightMultiplier * 1.0,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF6B7280),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
          Expanded(
            child: Text(
              'Derived from $count '
              'transaction${count == 1 ? '' : 's'} in this ledger.',
              style: TextStyle(
                color: const Color(0xFF4B5563),
                fontSize: SizeConfig.textMultiplier * 1.35,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tone palette for the hero block. Mirrors `CustomerBalanceHero` so the
/// sheet's headline matches what the merchant just saw on the Pay Later
/// screen.
class _BalanceTone {
  final String eyebrow;
  final String directionLabel;
  final Color accent;
  final Color tint;

  const _BalanceTone._({
    required this.eyebrow,
    required this.directionLabel,
    required this.accent,
    required this.tint,
  });

  factory _BalanceTone.from(double balance) {
    if (balance < 0) {
      return const _BalanceTone._(
        eyebrow: 'OWING',
        directionLabel: 'They owe you',
        accent: Color(0xFFC62828),
        tint: Color(0xFFFDECEA),
      );
    }
    if (balance > 0) {
      return const _BalanceTone._(
        eyebrow: 'IN CREDIT',
        directionLabel: 'You owe them',
        accent: Color(0xFF1B5E20),
        tint: Color(0xFFE8F5E9),
      );
    }
    return const _BalanceTone._(
      eyebrow: 'SETTLED',
      directionLabel: 'All square',
      accent: Color(0xFF455A64),
      tint: Color(0xFFECEFF1),
    );
  }
}

class _SheetChrome {
  static Widget grabber() => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFCFD8DC),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _LoadingShell extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetChrome.grabber(),
            SizedBox(height: SizeConfig.heightMultiplier * 3),
            const CircularProgressIndicator(),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Text(
              'Loading insights…',
              style: TextStyle(
                color: Colors.black54,
                fontSize: SizeConfig.textMultiplier * 1.6,
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 3),
          ],
        ),
      ),
    );
  }
}

class _ErrorShell extends StatelessWidget {
  final String message;
  const _ErrorShell({required this.message});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetChrome.grabber(),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Icon(Icons.error_outline,
                size: SizeConfig.imageSizeMultiplier * 12,
                color: Colors.redAccent),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            Text(
              'Could not load insights',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: SizeConfig.textMultiplier * 2,
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 0.5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black54,
                fontSize: SizeConfig.textMultiplier * 1.4,
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
          ],
        ),
      ),
    );
  }
}

class _EmptyShell extends StatelessWidget {
  final String customerName;
  const _EmptyShell({required this.customerName});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetChrome.grabber(),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Icon(Icons.insights_outlined,
                size: SizeConfig.imageSizeMultiplier * 12,
                color: Colors.black26),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            Text(
              'No insights yet',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: SizeConfig.textMultiplier * 2,
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 0.5),
            Text(
              'Record a credit or payment for $customerName to start '
              'building their report.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black54,
                fontSize: SizeConfig.textMultiplier * 1.5,
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
          ],
        ),
      ),
    );
  }
}

/// One row inside a grouped section.
///
/// Two-tier scale: a medium-weight neutral label on the left, a bold
/// tabular-figures value on the right. No row icon — the section eyebrow
/// already provides grouping, and removing per-row icons calms the visual
/// rhythm considerably.
///
/// Optional adornments:
///  - [valueLeading]: small "Nx" count chip painted before the value (used
///    by the Totals section to surface credit/payment counts without
///    eating a separate row).
///  - [valueBadge]: small uppercase pill painted to the right of the value
///    (used to flag stale activity).
class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final String? valueLeading;
  final String? valueBadge;
  final Color? valueColor;

  const _MetricRow({
    required this.label,
    required this.value,
    this.valueLeading,
    this.valueBadge,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveValueColor = valueColor ?? const Color(0xFF111827);

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 0.7,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.6,
                color: const Color(0xFF4B5563),
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ),
          if (valueLeading != null) ...[
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: SizeConfig.imageSizeMultiplier * 1.6,
                vertical: SizeConfig.heightMultiplier * 0.25,
              ),
              decoration: BoxDecoration(
                color: effectiveValueColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                valueLeading!,
                style: TextStyle(
                  color: effectiveValueColor,
                  fontSize: SizeConfig.textMultiplier * 1.2,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
          ],
          Text(
            value,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.8,
              fontWeight: FontWeight.w700,
              color: effectiveValueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (valueBadge != null) ...[
            SizedBox(width: SizeConfig.imageSizeMultiplier * 1.5),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: SizeConfig.imageSizeMultiplier * 1.4,
                vertical: SizeConfig.heightMultiplier * 0.2,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                valueBadge!.toUpperCase(),
                style: TextStyle(
                  color: const Color(0xFFE65100),
                  fontSize: SizeConfig.textMultiplier * 1.05,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
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
    // subsequent payment of any amount and record the gap. Simple
    // heuristic, intentionally — the provenance line keeps it honest.
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
