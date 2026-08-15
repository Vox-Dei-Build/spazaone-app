import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/ecommerce/orders/data/order_action_policy.dart';

void main() {
  test('manual EFT must be paid before pickup collection', () {
    expect(
      canMarkManualOrderPaymentReceived(
        paymentMethod: 'EFT',
        isPaid: false,
        isTerminal: false,
        isPendingMerchantReview: false,
        hasHandedOver: false,
      ),
      isTrue,
    );
    expect(
      canMarkPickupOrderCollected(
        paymentMethod: 'EFT',
        isPaid: false,
        isBnpl: false,
        isBnplApproved: false,
        isCollected: false,
        isDelivery: false,
        isPendingMerchantReview: false,
        isTerminal: false,
      ),
      isFalse,
    );
    expect(
      canMarkPickupOrderCollected(
        paymentMethod: 'EFT',
        isPaid: true,
        isBnpl: false,
        isBnplApproved: false,
        isCollected: false,
        isDelivery: false,
        isPendingMerchantReview: false,
        isTerminal: false,
      ),
      isTrue,
    );
  });

  test('cash pickup remains a single handover and receipt action', () {
    expect(
      canMarkPickupOrderCollected(
        paymentMethod: 'cash',
        isPaid: false,
        isBnpl: false,
        isBnplApproved: false,
        isCollected: false,
        isDelivery: false,
        isPendingMerchantReview: false,
        isTerminal: false,
      ),
      isTrue,
    );
    expect(
      canMarkManualOrderPaymentReceived(
        paymentMethod: 'cash',
        isPaid: false,
        isTerminal: false,
        isPendingMerchantReview: false,
        hasHandedOver: false,
      ),
      isFalse,
    );
  });

  test('only approved Pay Later may advance while still unpaid', () {
    expect(
      canAdvanceOrderFulfillment(
        paymentMethod: 'bnpl',
        isPaid: false,
        isBnpl: true,
        isBnplApproved: false,
      ),
      isFalse,
    );
    expect(
      canAdvanceOrderFulfillment(
        paymentMethod: 'bnpl',
        isPaid: false,
        isBnpl: true,
        isBnplApproved: true,
      ),
      isTrue,
    );
    expect(
      canAdvanceOrderFulfillment(
        paymentMethod: 'paystack',
        isPaid: false,
        isBnpl: false,
        isBnplApproved: false,
      ),
      isFalse,
    );
  });
}
