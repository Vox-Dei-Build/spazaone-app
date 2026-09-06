import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/contact/contact_management.dart';
import 'package:pasella/pages/reports/business_report/widgets/customer_activity_timeline.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/services/store_session.dart';
import 'package:provider/provider.dart';

/// Reads the same per-customer range as the balance summary and shows every
/// entry in date order. The timeline reconciles these rows with the summary.
class DateRangeLedgerDrilldown extends StatefulWidget {
  const DateRangeLedgerDrilldown({
    super.key,
    required this.startDate,
    required this.endDate,
    this.showLoadingIndicator = true,
    this.onLoadingChanged,
  });

  final DateTime startDate;
  final DateTime endDate;
  final bool showLoadingIndicator;
  final ValueChanged<bool>? onLoadingChanged;

  @override
  State<DateRangeLedgerDrilldown> createState() =>
      _DateRangeLedgerDrilldownState();
}

class _DateRangeLedgerDrilldownState extends State<DateRangeLedgerDrilldown> {
  late Future<List<CustomerActivityEntry>> _future;
  int _loadGeneration = 0;

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
      _future = _loadWithNotifications();
    }
  }

  Future<List<CustomerActivityEntry>> _loadWithNotifications() async {
    final generation = ++_loadGeneration;
    _notifyLoading(true, generation);
    try {
      return await _load(widget.startDate, widget.endDate);
    } finally {
      _notifyLoading(false, generation);
    }
  }

  void _notifyLoading(bool isLoading, int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _loadGeneration) {
        widget.onLoadingChanged?.call(isLoading);
      }
    });
  }

  Future<List<CustomerActivityEntry>> _load(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final uid = StoreSession.instance.storeId;
    if (uid.isEmpty) return [];

    final customersRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('customers');
    final customersSnap = await customersRef.get();

    // Mirror the backend's date filters. Keep the bounds fixed for the entire
    // request, even if another range is selected before these reads finish.
    final futures = customersSnap.docs.map((doc) async {
      final data = doc.data();
      final txnSnap = await customersRef
          .doc(doc.id)
          .collection('transactions')
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .orderBy('date', descending: true)
          .get();

      return txnSnap.docs.map((txDoc) {
        final tx = txDoc.data();
        final rawDate = tx['date'];
        DateTime? when;
        if (rawDate is Timestamp) when = rawDate.toDate();
        if (rawDate is String) when = DateTime.tryParse(rawDate);
        return CustomerActivityEntry(
          id: '${doc.id}-${txDoc.id}',
          customerId: doc.id,
          customerName: (data['name'] as String?) ?? 'Customer',
          customerNumber: data['number'] as String?,
          profileImageUrl: data['profileImageUrl']?.toString(),
          when: when,
          type: (tx['type'] as String?) ?? '',
          amount: (tx['amount'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
    });
    final results = await Future.wait(futures);
    return results.expand((entries) => entries).toList();
  }

  void _openCustomer(CustomerActivityEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerManagementPage(
          customerName: entry.customerName,
          customerId: entry.customerId,
          mobileNumber: entry.customerNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CustomerActivityEntry>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (!widget.showLoadingIndicator) return const SizedBox.shrink();
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const Icon(Icons.cloud_off_outlined, color: kSecondaryAccent),
                const SizedBox(height: 10),
                const Text(
                  'Could not load activity for these dates.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _future = _loadWithNotifications();
                  }),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try again'),
                ),
              ],
            ),
          );
        }
        return Consumer<BalanceSummaryProvider>(
          builder: (context, provider, _) => CustomerActivityTimeline(
            entries: snapshot.data ?? const [],
            reportedNet: provider.balanceSummary.netBalance,
            onOpenCustomer: _openCustomer,
          ),
        );
      },
    );
  }
}
