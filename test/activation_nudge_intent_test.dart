import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/services/activation_nudge_intent_bus.dart';

void main() {
  test('activation intent parses dashboard query params', () {
    final intent = ActivationNudgeIntent.fromUri(
      Uri.parse(
        '/dashboard?activation=link_product_transaction&customerId=c1&nudgeType=first_link',
      ),
    );

    expect(intent?.action, ActivationNudgeAction.linkProductTransaction);
    expect(intent?.customerId, 'c1');
    expect(intent?.nudgeType, 'first_link');
  });

  test('activation intent parses FCM data fallback', () {
    final intent = ActivationNudgeIntent.fromUri(
      Uri.parse('/dashboard'),
      data: {
        'activationAction': 'add_first_product',
        'nudgeId': 'nudge-1',
      },
    );

    expect(intent?.action, ActivationNudgeAction.addProduct);
    expect(intent?.nudgeId, 'nudge-1');
  });

  test('activation intent parses ordering link action', () {
    final intent = ActivationNudgeIntent.fromUri(
      Uri.parse('/dashboard?activation=share_ordering_link'),
    );

    expect(intent?.action, ActivationNudgeAction.shareOrderingLink);
  });

  test('activation intent ignores unknown actions', () {
    final intent = ActivationNudgeIntent.fromUri(
      Uri.parse('/dashboard?activation=unknown'),
    );

    expect(intent, isNull);
  });
}
