import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/wallet/wallet.dart';
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
      'verification': {
        'stage': 'submitted',
        'reason': 'authorization_review_pending',
        'requestStatus': 'authorization_required',
        'hasSavedBankingDetails': true,
        'requestedAtMs': 1234,
      },
      'settlements': <dynamic>[],
    });

    expect(overview.paymentsV2.schemaVersion, 2);
    expect(overview.paymentsV2.campaignCredits.ready, isTrue);
    expect(overview.paymentsV2.campaignCredits.channels, ['card', 'eft']);
    expect(overview.enabled, isFalse);
    expect(overview.reason, 'merchant_not_enabled');
    expect(overview.profile.maskedAccount, '•••• 1234');
    expect(overview.verification.stage, 'submitted');
    expect(overview.verification.awaitingAuthorization, isTrue);
    expect(overview.verification.requestedAtMs, 1234);
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
    expect(overview.verification.stage, 'not_started');
  });

  test('campaign top-up methods are the server and client intersection', () {
    const capability = MerchantPaymentCapability(
      ready: true,
      reason: 'ready',
      channels: ['qr', 'unknown_future_channel', 'card', 'qr'],
    );

    expect(supportedCampaignTopupChannels(capability), ['card', 'qr']);
  });

  test('campaign top-up methods fail closed for a disabled capability', () {
    const capability = MerchantPaymentCapability(
      ready: false,
      reason: 'capability_disabled',
      channels: ['card', 'eft'],
    );

    expect(supportedCampaignTopupChannels(capability), isEmpty);
  });
}
