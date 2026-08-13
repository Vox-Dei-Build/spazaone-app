import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/payment_setup_service.dart';

void main() {
  test('parses the four buyer-safe capability states and channels', () {
    final overview = MerchantPaymentOverview.fromMap({
      'readiness': {'enabled': false, 'reason': 'legacy'},
      'paymentsV2': {
        'schemaVersion': 2,
        'campaignCredits': {
          'ready': true,
          'reason': 'ready',
          'channels': ['card', 'eft'],
        },
        'ownedOrders': {
          'ready': false,
          'reason': 'merchant_not_enabled',
          'channels': <String>[],
        },
        'accountPayments': {
          'ready': true,
          'reason': 'ready',
          'channels': ['capitec_pay'],
        },
        'supplierOrders': {
          'ready': false,
          'reason': 'capability_disabled',
          'channels': <String>[],
        },
      },
      'profile': {'maskedAccount': '•••• 1234'},
      'settlements': <dynamic>[],
    });

    expect(overview.paymentsV2.schemaVersion, 2);
    expect(overview.paymentsV2.campaignCredits.ready, isTrue);
    expect(overview.paymentsV2.campaignCredits.channels, ['card', 'eft']);
    expect(overview.enabled, isFalse);
    expect(overview.reason, 'merchant_not_enabled');
    expect(overview.profile.maskedAccount, '•••• 1234');
  });

  test('legacy readiness is only an owned-order compatibility alias', () {
    final overview = MerchantPaymentOverview.fromMap({
      'readiness': {'enabled': true, 'reason': 'ready'},
    });

    expect(overview.paymentsV2.ownedOrders.ready, isTrue);
    expect(overview.paymentsV2.ownedOrders.channels, isEmpty);
    expect(overview.paymentsV2.campaignCredits.ready, isFalse);
    expect(overview.paymentsV2.accountPayments.ready, isFalse);
    expect(overview.paymentsV2.supplierOrders.ready, isFalse);
  });
}
