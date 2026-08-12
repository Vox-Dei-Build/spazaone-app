import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { assertStoreAccess } from "../stores/storeAccess";
import {
  canManuallyConfirmCommerceRefund,
  CommerceOrderAction,
  paymentStatusAfterAction,
  targetStatusForAction,
} from "./domain";
import {
  CommerceNotificationResult,
  deliverCommerceOrderNotificationOutbox,
  enqueueCommerceOrderNotification,
} from "./notifications";
import { validatedTrackingUrl } from "./tracking";
import {
  executePaystackRefundV2,
  refundCaseDocumentId,
} from "../payments/v2/refunds";

function requiredText(value: unknown, field: string, max = 160): string {
  const text = String(value ?? "").trim();
  if (!text || text.length > max) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `${field} is required.`,
    );
  }
  return text;
}

function optionalText(value: unknown, max = 200): string | null {
  const text = String(value ?? "").trim();
  return text ? text.slice(0, max) : null;
}

function isSpazaAdmin(context: functions.https.CallableContext): boolean {
  return context.auth?.token.spazaAdmin === true;
}

/** Applies one guarded manual fulfilment/refund transition. */
export const updateCommerceOrder = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in is required.",
      );
    }
    const orderId = requiredText(data?.orderId, "orderId", 128);
    const action = requiredText(
      data?.action,
      "action",
      64,
    ) as CommerceOrderAction;
    const orderRef = db.doc(`commerceOrders/${orderId}`);
    const before = await orderRef.get();
    if (!before.exists) {
      throw new functions.https.HttpsError("not-found", "Order not found.");
    }
    const beforeData = before.data() ?? {};
    const sellerId = requiredText(beforeData.sellerId, "sellerId", 128);
    let actorRole = "spaza_admin";
    if (!isSpazaAdmin(context)) {
      const managerOnly = [
        "confirm_manual_payment",
        "cancel",
        "mark_refunded",
      ].includes(action);
      const access = await assertStoreAccess(
        context.auth.uid,
        sellerId,
        managerOnly ? ["owner", "admin"] : undefined,
      );
      actorRole = access.role;
    }

    const trackingNumber = optionalText(data?.trackingNumber, 160);
    let trackingUrl: string | null;
    try {
      trackingUrl = validatedTrackingUrl(data?.trackingUrl);
    } catch (_) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Tracking link must start with https:// or http:// and be a valid link.",
      );
    }
    const supplierOrderId = optionalText(data?.supplierOrderId, 200);
    const manualPaymentNote = optionalText(data?.manualPaymentNote, 200);
    if (action === "confirm_manual_payment" && !manualPaymentNote) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Add the payment method or reference used by the buyer.",
      );
    }
    if (
      action === "mark_refunded" &&
      !canManuallyConfirmCommerceRefund(beforeData.payment?.provider)
    ) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Online refunds complete only after the payment provider confirms them.",
      );
    }
    if (
      action === "submit_for_fulfilment" &&
      beforeData.supplierId === "cj_dropshipping" &&
      !supplierOrderId
    ) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Add the delivery order number after placing the order.",
      );
    }
    if (action === "mark_shipped" && !trackingNumber) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Add a tracking number before marking the order shipped.",
      );
    }
    const reason = optionalText(data?.reason, 500);
    if (action === "cancel" && !reason) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Add a cancellation reason.",
      );
    }

    let refundCaseId = "";
    let refundIntentId = "";
    let refundAmountMinor = 0;
    const refundIdempotencyKey = `supplier-order-cancel:${orderId}`;
    if (
      action === "cancel" &&
      String(beforeData.payment?.provider ?? "") === "paystack" &&
      String(beforeData.paymentStatus ?? "") === "paid"
    ) {
      // Validate the transition before creating a money-moving operations
      // case. A concurrent state change is checked again in the transaction.
      targetStatusForAction(
        beforeData.status,
        action,
        beforeData.paymentStatus,
      );
      refundIntentId = requiredText(
        beforeData.paymentIntentId,
        "paymentIntentId",
        200,
      );
      refundAmountMinor = Number(beforeData.amountDueMinor);
      if (!Number.isSafeInteger(refundAmountMinor) || refundAmountMinor <= 0) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "The verified payment amount is unavailable.",
        );
      }
      refundCaseId = refundCaseDocumentId({
        intentId: refundIntentId,
        idempotencyKey: refundIdempotencyKey,
      });
    }

    let notificationId = "";
    let resultStatus = "";
    try {
      await db.runTransaction(async (tx) => {
        const refundIntentRef = refundCaseId
          ? db.doc(`paymentIntents/${refundIntentId}`)
          : null;
        const refundCaseRef = refundCaseId
          ? db.doc(`refundCases/${refundCaseId}`)
          : null;
        const [current, refundIntent, existingRefundCase] = await Promise.all([
          tx.get(orderRef),
          refundIntentRef ? tx.get(refundIntentRef) : Promise.resolve(null),
          refundCaseRef ? tx.get(refundCaseRef) : Promise.resolve(null),
        ]);
        if (!current.exists) throw new Error("ORDER_NOT_FOUND");
        const currentData = current.data() ?? {};
        const next = targetStatusForAction(
          currentData.status,
          action,
          currentData.paymentStatus,
        );
        const nextPaymentStatus = paymentStatusAfterAction(
          currentData.paymentStatus,
          action,
        );
        const now = FieldValue.serverTimestamp();
        if (refundIntentRef && refundCaseRef && refundIntent) {
          if (!refundIntent.exists) throw new Error("INTENT_NOT_FOUND");
          const intentData = refundIntent.data() ?? {};
          if (
            intentData.purpose !== "supplier_order" ||
            intentData.businessBinding?.id !== orderId ||
            !["paid", "refund_pending"].includes(
              String(intentData.status ?? ""),
            )
          ) {
            throw new Error("SUPPLIER_REFUND_BINDING_MISMATCH");
          }
          if (existingRefundCase?.exists) {
            if (existingRefundCase.get("intentId") !== refundIntentId) {
              throw new Error("REFUND_IDEMPOTENCY_MISMATCH");
            }
            refundAmountMinor = Number(
              existingRefundCase.get("refundAmountMinor"),
            );
          } else {
            const expected = Number(intentData.expectedAmountMinor);
            const confirmed = Number(intentData.confirmedRefundMinor ?? 0);
            const requested = Number(intentData.requestedRefundMinor ?? 0);
            const remaining = expected - confirmed - requested;
            if (
              expected !== Number(currentData.amountDueMinor) ||
              ![confirmed, requested].every(Number.isSafeInteger) ||
              !Number.isSafeInteger(remaining) ||
              remaining <= 0
            ) {
              throw new Error("REFUND_AMOUNT_EXCEEDS_REMAINING");
            }
            refundAmountMinor = remaining;
            tx.create(refundCaseRef, {
              refundCaseId,
              intentId: refundIntentId,
              commerceOrderId: orderId,
              refundAmountMinor,
              currency: "ZAR",
              status: "requested",
              provider: "paystack",
              providerConfirmed: false,
              reason: reason ?? "supplier_order_cancelled",
              owner: "operations",
              attemptCount: 0,
              schemaVersion: 2,
              createdAt: now,
              updatedAt: now,
            });
            tx.update(refundIntentRef, {
              status: "refund_pending",
              requestedRefundMinor: FieldValue.increment(refundAmountMinor),
              refundProviderConfirmed: false,
              updatedAt: now,
            });
          }
        }
        const update: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> =
          {
            status: next,
            fulfilmentStatus: next,
            paymentStatus: nextPaymentStatus,
            updatedAt: now,
            statusHistory: FieldValue.arrayUnion({
              from: String(currentData.status),
              to: next,
              action,
              actorUid: context.auth?.uid,
              actorRole,
              reason,
              at: new Date().toISOString(),
            }),
          };
        if (action === "confirm_manual_payment") {
          update.paidAt = now;
          update.manualPayment = {
            note: manualPaymentNote,
            confirmedBy: context.auth?.uid,
            confirmedAt: now,
          };
        } else if (action === "submit_for_fulfilment") {
          update.submittedForFulfilmentAt = now;
          update.supplierOrder = {
            provider: String(currentData.supplierId ?? ""),
            orderId: supplierOrderId,
            recordedBy: context.auth?.uid,
            recordedAt: now,
          };
        } else if (action === "mark_shipped") {
          update.shippedAt = now;
          update.tracking = {
            carrier: "",
            number: trackingNumber,
            url: trackingUrl,
          };
        } else if (action === "mark_delivered") {
          update.deliveredAt = now;
        } else if (action === "cancel") {
          update.cancelledAt = now;
          if (refundCaseId) update.refundCaseId = refundCaseId;
          update.cancellation = {
            reason,
            actorUid: context.auth?.uid,
          };
        } else if (action === "mark_refunded") {
          update.refundedAt = now;
          update.refund = {
            mode: "manual_payment_return",
            providerConfirmed: false,
            reference: optionalText(data?.refundReference, 200),
            note: optionalText(data?.refundNote, 500),
            recordedBy: context.auth?.uid,
          };
        }
        tx.update(orderRef, update);
        notificationId = enqueueCommerceOrderNotification(tx, {
          orderId,
          sellerId,
          customerId: String(currentData.customerId ?? ""),
          buyerName: String(currentData.buyer?.name ?? "Customer"),
          buyerPhone: String(currentData.buyer?.phone ?? ""),
          status: next,
          paymentMethod: String(currentData.paymentMethod ?? "paystack"),
          amountDueMinor: Number(currentData.amountDueMinor ?? 0),
          trackingNumber: trackingNumber ?? undefined,
          trackingUrl: trackingUrl ?? undefined,
        });
        resultStatus = next;
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      if (
        [
          "TRANSITION_INVALID",
          "MANUAL_PAYMENT_NOT_PENDING",
          "REFUND_NOT_PENDING",
          "STATUS_INVALID",
          "ACTION_INVALID",
        ].includes(code)
      ) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "That order action is not allowed in its current status.",
        );
      }
      throw error;
    }
    if (refundCaseId) {
      await executePaystackRefundV2(refundCaseId).catch((error) => {
        console.error("[commerce] refund submission queued", {
          refundCaseId,
          code: error instanceof Error ? error.message : "unknown",
        });
      });
    }
    let notification: CommerceNotificationResult = {
      notificationId,
      customer: "queued",
      buyerResult: "pending",
      sellerResult: "pending",
    };
    try {
      notification =
        await deliverCommerceOrderNotificationOutbox(notificationId);
    } catch (error) {
      // The transition and outbox item committed together. A transient send or
      // result-write failure must not be reported as a customer notification.
      console.error("[commerce] status notification queued", error);
    }
    return { orderId, status: resultStatus, notification };
  },
);
