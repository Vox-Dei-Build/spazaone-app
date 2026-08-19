import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/sales/widgets/online_commerce_hub.dart';
import 'package:pasella/services/payment_setup_service.dart';

void main() {
  test('supplier manual release no longer requires online readiness', () {
    final payments = MerchantPaymentsV2.fromMap(
      const {
        'schemaVersion': 2,
        'supplierOrders': {
          'ready': false,
          'reason': 'provider_disabled',
          'channels': <String>[],
        },
        'supplierOrdersRequireOnlinePayment': false,
      },
      legacyReadiness: const {},
    );

    expect(payments.supplierOrders.ready, isFalse);
    expect(payments.supplierOrdersRequireOnlinePayment, isFalse);
    expect(
      onlineCommerceSetupRequired(
        payments: payments,
        ownedClientEnabled: true,
        supplierClientEnabled: true,
      ),
      isFalse,
    );
  });

  test('older capability responses keep the online requirement fail-closed',
      () {
    final payments = MerchantPaymentsV2.fromMap(
      const {'schemaVersion': 2},
      legacyReadiness: const {},
    );

    expect(payments.supplierOrdersRequireOnlinePayment, isTrue);
  });
}
