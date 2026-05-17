import 'package:flutter_test/flutter_test.dart';
import 'package:pasella/pages/ecommerce/orders/data/payment_service.dart';

/// PAS-UX-07 — Order-action state semantics regression guard.
///
/// The previous `payment_service.dart` (pre-PAS-UX-07) returned a
/// snackbar with text `'Updated'` whenever the action label map missed
/// — silently hiding mis-routed actions behind a friendly word. The
/// merchant could not tell what state the order had landed in.
///
/// These tests pin the contract:
///   * Every server-whitelisted `paymentAction` has an explicit
///     past-tense state label.
///   * Every action also declares whether it triggers a downstream
///     customer message (and therefore a wallet debit) — so callers can
///     sequence the "Notifying customer…" intermediate snackbar
///     deterministically.
///   * The state-label map and the messaging-intent map have the same
///     key set. A new action added to one without the other is a bug.
void main() {
  // Source of truth: the server whitelist
  // `functions/src/ecommerce/updateOrderPayment.ts:5`.
  const serverAllowedActions = <String>{
    'ACCEPT_BNPL',
    'REJECT_BNPL',
    'MARK_CASH_RECEIVED',
    'MARK_COLLECTED',
    'SETTLE_BNPL',
    'CANCEL_ORDER',
  };

  group('PaymentService state labels', () {
    test('every server-allowed action has an explicit state label', () {
      for (final action in serverAllowedActions) {
        expect(
          PaymentService.actionStateLabels.containsKey(action),
          isTrue,
          reason:
              'Missing merchant-facing state label for "$action". '
              'Add it to PaymentService.actionStateLabels — never let it fall '
              'through to a vague success message.',
        );
        final label = PaymentService.actionStateLabels[action]!;
        expect(
          label.isNotEmpty,
          isTrue,
          reason: '"$action" has an empty label',
        );
        // The pre-PAS-UX-07 vague fallback. If it shows up here, the
        // ambiguity is back.
        expect(
          label.toLowerCase(),
          isNot(equals('updated')),
          reason: '"$action" must not be labelled "Updated"',
        );
      }
    });

    test('state-label map and message-intent map have the same keys', () {
      expect(
        PaymentService.actionStateLabels.keys.toSet(),
        equals(PaymentService.actionTriggersMessage.keys.toSet()),
        reason:
            'Every action with a state label must also declare its messaging '
            'intent. Otherwise the order detail page cannot decide whether '
            'to show "Notifying customer…" between the write and the send.',
      );
    });

    test('label map exactly mirrors the server whitelist', () {
      expect(
        PaymentService.actionStateLabels.keys.toSet(),
        equals(serverAllowedActions),
        reason:
            'Client label map drifted from server whitelist. Update both in '
            'lockstep (functions/src/ecommerce/updateOrderPayment.ts).',
      );
    });

    test('all known actions currently trigger a customer message', () {
      // All six template keys in OrderStatusMessagingService have a
      // matching template. If a future action is added that should be
      // silent (no customer notification), update this test and the
      // intent map together — never leave the merchant guessing.
      for (final action in serverAllowedActions) {
        expect(
          PaymentService.actionTriggersMessage[action],
          isTrue,
          reason: '"$action" silently dropped its messaging intent.',
        );
      }
    });
  });
}
