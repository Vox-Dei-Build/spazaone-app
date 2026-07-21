import 'package:cloud_functions/cloud_functions.dart';
import 'package:pasella/services/store_session.dart';
import 'package:flutter/foundation.dart';

/// PAS-UX-07 — Order action state semantics.
///
/// Each merchant action against the order flow is a discrete state
/// transition. The previous implementation surfaced every successful
/// transition as the snackbar text `'Updated'` whenever the label map
/// missed (`payment_service.dart` :41), which left the merchant
/// guessing what just changed and whether anything was sent to the
/// customer. It also raced the asynchronous WhatsApp template + wallet
/// debit that fires from `OrderDetailPage._callPayment` immediately
/// after this call — the user saw "Cash received" before the customer
/// was actually notified or the wallet was charged.
///
/// We now:
///   * never fall back to a vague "Updated" — unmapped actions are an
///     explicit programming error and are reported as such;
///   * return a structured result that names the *new order state*
///     (the post-write truth) so the caller can sequence the post-action
///     UI around the asynchronous "send + charge" step explicitly;
///   * expose the state copy as static maps that are unit-testable
///     without a Firebase context.
enum OrderActionStatus {
  /// Action was accepted by the backend and the order's post-action state
  /// is now the value described by `OrderPaymentResult.stateLabel`.
  success,

  /// Backend rejected the action (validation, permission, etc.). No
  /// state transition happened.
  serverError,

  /// Pre-flight failure (signed out, missing args). No call was made.
  notAttempted,

  /// Unknown failure path. Worth surfacing distinctly so merchants
  /// don't conflate it with a clean rejection.
  unexpectedError,
}

/// Structured outcome of a server `updateOrderPayment` call.
///
/// `stateLabel` is the short merchant-facing string that names the new
/// state of the order (e.g. "Marked as paid", "Order cancelled"). It is
/// intentionally past-tense because by the time the caller sees this
/// result, the server write has already committed.
///
/// `sendIntent` describes whether the action triggers a downstream
/// customer message + balance debit (sent silently by
/// `OrderStatusMessagingService.sendStatusMessage`). The caller can use
/// this to decide whether to show a follow-up "Notifying customer…"
/// state on the same snackbar/toast.
class OrderPaymentResult {
  const OrderPaymentResult({
    required this.status,
    required this.stateLabel,
    required this.sendIntent,
    this.errorMessage,
  });

  final OrderActionStatus status;

  /// Past-tense, merchant-facing state name. Empty when `status` is not
  /// `success`.
  final String stateLabel;

  /// Whether the action has a downstream messaging side-effect that
  /// debits the merchant's WhatsApp/SMS wallet. Lets the caller render
  /// "Notifying customer…" without guessing.
  final bool sendIntent;

  /// Populated for non-success outcomes so the caller can show the
  /// underlying reason without re-deriving it.
  final String? errorMessage;

  bool get isSuccess => status == OrderActionStatus.success;
}

class PaymentService {
  /// Human-readable, past-tense state label for each successful
  /// `paymentAction`. Keep this list aligned with the server whitelist
  /// in `functions/src/ecommerce/updateOrderPayment.ts:5`.
  ///
  /// Visible for testing so the snackbar copy can be asserted without a
  /// Firebase context.
  @visibleForTesting
  static const Map<String, String> actionStateLabels = {
    'ACCEPT_ORDER': 'Order accepted',
    'REJECT_ORDER': 'Order rejected',
    'ASSIGN_DRIVER': 'Driver assigned',
    'UNASSIGN_DRIVER': 'Driver unassigned',
    'MARK_OUT_FOR_DELIVERY': 'Order out for delivery',
    'MARK_DELIVERED': 'Order marked delivered',
    'ACCEPT_BNPL': 'Pay Later approved',
    'REJECT_BNPL': 'Pay Later rejected',
    'MARK_CASH_RECEIVED': 'Cash received recorded',
    'MARK_COLLECTED': 'Order marked collected',
    'SETTLE_BNPL': 'Pay Later settled · marked paid',
    'CANCEL_ORDER': 'Order cancelled',
  };

  /// Whether each action triggers a downstream customer notification
  /// via `OrderStatusMessagingService.sendStatusMessage`. Must stay in
  /// lockstep with the template keys in
  /// `lib/services/order_status_messaging_service.dart:13`.
  @visibleForTesting
  static const Map<String, bool> actionTriggersMessage = {
    'ACCEPT_ORDER': true,
    'REJECT_ORDER': true,
    'ASSIGN_DRIVER': true,
    // Unassign is an internal correction. We deliberately do NOT
    // notify the customer because the next ASSIGN_DRIVER will, and a
    // "your driver was unassigned" ping is more confusing than useful.
    'UNASSIGN_DRIVER': false,
    'MARK_OUT_FOR_DELIVERY': true,
    'MARK_DELIVERED': true,
    'ACCEPT_BNPL': true,
    'REJECT_BNPL': true,
    'MARK_CASH_RECEIVED': true,
    'MARK_COLLECTED': true,
    'SETTLE_BNPL': true,
    'CANCEL_ORDER': true,
  };

  /// Calls the `updateOrderPayment` callable and returns a structured
  /// result. **Does NOT surface any UI** — the caller owns the snackbar
  /// so it can sequence post-write feedback around the asynchronous
  /// messaging step (see `OrderDetailPage._callPayment`).
  static Future<OrderPaymentResult> updateOrderPayment({
    required String orderId,
    required String action,
    Map<String, dynamic> extraData = const {},
  }) async {
    final uid = StoreSession.instance.storeId;
    if (uid.isEmpty) {
      return const OrderPaymentResult(
        status: OrderActionStatus.notAttempted,
        stateLabel: '',
        sendIntent: false,
        errorMessage: 'You must be signed in.',
      );
    }
    if (orderId.isEmpty || action.isEmpty) {
      return const OrderPaymentResult(
        status: OrderActionStatus.notAttempted,
        stateLabel: '',
        sendIntent: false,
        errorMessage: 'Missing order or action.',
      );
    }

    final stateLabel = actionStateLabels[action];
    final sendIntent = actionTriggersMessage[action] ?? false;
    if (stateLabel == null) {
      // Fail loudly. The previous "Updated" fallback hid mis-routed
      // actions behind a friendly word; that is the exact ambiguity
      // PAS-UX-07 is removing. Server still gets the call — but the
      // caller must surface a real error rather than a vague success.
      debugPrint(
        '[PaymentService] Unknown paymentAction "$action" — no state label.',
      );
    }

    try {
      final fn = FirebaseFunctions.instance.httpsCallable('updateOrderPayment');
      await fn.call({
        'merchantId': uid,
        'orderId': orderId,
        'paymentAction': action,
        ...extraData,
      });
      if (stateLabel == null) {
        return OrderPaymentResult(
          status: OrderActionStatus.unexpectedError,
          stateLabel: '',
          sendIntent: sendIntent,
          errorMessage: 'Order updated, but action "$action" is not mapped.',
        );
      }
      return OrderPaymentResult(
        status: OrderActionStatus.success,
        stateLabel: stateLabel,
        sendIntent: sendIntent,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[updateOrderPayment] code=${e.code} message=${e.message}');
      return OrderPaymentResult(
        status: OrderActionStatus.serverError,
        stateLabel: '',
        sendIntent: false,
        errorMessage: e.message ?? 'Failed to update order',
      );
    } catch (e) {
      debugPrint('[updateOrderPayment] unexpected error: $e');
      return const OrderPaymentResult(
        status: OrderActionStatus.unexpectedError,
        stateLabel: '',
        sendIntent: false,
        errorMessage: 'Unexpected error. Please try again.',
      );
    }
  }
}
