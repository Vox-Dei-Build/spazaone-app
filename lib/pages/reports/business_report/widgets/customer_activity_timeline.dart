import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
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
    this.profileImageUrl,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String? customerNumber;
  final String? profileImageUrl;
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
          profileImageUrl == other.profileImageUrl &&
          type == other.type &&
          amount == other.amount &&
          when == other.when;

  @override
  int get hashCode => Object.hash(
        id,
        customerId,
        customerName,
        customerNumber,
        profileImageUrl,
        type,
        amount,
        when,
      );
}

/// Production's customer rollups, with entries disclosed only when needed.
/// Totals always include every loaded entry; paging limits rendered customers.
class CustomerActivityTimeline extends StatefulWidget {
  const CustomerActivityTimeline(
      {super.key,
      required this.entries,
      required this.onOpenCustomer,
      this.reportedNet});
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
  late List<List<CustomerActivityEntry>> _customers;

  @override
  void initState() {
    super.initState();
    _updateEntries();
  }

  @override
  void didUpdateWidget(covariant CustomerActivityTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(_sourceEntries, widget.entries)) {
      _visibleLimit = _pageSize;
      _updateEntries();
    }
  }

  void _updateEntries() {
    _sourceEntries = List.of(widget.entries);
    final groups = <String, List<CustomerActivityEntry>>{};
    for (final entry in _sourceEntries) {
      (groups[entry.customerId] ??= []).add(entry);
    }
    _customers = groups.values.toList();
    for (final entries in _customers) {
      entries.sort((a, b) {
        if (a.when == null && b.when == null) return a.id.compareTo(b.id);
        if (a.when == null) return 1;
        if (b.when == null) return -1;
        final dateOrder = b.when!.compareTo(a.when!);
        return dateOrder == 0 ? a.id.compareTo(b.id) : dateOrder;
      });
    }
    _customers.sort((a, b) {
      final movement = _net(a).compareTo(_net(b));
      return movement == 0
          ? a.first.customerId.compareTo(b.first.customerId)
          : movement;
    });
  }

  static double _net(List<CustomerActivityEntry> entries) =>
      entries.fold(0.0, (sum, entry) => sum + entry.movement);

  @override
  Widget build(BuildContext context) {
    final visible = _customers.length.clamp(0, _visibleLimit);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text('Transactions in range',
                  style: Theme.of(context).textTheme.titleSmall),
              Text(
                  '${_sourceEntries.length} ${_sourceEntries.length == 1 ? 'entry' : 'entries'}'
                  ' · ${_customers.length} ${_customers.length == 1 ? 'customer' : 'customers'}',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
      ),
      if (_customers.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No activity for these dates')),
      for (final entries in _customers.take(_visibleLimit))
        _CustomerActivityGroup(
          key: ValueKey('customer-activity-group-${entries.first.customerId}'),
          entries: entries,
          onOpen: () => widget.onOpenCustomer(entries.first),
        ),
      if (_customers.length > _pageSize)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Showing $visible of ${_customers.length} customers',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall)),
      if (visible < _customers.length)
        TextButton(
            key: const ValueKey('customer-activity-show-more'),
            onPressed: () => setState(() => _visibleLimit += _pageSize),
            child: const Text('Show more')),
      if (widget.reportedNet != null)
        _ActivityReconciliation(
            rowsNet: _net(_sourceEntries), reportedNet: widget.reportedNet!),
    ]);
  }
}

class _CustomerActivityGroup extends StatelessWidget {
  const _CustomerActivityGroup(
      {super.key, required this.entries, required this.onOpen});
  final List<CustomerActivityEntry> entries;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final customer = entries.first;
    final net = entries.fold(0.0, (sum, entry) => sum + entry.movement);
    final sales = entries
        .where((entry) => entry.type == 'Credit')
        .fold(0.0, (sum, entry) => sum + entry.amount);
    final payments = entries
        .where((entry) => entry.type == 'Payment')
        .fold(0.0, (sum, entry) => sum + entry.amount);
    final color = net < 0 ? Theme.of(context).colorScheme.error : kPrimaryColor;
    return PrivateRegion(child: LayoutBuilder(builder: (context, constraints) {
      final stack = constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      final money = Text(CurrencyUtil.format(net),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color, fontSize: 15, fontWeight: FontWeight.w700));
      return Card(
        elevation: .5,
        margin: const EdgeInsets.only(bottom: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpazaRadius.control),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: stack
                ? null
                : SizedBox.square(
                    dimension: 40,
                    child: profilePicture(
                      context,
                      customer.customerName,
                      customer.profileImageUrl,
                      customer.customerNumber,
                      false,
                      displayIcons: false,
                      radius: 20,
                    ),
                  ),
            title: Text(customer.customerName,
                maxLines: stack ? null : 1,
                overflow: stack ? null : TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontSize: 15)),
            subtitle:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${entries.length} ${entries.length == 1 ? 'transaction' : 'transactions'}',
                  style: Theme.of(context).textTheme.bodySmall),
              if (stack) money,
            ]),
            trailing: stack
                ? null
                : ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: constraints.maxWidth * .46),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(child: money),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more, size: 20),
                    ])),
            children: [
              for (final entry in entries)
                _ActivityEntryRow(
                    key: ValueKey('customer-activity-${entry.id}'),
                    entry: entry),
              const Divider(height: 16),
              _ActivityTotal(
                  'Transactions', sales, Theme.of(context).colorScheme.error),
              _ActivityTotal('Payments', payments, kPrimaryColor),
              _ActivityTotal('Net movement', net, color),
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open customer ledger'))),
            ],
          ),
        ),
      );
    }));
  }
}

class _ActivityEntryRow extends StatelessWidget {
  const _ActivityEntryRow({super.key, required this.entry});
  final CustomerActivityEntry entry;
  @override
  Widget build(BuildContext context) {
    final type = entry.type == 'Credit' ? 'Transaction' : entry.type;
    final date = entry.when == null
        ? 'Date unavailable'
        : DateFormat('dd MMM yyyy · HH:mm').format(entry.when!);
    final sign = entry.type == 'Credit'
        ? '−'
        : entry.type == 'Payment'
            ? '+'
            : '';
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final description =
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(type.isEmpty ? 'Entry' : type,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 14)),
              Text(date, style: Theme.of(context).textTheme.bodySmall),
            ]);
            final amount = Text('$sign${CurrencyUtil.format(entry.amount)}',
                key: ValueKey('customer-activity-amount-${entry.id}'),
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    color: entry.type == 'Credit'
                        ? Theme.of(context).colorScheme.error
                        : kPrimaryColor));
            return _ActivityFigureRow(
              description: description,
              amount: amount,
              stack: constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20,
            );
          },
        ));
  }
}

class _ActivityTotal extends StatelessWidget {
  const _ActivityTotal(this.label, this.amount, this.color);
  final String label;
  final double amount;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: LayoutBuilder(builder: (context, constraints) {
          final amountKey = label.toLowerCase().replaceAll(' ', '-');
          return _ActivityFigureRow(
            description:
                Text(label, style: Theme.of(context).textTheme.bodySmall),
            amount: Text(
              CurrencyUtil.format(amount),
              key: ValueKey('customer-activity-total-$amountKey'),
              textAlign: TextAlign.right,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontSize: 14, color: color),
            ),
            stack: constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 20,
          );
        }),
      );
}

/// Keeps every activity figure on the same right edge while giving descriptions
/// a stable share of the row. At narrow widths and large text sizes, the figure
/// moves below the description and retains that right edge without truncation.
class _ActivityFigureRow extends StatelessWidget {
  const _ActivityFigureRow({
    required this.description,
    required this.amount,
    required this.stack,
  });

  final Widget description;
  final Widget amount;
  final bool stack;

  @override
  Widget build(BuildContext context) {
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          description,
          const SizedBox(height: 2),
          Align(alignment: Alignment.centerRight, child: amount),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: description),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.topRight,
            child: FittedBox(fit: BoxFit.scaleDown, child: amount),
          ),
        ),
      ],
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
    if (reconciles) return const SizedBox.shrink();
    final color = Colors.orange.shade900;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Entries total ${CurrencyUtil.format(rowsNet)}. '
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
