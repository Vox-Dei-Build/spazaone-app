import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/analytics_event.dart';

void main() {
  test('sale completed carries product linkage properties', () {
    final event = SaleCompleted(
      amountBucket: '50-200',
      isCredit: true,
      customerIsExisting: true,
      hasProducts: true,
      productCountBucket: productCountBucket(2),
    );

    expect(event.properties['has_products'], isTrue);
    expect(event.properties['product_count_bucket'], '2-3');
  });

  test('payment received carries a stable reconciliation key', () {
    const event = PaymentReceived(
      transactionId: 'ledger_payment:transaction-1',
      amountBucket: '50-200',
      source: 'ledger_repayment',
      method: 'manual',
    );

    expect(event.name, 'payment_received');
    expect(event.properties, {
      'transaction_id': 'ledger_payment:transaction-1',
      'amount_bucket': '50-200',
      'source': 'ledger_repayment',
      'method': 'manual',
    });
  });

  test('product count bucket is coarse and bounded', () {
    expect(productCountBucket(0), '0');
    expect(productCountBucket(1), '1');
    expect(productCountBucket(3), '2-3');
    expect(productCountBucket(5), '4-5');
    expect(productCountBucket(6), '6+');
  });

  test('customer created carries customer depth bucket', () {
    final event = CustomerCreated(
      hasImage: false,
      customerCountBucket: customerCountBucket(10),
    );

    expect(event.properties['customer_count_bucket'], '10+');
  });

  test('customer count bucket covers activation milestones', () {
    expect(customerCountBucket(0), '0');
    expect(customerCountBucket(1), '1');
    expect(customerCountBucket(4), '2-4');
    expect(customerCountBucket(9), '5-9');
    expect(customerCountBucket(10), '10+');
  });

  test('ordering link events stay coarse and PII-free', () {
    final created = OrderingLinkCreated(
      source: 'activation_nudge',
      regenerated: false,
    );
    final shared = OrderingLinkShared(channel: 'whatsapp');

    expect(created.name, 'ordering_link_created');
    expect(created.properties, {
      'source': 'activation_nudge',
      'regenerated': false,
    });
    expect(shared.properties, {'channel': 'whatsapp'});
  });
}
