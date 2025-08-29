import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/utils/currency_util.dart';

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

// ---- Helpers: make all math & formatting type-safe ----
double toDouble(dynamic v, {double fallback = 0.0}) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

int toInt(dynamic v, {int fallback = 0}) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double sizeConfigUtil(dynamic v, {double fallback = 1.0}) {
  // Safely coerce SizeConfig multipliers (which should be num/double) to double.
  if (v is num) return v.toDouble();
  return fallback;
}

String formatDateish(dynamic v) {
  if (v is Timestamp) return v.toDate().toString();
  if (v is DateTime) return v.toString();
  if (v is String && v.isNotEmpty) return v;
  return '—';
}

String formatMoney(dynamic v) {
  // CurrencyUtil.format usually expects num/double
  return CurrencyUtil.format(toDouble(v));
}
