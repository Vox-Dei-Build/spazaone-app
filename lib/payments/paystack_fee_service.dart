import 'package:cloud_functions/cloud_functions.dart';

class PaystackFeeQuote {
  final double amount;
  final String method;
  final double feeExVat;
  final double vat;
  final double feeInclVat;
  final double payoutFeeExVat;
  final double payoutVat;
  final double payoutFeeInclVat;
  final double totalFeesInclVat;
  final double netToMerchant;

  PaystackFeeQuote.fromMap(Map data)
      : amount = (data['amount'] as num).toDouble(),
        method = data['method'] as String,
        feeExVat = (data['feeExVat'] as num).toDouble(),
        vat = (data['vat'] as num).toDouble(),
        feeInclVat = (data['feeInclVat'] as num).toDouble(),
        payoutFeeExVat = (data['payoutFeeExVat'] as num).toDouble(),
        payoutVat = (data['payoutVat'] as num).toDouble(),
        payoutFeeInclVat = (data['payoutFeeInclVat'] as num).toDouble(),
        totalFeesInclVat = (data['totalFeesInclVat'] as num).toDouble(),
        netToMerchant = (data['netToMerchant'] as num).toDouble();
}

class PaystackFeeService {
  static Future<PaystackFeeQuote> quote({
    required double amountZar,
    required String method, // 'local_card' | 'eft' | 'international'
    bool includePayout = false,
  }) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('getPaystackQuote');
    final res = await callable.call({
      'amountZar': amountZar,
      'method': method,
      'includePayout': includePayout,
    });
    return PaystackFeeQuote.fromMap(res.data as Map);
  }
}
