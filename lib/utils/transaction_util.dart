class TransactionStats {
  final int paymentCount;
  final double paymentAmount;
  final int creditCount;
  final double creditAmount;

  TransactionStats({
    required this.paymentCount,
    required this.paymentAmount,
    required this.creditCount,
    required this.creditAmount,
  });
}

class TransactionService {
  final Stream<List<Map<String, dynamic>>> transactionStream;

  TransactionService(this.transactionStream);

  static double calculateBalance(List<Map<String, dynamic>> transactionsList) {
    double userBalance = 0;

    for (var transaction in transactionsList) {
      if (transaction['type'] == 'Credit') {
        userBalance -= (transaction['amount'] as num).toDouble();
      } else if (transaction['type'] == 'Payment') {
        userBalance += (transaction['amount'] as num).toDouble();
      }
    }

    return userBalance;
  }

  static TransactionStats calculateCustomerTransactionStats(
      List<Map<String, dynamic>> transactionsList) {
    int paymentCount = 0;
    double paymentAmount = 0.0;
    int creditCount = 0;
    double creditAmount = 0.0;

    for (var transaction in transactionsList) {
      if (transaction['type'] == 'Payment') {
        paymentCount++;
        paymentAmount += transaction['amount'];
      } else if (transaction['type'] == 'Credit') {
        creditCount++;
        creditAmount += transaction['amount'];
      }
    }

    return TransactionStats(
      paymentCount: paymentCount,
      paymentAmount: paymentAmount,
      creditCount: creditCount,
      creditAmount: creditAmount,
    );
  }

  Stream<TransactionStats> get transactionStatsStream => transactionStream
      .map((transactions) => calculateCustomerTransactionStats(transactions));

  Stream<double> get balanceStream =>
      transactionStream.map((transactions) => calculateBalance(transactions));
}
