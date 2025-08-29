import 'package:flutter/material.dart';
import '../../utils/currency.dart';
import '../paystack_fee_service.dart';

class PaystackFeeBreakdownCard extends StatelessWidget {
  final PaystackFeeQuote quote;
  final String title;

  const PaystackFeeBreakdownCard({
    super.key,
    required this.quote,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <_KV>[
      _KV('Amount', zar(quote.amount)),
      _KV('Processing fee (incl. VAT)', zar(quote.feeInclVat)),
      if (quote.payoutFeeInclVat > 0)
        _KV('Payout fee (incl. VAT)', zar(quote.payoutFeeInclVat)),
      _KV('Total fees', zar(quote.totalFeesInclVat)),
      _KV('You receive', zar(quote.netToMerchant)),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...rows.map(
                (kv) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(kv.k, style: TextStyle(color: Colors.grey[700])),
                      Text(
                        kv.v,
                        style: TextStyle(
                          fontWeight: kv.k == 'You receive'
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
      ),
    );
  }
}

class _KV {
  final String k;
  final String v;
  _KV(this.k, this.v);
}
