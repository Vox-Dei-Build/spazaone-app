// PAS-UX-06A: Date View ledger drill-down.
//
// The Reports tab's Date View previously showed only an aggregated Net
// Balance card for the selected range, with no way to see which
// transactions or customers produced that number. Merchants reported
// "it doesn't make sense" because there was nothing on screen to verify
// it against. This widget is the verification surface.
//
// It re-runs the same per-customer date-range query the backend's
// `calculateUserBalance` Cloud Function runs (lib/../functions/src/
// ledger/ledger.ts:51-57), so the rows here cannot disagree with the
// Net Balance card above as long as they pull from the same Firestore
// data. If they do disagree — a Cloud Function staleness, a missed
// trigger — the reconciliation line at the bottom turns orange and
// shows the delta, which is the actual ledger-truth signal merchants
// need.
//
// Concurrency: queries fan out per customer. For SMB sizes (sub-200
// customers) this is fine; see remaining-risks in the lane handover.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/contact/contact_management.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/widgets/private_region.dart';
import 'package:provider/provider.dart';

class DateRangeLedgerDrilldown extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final bool showLoadingIndicator;
  final ValueChanged<bool>? onLoadingChanged;

  const DateRangeLedgerDrilldown({
    super.key,
    required this.startDate,
    required this.endDate,
    this.showLoadingIndicator = true,
    this.onLoadingChanged,
  });

  @override
  State<DateRangeLedgerDrilldown> createState() =>
      _DateRangeLedgerDrilldownState();
}

class _DateRangeLedgerDrilldownState extends State<DateRangeLedgerDrilldown> {
  late Future<List<_CustomerRangeRollup>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadWithNotifications();
  }

  @override
  void didUpdateWidget(covariant DateRangeLedgerDrilldown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate ||
        oldWidget.endDate != widget.endDate) {
      setState(() {
        _future = _loadWithNotifications();
      });
    }
  }

  Future<List<_CustomerRangeRollup>> _loadWithNotifications() async {
    _notifyLoading(true);
    try {
      return await _load();
    } finally {
      _notifyLoading(false);
    }
  }

  void _notifyLoading(bool isLoading) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLoadingChanged?.call(isLoading);
    });
  }

  Future<List<_CustomerRangeRollup>> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return [];

    final firestore = FirebaseFirestore.instance;
    final customersRef =
        firestore.collection('users').doc(uid).collection('customers');
    final customersSnap = await customersRef.get();

    // Mirror the backend: per-customer, filter the transactions
    // subcollection by date range. Running these in parallel keeps the
    // wall-clock close to a single round-trip.
    final futures = customersSnap.docs.map((doc) async {
      final data = doc.data();
      final name = (data['name'] as String?) ?? 'Customer';
      final number = data['number'] as String?;
      final profileImageUrl = data['profileImageUrl'] as String?;

      final txnSnap = await customersRef
          .doc(doc.id)
          .collection('transactions')
          .where('date', isGreaterThanOrEqualTo: widget.startDate)
          .where('date', isLessThanOrEqualTo: widget.endDate)
          .orderBy('date', descending: true)
          .get();

      if (txnSnap.docs.isEmpty) return null;

      final lines = <_TxnLine>[];
      double net = 0.0;
      double credits = 0.0;
      double payments = 0.0;
      for (final txDoc in txnSnap.docs) {
        final tx = txDoc.data();
        final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final type = (tx['type'] as String?) ?? '';
        final rawDate = tx['date'];
        DateTime? when;
        if (rawDate is Timestamp) when = rawDate.toDate();
        if (rawDate is String) when = DateTime.tryParse(rawDate);
        if (type == 'Payment') {
          net += amount;
          payments += amount;
        } else if (type == 'Credit') {
          net -= amount;
          credits += amount;
        }
        lines.add(_TxnLine(when: when, type: type, amount: amount));
      }
      return _CustomerRangeRollup(
        customerId: doc.id,
        name: name,
        number: number,
        profileImageUrl: profileImageUrl,
        netInRange: net,
        creditsTotal: credits,
        paymentsTotal: payments,
        lines: lines,
      );
    }).toList();

    final results = await Future.wait(futures);
    final rollups = results.whereType<_CustomerRangeRollup>().toList();
    // Sort: largest negative net (most owed) first, settled in the middle,
    // largest positive net last. That foregrounds the cashflow-impact rows.
    rollups.sort((a, b) => a.netInRange.compareTo(b.netInRange));
    return rollups;
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return FutureBuilder<List<_CustomerRangeRollup>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (!widget.showLoadingIndicator) return const SizedBox.shrink();
          return Padding(
            padding: EdgeInsets.symmetric(
              vertical: SizeConfig.heightMultiplier * 2,
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: EdgeInsets.symmetric(
              vertical: SizeConfig.heightMultiplier * 2,
            ),
            child: Text(
              'Could not load transactions for this date range.',
              style: TextStyle(
                color: Colors.red,
                fontSize: SizeConfig.textMultiplier * 1.6,
              ),
            ),
          );
        }
        final rollups = snapshot.data ?? const <_CustomerRangeRollup>[];
        if (rollups.isEmpty) {
          return Padding(
            padding: EdgeInsets.symmetric(
              vertical: SizeConfig.heightMultiplier * 2,
            ),
            child: Text(
              'No transactions in this date range.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: SizeConfig.textMultiplier * 1.6,
              ),
            ),
          );
        }

        final summedNet = rollups.fold<double>(
          0.0,
          (acc, r) => acc + r.netInRange,
        );
        final txnCount = rollups.fold<int>(0, (acc, r) => acc + r.lines.length);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: SizeConfig.heightMultiplier * 1.5,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.list_alt,
                    size: SizeConfig.imageSizeMultiplier * 5,
                    color: kPrimaryColor,
                  ),
                  SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                  Expanded(
                    child: Text(
                      'Transactions in range',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '${rollups.length} customer'
                    '${rollups.length == 1 ? '' : 's'} • '
                    '$txnCount txn${txnCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.4,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            ...rollups.map((r) => _CustomerRangeTile(rollup: r)),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            _ReconciliationLine(rowsNet: summedNet),
          ],
        );
      },
    );
  }
}

class _CustomerRangeTile extends StatelessWidget {
  final _CustomerRangeRollup rollup;
  const _CustomerRangeTile({required this.rollup});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final isNegative = rollup.netInRange < 0;
    final color = isNegative ? Colors.red : kPrimaryColor;
    final avatarSize = SizeConfig.heightMultiplier * 6;

    return PrivateRegion(
      child: Card(
        elevation: 0.5,
        margin: EdgeInsets.symmetric(
          vertical: SizeConfig.heightMultiplier * 0.4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            SizeConfig.imageSizeMultiplier * 2,
          ),
        ),
        child: Theme(
          // Hide the default expansion divider; the Card already separates rows.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 2,
              vertical: 0,
            ),
            leading: SizedBox(
              width: avatarSize,
              height: avatarSize,
              child: profilePicture(
                context,
                rollup.name,
                rollup.profileImageUrl,
                rollup.number,
                false,
              ),
            ),
            title: Text(
              rollup.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: SizeConfig.textMultiplier * 1.8,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${rollup.lines.length} txn'
              '${rollup.lines.length == 1 ? '' : 's'} in range',
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.3,
                color: Colors.black54,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  CurrencyUtil.format(rollup.netInRange),
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.7,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Icon(
                  Icons.expand_more,
                  size: SizeConfig.imageSizeMultiplier * 5,
                  color: Colors.black45,
                ),
              ],
            ),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: SizeConfig.imageSizeMultiplier * 3,
                  vertical: SizeConfig.heightMultiplier * 0.5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...rollup.lines.map((line) => _TxnLineRow(line: line)),
                    Divider(height: SizeConfig.heightMultiplier * 2),
                    _SubtotalRow(
                      label: 'Transactions',
                      amount: rollup.creditsTotal,
                      amountColor: Colors.red,
                    ),
                    _SubtotalRow(
                      label: 'Payments',
                      amount: rollup.paymentsTotal,
                      amountColor: kPrimaryColor,
                    ),
                    _SubtotalRow(
                      label: 'Movement in period',
                      amount: rollup.netInRange,
                      amountColor: color,
                      isBold: true,
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 0.8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          // Both providers (BalanceSummaryProvider and
                          // CustomerBalanceSummaryProvider) are provided
                          // at the app root in main.dart, so navigating
                          // directly works without re-providing here —
                          // same pattern entity_tab.dart uses for the
                          // customer list.
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CustomerManagementPage(
                                customerName: rollup.name,
                                customerId: rollup.customerId,
                                mobileNumber: rollup.number,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Open customer ledger'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TxnLineRow extends StatelessWidget {
  final _TxnLine line;
  const _TxnLineRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final isCredit = line.type == 'Credit';
    final color = isCredit ? Colors.red : kPrimaryColor;
    final sign = isCredit ? '-' : '+';
    final displayType = isCredit ? 'Transaction' : line.type;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 0.4,
      ),
      child: Row(
        children: [
          Icon(
            isCredit ? Icons.arrow_downward : Icons.arrow_upward,
            color: color,
            size: SizeConfig.imageSizeMultiplier * 3.5,
          ),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
          Expanded(
            child: Text(
              line.when != null
                  ? DateFormat('dd MMM yyyy').format(line.when!)
                  : '—',
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.5,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            displayType,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.3,
              color: Colors.black45,
            ),
          ),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
          Text(
            '$sign${CurrencyUtil.format(line.amount)}',
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtotalRow extends StatelessWidget {
  final String label;
  final double amount;
  final Color amountColor;
  final bool isBold;

  const _SubtotalRow({
    required this.label,
    required this.amount,
    required this.amountColor,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 0.2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.5,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            CurrencyUtil.format(amount),
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReconciliationLine extends StatelessWidget {
  final double rowsNet;
  const _ReconciliationLine({required this.rowsNet});

  @override
  Widget build(BuildContext context) {
    // Surface the same number the Net Balance card above is showing so
    // the merchant can confirm the rows below reconcile with it. If
    // they disagree, the row tints orange and shows the delta — that
    // is the actual ledger-truth signal.
    return Consumer<BalanceSummaryProvider>(
      builder: (context, provider, _) {
        final cardNet = provider.balanceSummary.netBalance;
        final delta = (rowsNet - cardNet).abs();
        // Allow sub-cent floating-point noise without flagging.
        final reconciles = delta < 0.01;
        final color = reconciles ? Colors.green.shade800 : Colors.orange;
        return Padding(
          padding: EdgeInsets.symmetric(
            vertical: SizeConfig.heightMultiplier * 1,
            horizontal: SizeConfig.imageSizeMultiplier * 1,
          ),
          child: Row(
            children: [
              Icon(
                reconciles ? Icons.check_circle_outline : Icons.warning_amber,
                color: color,
                size: SizeConfig.imageSizeMultiplier * 4.5,
              ),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
              Expanded(
                child: Text(
                  reconciles
                      ? 'Rows sum to ${CurrencyUtil.format(rowsNet)} — '
                          'matches Net Movement above.'
                      : 'Rows sum to ${CurrencyUtil.format(rowsNet)}; '
                          'Net Movement above shows '
                          '${CurrencyUtil.format(cardNet)} '
                          '(off by ${CurrencyUtil.format(delta)}).',
                  style: TextStyle(
                    color: color,
                    fontSize: SizeConfig.textMultiplier * 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CustomerRangeRollup {
  final String customerId;
  final String name;
  final String? number;
  final String? profileImageUrl;
  final double netInRange;
  final double creditsTotal;
  final double paymentsTotal;
  final List<_TxnLine> lines;

  _CustomerRangeRollup({
    required this.customerId,
    required this.name,
    required this.number,
    required this.profileImageUrl,
    required this.netInRange,
    required this.creditsTotal,
    required this.paymentsTotal,
    required this.lines,
  });
}

class _TxnLine {
  final DateTime? when;
  final String type;
  final double amount;
  _TxnLine({required this.when, required this.type, required this.amount});
}
