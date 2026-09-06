import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/transactions/edit_transaction/edit_transaction.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/spaza_shimmer.dart';
import 'package:pasella/shared/widgets/transaction_detail_widgets.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';
import 'package:pasella/utils/transaction_util.dart';
import 'package:pasella/widgets/private_region.dart';

class TransactionDetailScreen extends StatefulWidget {
  final String customerName;
  final String customerId;
  final String transactionId;
  final Map<String, dynamic> transaction;
  final String? mobileNumber;
  final Future<Map<String, dynamic>?> Function()? loadTransaction;
  final Widget Function(Map<String, dynamic> transaction)?
      editTransactionBuilder;

  const TransactionDetailScreen({
    super.key,
    required this.customerName,
    required this.customerId,
    required this.transactionId,
    required this.transaction,
    this.mobileNumber,
    this.loadTransaction,
    this.editTransactionBuilder,
  });

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  late Future<Map<String, dynamic>?> _transactionFuture;
  late Map<String, dynamic> _latestTransaction;

  @override
  void initState() {
    super.initState();
    _latestTransaction = Map<String, dynamic>.from(widget.transaction);
    _transactionFuture = loadTransactionDetails();
  }

  Future<Map<String, dynamic>?> loadTransactionDetails() async {
    final injectedLoader = widget.loadTransaction;
    if (injectedLoader != null) return injectedLoader();
    final uid = StoreSession.instance.storeId;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('customers')
        .doc(widget.customerId)
        .collection('transactions')
        .doc(widget.transactionId)
        .get();
    if (!snapshot.exists) return null;
    final raw = snapshot.data();
    return raw is Map<String, dynamic> ? raw : null;
  }

  @override
  Widget build(BuildContext context) {
    final initialType = widget.transaction['type']?.toString();
    final title = switch (initialType) {
      'Payment' => 'Payment details',
      'Credit' => 'Pay later details',
      _ => 'Transaction details',
    };

    return Scaffold(
      appBar: CustomAppBar(
        title: title,
        trailing: IconButton(
          tooltip: 'Edit transaction',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () async {
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (context) =>
                    widget.editTransactionBuilder
                        ?.call(Map<String, dynamic>.from(_latestTransaction)) ??
                    EditTransactionScreen(
                      customerName: widget.customerName,
                      customerId: widget.customerId,
                      transactionId: widget.transactionId,
                      transaction: Map<String, dynamic>.from(
                        _latestTransaction,
                      ),
                      mobileNumber: widget.mobileNumber,
                    ),
              ),
            );
            // Deleting leaves no record to refresh, so close this page too.
            if (result == true && context.mounted) {
              Navigator.of(context).pop(true);
              return;
            }
            if (!context.mounted) return;
            setState(() {
              _transactionFuture = loadTransactionDetails();
            });
          },
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _transactionFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SpazaDetailSkeleton(
              semanticsLabel: 'Loading transaction details',
            );
          }
          if (!snapshot.hasData || snapshot.hasError) {
            return const Center(
                child: Text('Could not load this transaction.'));
          }

          final transaction = Map<String, dynamic>.from(snapshot.data!);
          _latestTransaction = transaction;
          return TransactionDetailsContent(
            customerName: widget.customerName,
            transaction: transaction,
          );
        },
      ),
    );
  }
}

/// Compact transaction receipt shared by live data and synthetic previews.
class TransactionDetailsContent extends StatelessWidget {
  const TransactionDetailsContent({
    super.key,
    required this.customerName,
    required this.transaction,
  });

  final String customerName;
  final Map<String, dynamic> transaction;

  @override
  Widget build(BuildContext context) {
    final isPayment = transaction['type'] == 'Payment';
    final rawStatus = transaction['status']?.toString().trim();
    final status = _titleCaseStatus(
      rawStatus == null || rawStatus.isEmpty
          ? (isPayment ? 'PAID' : 'DUE')
          : rawStatus,
    );
    final normalizedStatus = status.toLowerCase();
    final statusTone = normalizedStatus == 'paid'
        ? TransactionDetailStatusTone.positive
        : normalizedStatus.contains('due') ||
                normalizedStatus.contains('pending')
            ? TransactionDetailStatusTone.attention
            : TransactionDetailStatusTone.neutral;
    final remarks = transaction['remarks']?.toString().trim() ?? '';
    final rawProducts = transaction['products'];
    final products = rawProducts is Map
        ? rawProducts.map<String, dynamic>(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, dynamic>{};
    final date = _formatDetailDate(transaction['date']);
    final dueDate = _formatDetailDate(transaction['repaymentDate']);

    return SafeArea(
      child: PrivateRegion(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TransactionDetailHero(
              eyebrow: isPayment ? 'Payment' : 'Pay later',
              amount: CurrencyUtil.format(toDouble(transaction['amount'])),
              status: status,
              statusTone: statusTone,
              meta: '$customerName · $date',
            ),
            const SizedBox(height: SpazaSpace.md),
            TransactionDetailCard(
              child: Column(
                children: [
                  if (isPayment)
                    TransactionDetailRow(
                      'Payment method',
                      _paymentMethodLabel(
                        transaction['paymentMethod']?.toString(),
                      ),
                    )
                  else
                    TransactionDetailRow('Due date', dueDate),
                ],
              ),
            ),
            if (remarks.isNotEmpty) ...[
              const SizedBox(height: SpazaSpace.md),
              TransactionDetailCard(
                title: 'Note',
                child: Text(remarks),
              ),
            ],
            if (products.isNotEmpty) ...[
              const SizedBox(height: SpazaSpace.md),
              TransactionDetailCard(
                title: 'Products',
                child: _TransactionProductList(products: products),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransactionProductList extends StatelessWidget {
  const _TransactionProductList({required this.products});

  final Map<String, dynamic> products;

  @override
  Widget build(BuildContext context) {
    final uid = StoreSession.instance.storeId;
    final entries = products.entries.toList();
    return Column(
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) const Divider(),
          _TransactionProductRow(
            productId: entries[index].key,
            quantity: toInt(entries[index].value),
            userId: uid,
          ),
        ],
      ],
    );
  }
}

class _TransactionProductRow extends StatelessWidget {
  const _TransactionProductRow({
    required this.productId,
    required this.quantity,
    required this.userId,
  });

  final String productId;
  final int quantity;
  final String userId;

  @override
  Widget build(BuildContext context) => FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('products')
            .doc(productId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SpazaShimmer(
              semanticsLabel: 'Loading transaction product',
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    SpazaSkeletonBox(height: 36, width: 36),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SpazaSkeletonLine(widthFactor: .62, height: 13),
                          SizedBox(height: 8),
                          SpazaSkeletonLine(widthFactor: .36, height: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          if (snapshot.hasError ||
              !snapshot.hasData ||
              !snapshot.data!.exists) {
            return const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(SpazaIcons.products),
              title: Text('Product unavailable'),
            );
          }
          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final productName = formatStringToCamelCase(
            (data['name'] ?? 'Unnamed product').toString(),
          );
          final sellingPrice = data['sellingPrice'];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            minVerticalPadding: 6,
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: SpazaColors.subtle,
                borderRadius: BorderRadius.circular(SpazaRadius.small),
              ),
              child: const Icon(SpazaIcons.products, size: 19),
            ),
            title: Text(productName),
            subtitle: Text(
              sellingPrice == null
                  ? '$quantity sold'
                  : '$quantity × ${formatMoney(sellingPrice)}',
            ),
          );
        },
      );
}

String _paymentMethodLabel(String? value) => switch (value) {
      'cash' => 'Cash',
      'bank_transfer' => 'Bank transfer',
      'other' => 'Other',
      _ => 'Not recorded',
    };

String _titleCaseStatus(String value) => value
    .replaceAll('_', ' ')
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .map((word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
    .join(' ');

String _formatDetailDate(dynamic value) {
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  if (value is String) date = DateTime.tryParse(value);
  if (date == null) return 'Not recorded';
  return DateFormat('d MMM yyyy · HH:mm').format(date.toLocal());
}
