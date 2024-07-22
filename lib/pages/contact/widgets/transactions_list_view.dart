import 'package:flutter/material.dart';
import 'package:pasella/pages/contact/view_model/customer_management_view_model.dart';
import 'package:pasella/pages/contact/view_transaction/view_transaction.dart';
import 'package:pasella/pages/contact/widgets/transaction_card.dart';
import 'package:pasella/pages/contact/widgets/transaction_date.dart';

class TransactionsListView extends StatelessWidget {
  final CustomerManagementViewModel customerManagementViewModel;
  final List<Map<String, dynamic>> transactions;
  final String customerId;
  final String customerName;

  const TransactionsListView({
    Key? key,
    required this.customerManagementViewModel,
    required this.transactions,
    required this.customerId,
    required this.customerName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    customerManagementViewModel.transactions = transactions;
    var groupedTransactions =
        customerManagementViewModel.groupTransactionsByDate();

    return ListView.builder(
      itemCount: groupedTransactions.keys.length,
      itemBuilder: (context, index) {
        String date = groupedTransactions.keys.elementAt(index);
        return Column(
          children: [
            TransactionDate(date),
            ...groupedTransactions[date]!.map((transaction) {
              return InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => TransactionDetailScreen(
                        customerName: customerName,
                        customerId: customerId,
                        transactionId: transaction['id'],
                        transaction: transaction,
                      ),
                    ),
                  );
                },
                child: TransactionCard(transaction),
              );
            }).toList(),
          ],
        );
      },
    );
  }
}
