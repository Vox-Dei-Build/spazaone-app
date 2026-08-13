import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/sales/widgets/online_commerce_hub.dart';
import 'package:pasella/services/payment_setup_service.dart';

void main() {
  test('effective capability is the intersection of client and server gates',
      () {
    const serverReady = MerchantPaymentCapability(
      ready: true,
      reason: 'ready',
      channels: ['card', 'eft'],
    );
    const serverBlocked = MerchantPaymentCapability(
      ready: false,
      reason: 'global_suspended',
      channels: ['card'],
    );

    final clientBlocked = effectiveCommerceCapability(
      clientEnabled: false,
      server: serverReady,
    );
    expect(clientBlocked.ready, isFalse);
    expect(clientBlocked.reason, 'client_disabled');
    expect(clientBlocked.channels, isEmpty);

    final backendBlocked = effectiveCommerceCapability(
      clientEnabled: true,
      server: serverBlocked,
    );
    expect(backendBlocked.ready, isFalse);
    expect(backendBlocked.reason, 'global_suspended');
    expect(backendBlocked.channels, isEmpty);

    final ready = effectiveCommerceCapability(
      clientEnabled: true,
      server: serverReady,
    );
    expect(ready.ready, isTrue);
    expect(ready.channels, ['card', 'eft']);
  });
}
