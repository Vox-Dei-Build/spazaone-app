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
import 'package:pasella/design/spaza_tokens.dart';
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

  void _retry() {
    setState(() {
      _future = CurrencyUtil.fetchTransactionsForCustomer(
        widget.userId,
        widget.customerId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _LoadingShell();
        }
        if (snapshot.hasError) {
          return _ErrorShell(onRetry: _retry);
        }
        final txs = snapshot.data ?? const [];
        if (txs.isEmpty) {
          return _EmptyShell(customerName: widget.customerName);
        }
        return CustomerReportContent(
          customerName: widget.customerName,
          transactions: txs,
        );
      },
    );
  }
}

class CustomerReportContent extends StatelessWidget {
  final String customerName;
  final List<Map<String, dynamic>> transactions;

  const CustomerReportContent(
      {super.key, required this.customerName, required this.transactions});

  @override
  Widget build(BuildContext context) {
    final stats = _CustomerReportStats.from(transactions);
    final balanceState = _BalanceTone.from(stats.netBalance);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          20,
          8,
          20,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetChrome.grabber(),
            const SizedBox(height: 16),

            // ── HEADER ──
            _SheetHeader(customerName: customerName),
            const SizedBox(height: 24),

            // ── HERO BALANCE ──
            _BalanceHeroBlock(tone: balanceState, amount: stats.netBalance),
            const SizedBox(height: 24),

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
            const SizedBox(height: 24),

            // ── TOTALS ──
            const _SectionEyebrow(label: 'TOTALS'),
            _MetricRow(
              label: 'Transactions',
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
            const SizedBox(height: 24),

            // ── BEHAVIOUR ──
            const _SectionEyebrow(label: 'BEHAVIOUR'),
            _MetricRow(
              label: 'Avg. days to repay',
              value: stats.avgRepaymentDaysLabel,
            ),
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
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: kPrimaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(SpazaRadius.control),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.insights_outlined,
            color: kPrimaryColor,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'INSIGHTS',
                style: TextStyle(
                  color: kPrimaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                customerName,
                style: const TextStyle(
                  color: SpazaColors.heading,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
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
          color: SpazaColors.muted,
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Close',
        ),
      ],
    );
  }
}

/// The headline number. State-aware: red Owing / green Ahead / slate
/// Settled. Big tabular-figure amount, eyebrow label, and a tiny direction
/// chip ("They owe you" / "You owe them" / "All square").
class _BalanceHeroBlock extends StatelessWidget {
  final _BalanceTone tone;
  final double amount;
  const _BalanceHeroBlock({required this.tone, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16,
      ),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(SpazaRadius.control),
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
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              CurrencyUtil.format(amount.abs()),
              style: TextStyle(
                color: tone.accent,
                fontSize: 30,
                fontWeight: FontWeight.w500,
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: SpazaColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

/// Tone palette for the hero block. Mirrors `CustomerBalanceHero` so the
/// sheet's headline matches what the merchant just saw on the Pay Later
/// screen.
class _BalanceTone {
  final String eyebrow;
  final Color accent;
  final Color tint;

  const _BalanceTone._({
    required this.eyebrow,
    required this.accent,
    required this.tint,
  });

  factory _BalanceTone.from(double balance) {
    if (balance < 0) {
      return const _BalanceTone._(
        eyebrow: 'OWING',
        accent: Color(0xFFC62828),
        tint: Color(0xFFFDECEA),
      );
    }
    if (balance > 0) {
      return const _BalanceTone._(
        eyebrow: 'AHEAD',
        accent: Color(0xFF1B5E20),
        tint: Color(0xFFE8F5E9),
      );
    }
    return const _BalanceTone._(
      eyebrow: 'SETTLED',
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
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetChrome.grabber(),
            const SizedBox(height: 40),
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            const Text(
              'Loading insights…',
              style: TextStyle(
                color: SpazaColors.muted,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _ErrorShell extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorShell({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetChrome.grabber(),
            const SizedBox(height: 24),
            const Icon(
              Icons.error_outline,
              size: 44,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 8),
            const Text(
              'Could not load insights',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SpazaColors.muted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
            const SizedBox(height: 24),
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetChrome.grabber(),
            const SizedBox(height: 24),
            const Icon(
              Icons.insights_outlined,
              size: 44,
              color: Colors.black26,
            ),
            const SizedBox(height: 8),
            const Text(
              'No insights yet',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Record a transaction or payment for $customerName to start '
              'building their report.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SpazaColors.muted,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
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
    final theme = Theme.of(context);
    final color = valueColor ?? SpazaColors.heading;
    final values = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (valueLeading != null)
          Text(valueLeading!,
              style: theme.textTheme.bodySmall?.copyWith(color: color)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: theme.textTheme.titleSmall?.copyWith(color: color)),
        ),
        if (valueBadge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(valueBadge!.toUpperCase(),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: const Color(0xFFE65100))),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(builder: (context, constraints) {
        final title = Text(label,
            style:
                theme.textTheme.bodyMedium?.copyWith(color: SpazaColors.muted));
        if (constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(16) > 21) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 8), values]);
        }
        return Row(children: [
          Expanded(child: title),
          const SizedBox(width: 16),
          Flexible(child: values)
        ]);
      }),
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
      dated.add(
        _DatedTx(
          when: when,
          type: (t['type'] as String?) ?? '',
          amount: (t['amount'] as num?)?.toDouble() ?? 0.0,
        ),
      );
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
