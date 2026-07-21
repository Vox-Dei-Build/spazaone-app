import 'package:flutter/material.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/pages/contact/view_model/customer_management_view_model.dart';
import 'package:pasella/pages/transactions/view_transaction/view_transaction.dart';
import 'package:pasella/pages/transactions/widgets/product_name_cache.dart';
import 'package:pasella/pages/transactions/widgets/transaction_card.dart';
import 'package:pasella/pages/transactions/widgets/transaction_date.dart';
import 'package:pasella/widgets/private_region.dart';
import 'package:provider/provider.dart';

class TransactionsListView extends StatefulWidget {
  final CustomerManagementViewModel customerManagementViewModel;
  final List<Map<String, dynamic>> transactions;
  final String customerId;
  final String customerName;
  final String? mobileNumber;

  const TransactionsListView({
    Key? key,
    required this.customerManagementViewModel,
    required this.transactions,
    required this.customerId,
    required this.customerName,
    this.mobileNumber,
  }) : super(key: key);

  @override
  _TransactionsListViewState createState() => _TransactionsListViewState();
}

class _TransactionsListViewState extends State<TransactionsListView> {
  final ScrollController _scrollController = ScrollController();
  late final ProductNameCache _productNameCache;

  @override
  void initState() {
    super.initState();
    _productNameCache = ProductNameCache(
      userId: StoreSession.instance.storeId,
    );
    // Kick off the first batched resolve for whatever we already have.
    _productNameCache.resolveFromTransactions(widget.transactions);
  }

  @override
  void didUpdateWidget(covariant TransactionsListView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Resolve any new product IDs introduced by the latest snapshot. The
    // cache de-dupes already-known IDs internally, so this is cheap.
    if (widget.transactions != oldWidget.transactions) {
      _productNameCache.resolveFromTransactions(widget.transactions);
    }

    // ✅ Auto-scroll to the bottom when new transactions arrive
    if (widget.transactions.length > oldWidget.transactions.length) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.minScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _productNameCache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.customerManagementViewModel.transactions = widget.transactions;
    var groupedTransactions =
        widget.customerManagementViewModel.groupTransactionsByDate();

    var reversedKeys = groupedTransactions.keys
        .toList()
        .reversed
        .toList(); // ✅ Reverse the date order

    // Customer profile already shows the name in the AppBar; the list shows
    // their amounts. Wrap the list once so every transaction amount is masked
    // in replay -- pairing of name+amount is what makes this PII-sensitive.
    return ChangeNotifierProvider<ProductNameCache>.value(
      value: _productNameCache,
      child: PrivateRegion(
        child: ListView.builder(
          controller: _scrollController,
          reverse: true, // ✅ Makes the latest transactions appear at the bottom
          itemCount: reversedKeys.length,
          itemBuilder: (context, index) {
            String date = reversedKeys[index];
            return Column(
              children: [
                TransactionDate(date),
                ...groupedTransactions[date]!
                    .map((transaction) {
                      return InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => TransactionDetailScreen(
                                  customerName: widget.customerName,
                                  customerId: widget.customerId,
                                  transactionId: transaction['id'],
                                  transaction: transaction,
                                  mobileNumber: widget.mobileNumber),
                            ),
                          );
                        },
                        child: TransactionCard(transaction),
                      );
                    })
                    .toList()
                    .reversed, // ✅ Reverse transactions inside each date group
              ],
            );
          },
        ),
      ),
    );
  }
}
