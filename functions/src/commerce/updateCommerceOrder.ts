import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { assertStoreAccess } from "../stores/storeAccess";
import {
  CommerceOrderAction,
  paymentStatusAfterAction,
  targetStatusForAction,
} from "./domain";
import { notifyCommerceOrder } from "./notifications";

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

    const trackingCarrier = optionalText(data?.trackingCarrier, 100);
    const trackingNumber = optionalText(data?.trackingNumber, 160);
    const trackingUrl = optionalText(data?.trackingUrl, 500);
    const supplierOrderId = optionalText(data?.supplierOrderId, 200);
    const manualPaymentNote = optionalText(data?.manualPaymentNote, 200);
    if (action === "confirm_manual_payment" && !manualPaymentNote) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Add the payment method or reference used by the buyer.",
      );
    }
    if (
      action === "submit_for_fulfilment" &&
      beforeData.supplierId === "cj_dropshipping" &&
      !supplierOrderId
    ) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Add the CJ order number after placing the supplier order.",
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

    let notice: Parameters<typeof notifyCommerceOrder>[0] | null = null;
    let resultStatus = "";
    try {
      await db.runTransaction(async (tx) => {
        const current = await tx.get(orderRef);
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
            carrier: trackingCarrier,
            number: trackingNumber,
            url: trackingUrl,
          };
        } else if (action === "mark_delivered") {
          update.deliveredAt = now;
        } else if (action === "cancel") {
          update.cancelledAt = now;
          update.cancellation = {
            reason,
            actorUid: context.auth?.uid,
          };
        } else if (action === "mark_refunded") {
          update.refundedAt = now;
          update.refund = {
            reference: optionalText(data?.refundReference, 200),
            note: optionalText(data?.refundNote, 500),
            recordedBy: context.auth?.uid,
          };
        }
        tx.update(orderRef, update);
        notice = {
          orderId,
          sellerId,
          buyerName: String(currentData.buyer?.name ?? "Customer"),
          buyerPhone: String(currentData.buyer?.phone ?? ""),
          status: next,
          paymentMethod: String(currentData.paymentMethod ?? "paystack"),
          amountDueMinor: Number(currentData.amountDueMinor ?? 0),
          trackingCarrier: trackingCarrier ?? undefined,
          trackingNumber: trackingNumber ?? undefined,
        };
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
    if (notice) {
      await notifyCommerceOrder(notice).catch((error) => {
        console.error("[commerce] status notification failed", error);
      });
    }
    return { orderId, status: resultStatus };
  },
);
