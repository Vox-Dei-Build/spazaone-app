import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/widgets/private_region.dart';

/// One ledger entry, with its customer context, ready for presentation.
class CustomerActivityEntry {
  const CustomerActivityEntry({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.type,
    required this.amount,
    this.when,
    this.customerNumber,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String? customerNumber;
  final String type;
  final double amount;
  final DateTime? when;

  double get movement => type == 'Payment'
      ? amount
      : type == 'Credit'
          ? -amount
          : 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomerActivityEntry &&
          id == other.id &&
          customerId == other.customerId &&
          customerName == other.customerName &&
          customerNumber == other.customerNumber &&
          type == other.type &&
          amount == other.amount &&
          when == other.when;

  @override
  int get hashCode => Object.hash(
        id,
        customerId,
        customerName,
        customerNumber,
        type,
        amount,
        when,
      );
}

/// A flat timeline keeps each sale and payment visible without opening cards.
class CustomerActivityTimeline extends StatefulWidget {
  const CustomerActivityTimeline({
    super.key,
    required this.entries,
    required this.onOpenCustomer,
    this.reportedNet,
  });

  final List<CustomerActivityEntry> entries;
  final ValueChanged<CustomerActivityEntry> onOpenCustomer;
  final double? reportedNet;

  @override
  State<CustomerActivityTimeline> createState() =>
      _CustomerActivityTimelineState();
}

class _CustomerActivityTimelineState extends State<CustomerActivityTimeline> {
  static const _pageSize = 50;
  int _visibleLimit = _pageSize;
  late List<CustomerActivityEntry> _sourceEntries;
  late List<CustomerActivityEntry> _sortedEntries;

  @override
  void initState() {
    super.initState();
    _updateEntries();
  }

  @override
  void didUpdateWidget(covariant CustomerActivityTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Equivalent lists created during a normal parent rebuild must not hide
    // pages the merchant has already opened. Changed data starts at page one.
    if (!listEquals(_sourceEntries, widget.entries)) {
      _visibleLimit = _pageSize;
      _updateEntries();
    }
  }

  void _updateEntries() {
    _sourceEntries = List.of(widget.entries);
    _sortedEntries = [..._sourceEntries]..sort((a, b) {
        if (a.when == null && b.when == null) return a.id.compareTo(b.id);
        if (a.when == null) return 1;
        if (b.when == null) return -1;
        final dateOrder = b.when!.compareTo(a.when!);
        return dateOrder == 0 ? a.id.compareTo(b.id) : dateOrder;
      });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _sourceEntries;
    final visibleCount = entries.length.clamp(0, _visibleLimit);
    final groups = <String, List<CustomerActivityEntry>>{};
    for (final entry in _sortedEntries.take(_visibleLimit)) {
      final day = entry.when == null
          ? 'Date unavailable'
          : DateFormat('EEE, d MMM yyyy').format(entry.when!);
      (groups[day] ??= []).add(entry);
    }
    final customerCount =
        entries.map((entry) => entry.customerId).toSet().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(
          'Activity',
          style: theme.textTheme.titleMedium?.copyWith(
            color: kTertiaryColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}'
          ' · $customerCount ${customerCount == 1 ? 'customer' : 'customers'}',
          style: theme.textTheme.bodySmall?.copyWith(color: kSecondaryAccent),
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            child: Column(
              children: [
                const Icon(
                  SpazaIcons.sales,
                  color: kSecondaryAccent,
                  size: 28,
                ),
                const SizedBox(height: 12),
                Text(
                  'No activity for these dates',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: kTertiaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose another date to see sales and payments.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kSecondaryAccent,
                  ),
                ),
              ],
            ),
          ),
        for (final group in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 12),
            child: Text(
              group.key,
              style: theme.textTheme.bodySmall?.copyWith(
                color: kSecondaryAccent,
              ),
            ),
          ),
          for (final entry in group.value)
            _ActivityRow(
              key: ValueKey('customer-activity-${entry.id}'),
              entry: entry,
              onTap: () => widget.onOpenCustomer(entry),
            ),
        ],
        if (entries.length > _pageSize)
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text(
              'Showing $visibleCount of ${entries.length} entries',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: kSecondaryAccent,
              ),
            ),
          ),
        if (visibleCount < entries.length)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              key: const ValueKey('customer-activity-show-more'),
              onPressed: () => setState(() => _visibleLimit += _pageSize),
              style: TextButton.styleFrom(minimumSize: const Size(96, 48)),
              child: const Text('Show more'),
            ),
          ),
        if (widget.reportedNet != null)
          _ActivityReconciliation(
            rowsNet:
                entries.fold(0.0, (total, entry) => total + entry.movement),
            reportedNet: widget.reportedNet!,
          ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({super.key, required this.entry, required this.onTap});

  final CustomerActivityEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPayment = entry.type == 'Payment';
    final isSale = entry.type == 'Credit';
    final color = isPayment ? kPrimaryColor : kTertiaryColor;
    final label = isPayment
        ? 'Payment received'
        : isSale
            ? 'Sale added'
            : entry.type.isEmpty
                ? 'Entry'
                : entry.type;
    final sign = isPayment
        ? '+'
        : isSale
            ? '−'
            : '';
    final amount = '$sign${CurrencyUtil.format(entry.amount)}';
    final time =
        entry.when == null ? null : DateFormat('HH:mm').format(entry.when!);
    final detail = time == null ? label : '$label · $time';

    return PrivateRegion(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(SpazaRadius.control),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(SpazaRadius.control),
            child: Container(
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stack = constraints.maxWidth < 300 ||
                      MediaQuery.textScalerOf(context).scale(14) > 19;
                  final amountText = FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      amount,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: SpazaColors.subtle,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPayment
                              ? Icons.south_west_rounded
                              : isSale
                                  ? SpazaIcons.sales
                                  : Icons.notes_rounded,
                          size: 18,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.customerName,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: kTertiaryColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (!stack) ...[
                                  const SizedBox(width: 12),
                                  Flexible(child: amountText),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              detail,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: kSecondaryAccent,
                              ),
                            ),
                            if (stack) ...[
                              const SizedBox(height: 8),
                              amountText,
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        SpazaIcons.next,
                        size: 18,
                        color: kSecondaryAccent,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityReconciliation extends StatelessWidget {
  const _ActivityReconciliation({
    required this.rowsNet,
    required this.reportedNet,
  });

  final double rowsNet;
  final double reportedNet;

  @override
  Widget build(BuildContext context) {
    final delta = (rowsNet - reportedNet).abs();
    final reconciles = delta < .01;
    final color = reconciles ? kSecondaryAccent : Colors.orange.shade900;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            reconciles ? Icons.check_rounded : Icons.info_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              reconciles
                  ? 'Entries match the net movement above.'
                  : 'Entries total ${CurrencyUtil.format(rowsNet)}. '
                      'The summary shows ${CurrencyUtil.format(reportedNet)} '
                      '— a difference of ${CurrencyUtil.format(delta)}.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
