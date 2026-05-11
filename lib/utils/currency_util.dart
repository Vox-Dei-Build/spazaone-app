// currency_util.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pasella/utils/transaction_util.dart';

class CurrencyUtil {
  static final _formatCurrency = NumberFormat.simpleCurrency(locale: 'en_ZA');

  static String format(double amount) {
    return _formatCurrency.format(amount);
  }

  /// SMS-safe currency formatter.
  ///
  /// `format(...)` uses `NumberFormat.simpleCurrency(locale: 'en_ZA')`, which
  /// produces strings like `R1\u00A0234,56`. The thousands separator is
  /// **U+00A0 NO-BREAK SPACE**, which is not in the GSM-7 default alphabet.
  /// Any U+00A0 in an SMS body forces the entire message into UCS-2
  /// segmentation (70 chars/segment vs 160), silently roughly doubling the
  /// per-send cost on every transactional SMS where `amount` or `balance` is
  /// >= R1 000. See `docs/openclaw/pas-sms-01-template-segment-audit.md` (F-2).
  ///
  /// This formatter renders the same value as ASCII-only GSM-7-safe text
  /// (no thousands separator, comma decimal) so that substituting it into an
  /// SMS body does not flip GSM-7 → UCS-2:
  ///
  /// ```
  /// formatForSms(150.00)    => 'R150,00'
  /// formatForSms(1250.00)   => 'R1250,00'   // no U+00A0
  /// formatForSms(12500.00)  => 'R12500,00'
  /// formatForSms(-150.00)   => '-R150,00'
  /// ```
  ///
  /// Use this **only** for strings that are bound for SMS bodies. UI surfaces
  /// (wallet, transaction lists, ledger, etc.) should keep `format(...)` so
  /// merchants still see locale-correct thousands separators on screen.
  static String formatForSms(double amount) {
    final negative = amount < 0;
    final absolute = amount.abs();
    final whole = absolute.truncate();
    final cents = ((absolute - whole) * 100).round();
    // Guard against floating-point overflow on the cents (e.g. 0.999999... -> 100).
    final normalisedWhole = cents == 100 ? whole + 1 : whole;
    final normalisedCents = cents == 100 ? 0 : cents;
    final centsStr = normalisedCents.toString().padLeft(2, '0');
    final body = 'R$normalisedWhole,$centsStr';
    return negative ? '-$body' : body;
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
