// currency_util.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pasella/utils/transaction_util.dart';

class CurrencyUtil {
  static final _formatCurrency = NumberFormat.simpleCurrency(locale: 'en_ZA');

  static String format(double amount) {
    return _formatCurrency.format(amount);
  }

  static Future<double> fetchCurrentBalanceForCustomer(
      String currentUserId, String customerId) async {
    List<Map<String, dynamic>> transactionsList =
        await fetchTransactionsForCustomer(currentUserId, customerId);
    return TransactionService.calculateBalance(transactionsList);
  }

  static Future<List<Map<String, dynamic>>> fetchTransactionsForCustomer(
      String currentUserId, String customerId) async {
    QuerySnapshot querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('customers')
        .doc(customerId)
        .collection('transactions')
        .get();

    return querySnapshot.docs.map((doc) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;
      if (data['date'] is Timestamp) {
        data['date'] = (data['date'] as Timestamp).toDate().toIso8601String();
      }
      return data;
    }).toList();
  }
}
