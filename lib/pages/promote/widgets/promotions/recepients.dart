import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/ledger/widgets/transaction_tile.dart';

/// A simple list showing only the customers selected for a given promotion.
class SelectedCustomersRecipients extends StatelessWidget {
  final List<Map<String, dynamic>> customers;
  final Set<String> selectedCustomerIds;
  final void Function(Map<String, dynamic> customer)? onCustomerTap;

  const SelectedCustomersRecipients({
    Key? key,
    required this.customers,
    required this.selectedCustomerIds,
    this.onCustomerTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // filter down to only those customers whose IDs are in the selection set
    final filtered = customers
        .where((c) => selectedCustomerIds.contains(c['id'] as String))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '👥 Recipients',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: SizeConfig.textMultiplier * 2,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 1),
        if (filtered.isEmpty) ...[
          Text(
            'No customers selected.',
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.6,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ] else ...[
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final customer = filtered[i];
              final ts = (customer['lastTransaction']?['date'] as Timestamp?);
              final lastTransactionDate = ts != null
                  ? DateFormat('y MMM d, h:mm a').format(ts.toDate())
                  : '';
              return TransactionTile(
                color: kHighLightColor.value,
                name: customer['name'] as String? ?? '',
                amount: customer['lastTransaction']['amount'] ?? '',
                remarks: customer['lastTransaction']['remarks'] ?? '',
                status: customer['lastTransaction']['status'] ?? '',
                type: customer['lastTransaction']['type'] ?? '',
                date: lastTransactionDate,
                selectedCustomerId: customer['id'] as String,
                balance: (customer['balance'] as num?)?.toDouble() ?? 0.0,
                number: customer['number'] as String? ?? '',
                profileImageUrl: customer['profileImageUrl'] as String?,
                unreadCount: 0,
                isNPA: customer['isNPA'],
              );
            },
          ),
        ],
      ],
    );
  }
}
