// functions/src/http/updateOrderPayment.ts
import { db, functions } from "../config/main";
import { authorizeCallableMerchantOrBot } from "../security/requestAuth";
import { FieldValue } from "firebase-admin/firestore";
import { createHash } from "crypto";
import {
  buildPaymentReceiptPatch,
  isPaymentAlreadyRecorded,
  isPaymentReceiptAction,
} from "./orderPaymentPolicy";
import {
  commerceNotificationDocumentId,
  CommerceNotificationResult,
  deliverCommerceOrderNotificationOutbox,
  enqueueCommerceOrderNotification,
  OrderNotice,
} from "../commerce/notifications";
import {
  consumeOwnedInventoryReservation,
  releaseOwnedInventoryReservation,
} from "../payments/v2/inventoryReservations";
import {
  executePaystackRefundV2,
  openRefundCaseInTransactionV2,
} from "../payments/v2/refunds";

const ALLOWED = new Set([
  "ACCEPT_ORDER",
  "REJECT_ORDER",
  "ASSIGN_DRIVER",
  "UNASSIGN_DRIVER",
  "MARK_OUT_FOR_DELIVERY",
  "MARK_DELIVERED",
  "ACCEPT_BNPL",
  "REJECT_BNPL",
  "MARK_CASH_RECEIVED",
  "MARK_COLLECTED",
  "SETTLE_BNPL",
  "CANCEL_ORDER",
]);

function canonicalNoticeStatus(action: string): string {
  switch (action) {
    case "MARK_CASH_RECEIVED":
    case "SETTLE_BNPL":
      return "paid";
    case "ACCEPT_ORDER":
    case "ASSIGN_DRIVER":
    case "UNASSIGN_DRIVER":
    case "ACCEPT_BNPL":
      return "preparing";
    case "MARK_OUT_FOR_DELIVERY":
      return "on_the_way";
    case "MARK_DELIVERED":
    case "MARK_COLLECTED":
      return "delivered";
    case "REJECT_ORDER":
    case "CANCEL_ORDER":
      return "cancelled";
    case "REJECT_BNPL":
      return "awaiting_payment";
    default:
      throw new Error("ORDER_NOTICE_ACTION_INVALID");
  }
}

function legacyOrderNotice(input: {
  merchantId: string;
  orderId: string;
  action: string;
  order: Record<string, any>;
  customer?: Record<string, any>;
}): OrderNotice {
  const customer = input.customer ?? {};
  const amountRands = Number(input.order.total ?? input.order.amount ?? 0);
  const amountDueMinor = Number.isFinite(amountRands)
    ? Math.max(0, Math.round(amountRands * 100))
    : 0;
  const driver = input.order.driver ?? {};
  const assignmentIdentity = [
    String(driver.id ?? ""),
    String(driver.phone ?? ""),
    String(driver.name ?? ""),
    input.order.driverAssignedAt instanceof Date
      ? input.order.driverAssignedAt.toISOString()
      : String(input.order.driverAssignedAt ?? ""),
  ].join(":");
  const unassignmentIdentity =
    input.order.driverUnassignedAt instanceof Date
      ? input.order.driverUnassignedAt.toISOString()
      : String(input.order.driverUnassignedAt ?? "");
  const eventKey =
    input.action === "ASSIGN_DRIVER"
      ? `assign_driver:${createHash("sha256")
          .update(assignmentIdentity)
          .digest("hex")
          .slice(0, 24)}`
      : input.action === "UNASSIGN_DRIVER"
        ? `unassign_driver:${createHash("sha256")
            .update(unassignmentIdentity)
            .digest("hex")
            .slice(0, 24)}`
        : input.action.toLowerCase();
  return {
    orderId: input.orderId,
    sellerId: input.merchantId,
    customerId: String(input.order.customerId ?? input.order.customerID ?? ""),
    buyerName: String(
      customer.name ??
        customer.fullName ??
        input.order.customerName ??
        "Customer",
    ),
    buyerPhone: String(
      customer.number ?? customer.phone ?? input.order.customerPhone ?? "",
    ),
    status: canonicalNoticeStatus(input.action),
    paymentMethod: String(
      input.order.paymentMethod ?? input.order.type ?? "manual",
    ).toLowerCase(),
    amountDueMinor,
    notifyBuyer: input.action !== "UNASSIGN_DRIVER",
    orderKind: "merchant_stock",
    eventKey,
  };
}

async function deliverLegacyOrderNotice(
  notificationId: string,
): Promise<CommerceNotificationResult> {
  if (!notificationId) {
    return {
      customer: "skipped",
      buyerResult: "skipped_no_change",
      sellerResult: "skipped_no_change",
    };
  }
  try {
    return await deliverCommerceOrderNotificationOutbox(notificationId);
  } catch (error) {
    console.error("[owned-order] notification queued", error);
    return {
      notificationId,
      customer: "queued",
      buyerResult: "pending",
      sellerResult: "pending",
    };
  }
}

/**
 * Finalizes the inventory and clears the customer's cart for a given order.
 *
 * This function is **idempotent** — it only applies stock decrements and
 * cart clearing if the order has not already been finalized.
 *
 * Steps performed inside a Firestore transaction:
 * 1. Decrement product stock quantities if defined.
 * 2. Clear all cart items and reset the cart totals.
 * 3. Mark the sale record as inventory finalized with timestamps.
 *
 * @async
 * @function finalizeInventoryOnce
 * @param {Object} opts - Options for finalizing inventory.
 * @param {string} opts.merchantId - The merchant's user ID in Firestore.
 * @param {string} opts.orderId - The order ID referencing the sale document.
 * @param {string} opts.customerId - The customer ID whose cart will be cleared.
 * @throws {Error} If the sale document is not found.
 * @return {Promise<void>} Resolves once the transaction completes successfully.
 */
async function finalizeInventoryOnce(opts: {
  merchantId: string;
  orderId: string;
  customerId: string;
}) {
  const { merchantId, orderId, customerId } = opts;

  const saleRef = db
    .collection("users")
    .doc(merchantId)
    .collection("sales")
    .doc(orderId);

  const cartDoc = db
    .collection("users")
    .doc(merchantId)
    .collection("carts")
    .doc(customerId);

  const preflight = await saleRef.get();
  if (!preflight.exists) throw new Error("SALE_NOT_FOUND");
  const reservationId = String(
    preflight.data()?.inventoryReservationId ?? "",
  ).trim();
  if (reservationId) {
    await consumeOwnedInventoryReservation({
      reservationId,
      merchantId,
      orderId,
    });
  }

  await db.runTransaction(async (tx) => {
    // --- READS (all of them) ---
    const saleSnap = await tx.get(saleRef);
    if (!saleSnap.exists) throw new Error("SALE_NOT_FOUND");

    const sale = saleSnap.data() || {};
    if (sale.inventoryFinalized) {
      // Idempotent: already finalized
      return;
    }

    const productIds: string[] = reservationId
      ? []
      : Object.keys(sale.products || {});
    const productRefs = productIds.map((pid) =>
      db.collection("users").doc(merchantId).collection("products").doc(pid),
    );

    // Read all product docs
    const productSnaps = [];
    for (const ref of productRefs) {
      productSnaps.push(await tx.get(ref));
    }

    // Read all cart items (subcollection) BEFORE any write
    const itemsCol = cartDoc.collection("items");
    const itemsSnap = await tx.get(itemsCol);

    // --- WRITES (after all reads) ---

    // 1) Decrement stock where quantity exists
    for (const snap of productSnaps) {
      if (!snap.exists) continue;
      const pid = snap.id;
      const q = Number((sale.products || {})[pid] || 0);
      if (q <= 0) continue;

      const hasQuantity = snap.get("quantity") !== undefined;
      if (hasQuantity) {
        tx.update(snap.ref, {
          quantity: FieldValue.increment(-q),
        });
      }
    }

    // 2) Clear cart items + reset cart totals
    itemsSnap.docs.forEach((d) => tx.delete(d.ref));
    tx.set(
      cartDoc,
      {
        total: 0,
        itemsCount: 0,
        lock: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    // 3) Mark sale as inventory finalized
    tx.update(saleRef, {
      inventoryFinalized: true,
      ...(reservationId
        ? {
            inventoryReservationConsumed: true,
            inventoryReservationConsumedAt: FieldValue.serverTimestamp(),
          }
        : {}),
      inventoryFinalizedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

/**
 * Cloud Function: updateOrderPayment
 *
 * Handles updates to an order’s payment or fulfillment status.
 * Supported actions include:
 * - `ACCEPT_BNPL`: Approve Buy Now, Pay Later transaction (creates customer credit transaction).
 * - `REJECT_BNPL`: Reject BNPL request (voids pending customer credit transaction).
 * - `MARK_CASH_RECEIVED`: Mark order as paid in cash.
 * - `MARK_COLLECTED`: Mark order as collected, finalize inventory, and clear cart.
 * - `SETTLE_BNPL`: Mark BNPL transaction as settled (paid).
 * - `CANCEL_ORDER`: Cancel order and release cart lock.
 *
 * Updates the order document with appropriate fields and timestamps, and may
 * create/update related customer transaction documents.
 *
 * @async
 * @function updateOrderPayment
 * @param {Object} data - The function input payload.
 * @param {string} data.merchantId - Merchant's user ID in Firestore.
 * @param {string} data.orderId - The order ID to update.
 * @param {string} data.paymentAction - The action to perform (must be one of ALLOWED).
 * @param {functions.https.CallableContext} context - Callable context with authentication info.
 * @throws {functions.https.HttpsError} If arguments are invalid, order not found, or update fails.
 * @returns {Promise<{ok: boolean, paymentRecordedNow?: boolean}>} Result.
 */
export const updateOrderPayment = functions.https.onCall(
  async (data, context) => {
    try {
      const merchantId = (data?.merchantId ?? "").toString().trim();
      const orderId = (data?.orderId ?? "").toString().trim();
      const paymentAction = (data?.paymentAction ?? "")
        .toString()
        .trim()
        .toUpperCase();

      console.log("[updateOrderPayment] input", {
        merchantId,
        orderId,
        paymentAction,
        uid: context.auth?.uid,
      });

      if (!merchantId || !orderId || !paymentAction) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "merchantId, orderId, paymentAction are required",
        );
      }
      if (!(await authorizeCallableMerchantOrBot(context, merchantId))) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "Access denied",
        );
      }
      if (!ALLOWED.has(paymentAction)) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          `Unknown paymentAction. Allowed: ${Array.from(ALLOWED).join(", ")}`,
        );
      }

      const ref = db
        .collection("users")
        .doc(merchantId)
        .collection("sales")
        .doc(orderId);

      if (isPaymentReceiptAction(paymentAction)) {
        const receipt = await db.runTransaction(async (tx) => {
          const current = await tx.get(ref);
          if (!current.exists) {
            throw new functions.https.HttpsError(
              "not-found",
              "Order not found",
            );
          }
          const currentData = current.data() || {};
          if (isPaymentAlreadyRecorded(currentData)) {
            return { paymentRecordedNow: false, notificationId: "" };
          }

          const customerId = String(
            currentData.customerId ?? currentData.customerID ?? "",
          );
          const customer = customerId
            ? await tx.get(
                db.doc(`users/${merchantId}/customers/${customerId}`),
              )
            : null;

          const notice = legacyOrderNotice({
            merchantId,
            orderId,
            action: paymentAction,
            order: currentData,
            customer: customer?.data(),
          });
          const notificationId = commerceNotificationDocumentId(notice);
          const existingNotice = await tx.get(
            db.doc(`commerceNotificationOutbox/${notificationId}`),
          );
          tx.update(
            ref,
            buildPaymentReceiptPatch(paymentAction, currentData, new Date()),
          );
          if (!existingNotice.exists) {
            enqueueCommerceOrderNotification(tx, notice);
          }
          return { paymentRecordedNow: true, notificationId };
        });
        const notification = await deliverLegacyOrderNotice(
          receipt.notificationId,
        );
        return {
          ok: true,
          paymentRecordedNow: receipt.paymentRecordedNow,
          notification,
        };
      }

      const snap = await ref.get();
      if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Order not found");
      }

      const now = new Date();
      let patch: Record<string, any> = { updatedAt: now };
      const orderData = snap.data() || {};

      // Normalize fields that differ between writers
      const customerId = (
        orderData.customerId ??
        orderData.customerID ??
        orderData.customer
      )?.toString();
      const amount = Number(orderData.total ?? orderData.amount ?? 0) || 0;
      const products =
        orderData.products ?? orderData.items ?? orderData.cart ?? [];
      let refundIntentId = "";
      let refundAmountMinor = 0;
      let refundCaseId = "";

      switch (paymentAction) {
        case "ACCEPT_ORDER": {
          patch = {
            ...patch,
            status: "accepted",
            acceptedAt: now,
            acceptedBy: context.auth?.uid || merchantId,
            paymentStatus: orderData.paymentStatus || "unpaid",
            collected: false,
          };
          break;
        }

        case "REJECT_ORDER": {
          patch = {
            ...patch,
            status: "rejected",
            paymentStatus: orderData.paymentStatus || "unpaid",
            rejectedAt: now,
            rejectedBy: context.auth?.uid || merchantId,
            collected: false,
          };
          if (customerId) {
            const cartDoc = db
              .collection("users")
              .doc(merchantId)
              .collection("carts")
              .doc(customerId);
            await cartDoc.set({ lock: FieldValue.delete() }, { merge: true });
          }
          break;
        }

        case "ASSIGN_DRIVER": {
          const driverName = (data?.driverName ?? "").toString().trim();
          const driverPhone = (data?.driverPhone ?? "").toString().trim();
          const driverId = (data?.driverId ?? "").toString().trim();
          if (!driverName && !driverPhone && !driverId) {
            throw new functions.https.HttpsError(
              "invalid-argument",
              "driverName, driverPhone, or driverId is required",
            );
          }
          patch = {
            ...patch,
            driver: {
              id: driverId || null,
              name: driverName || null,
              phone: driverPhone || null,
              assignedAt: now,
              assignedBy: context.auth?.uid || merchantId,
            },
            driverAssignedAt: now,
          };
          break;
        }

        case "UNASSIGN_DRIVER": {
          // Clears the driver assignment so the merchant can reassign.
          // We deliberately keep the order's status as-is (typically
          // "accepted" or "out_for_delivery") so the merchant can pick
          // up exactly where they left off after fixing the dispatch.
          patch = {
            ...patch,
            driver: FieldValue.delete(),
            driverAssignedAt: FieldValue.delete(),
            driverUnassignedAt: now,
            driverUnassignedBy: context.auth?.uid || merchantId,
          };
          // If the order was already out for delivery, walk it back to
          // "accepted" — there is no driver any more, so it can't be
          // out for delivery. Keeps the state machine honest.
          if (orderData.status === "out_for_delivery") {
            patch.status = "accepted";
          }
          break;
        }

        case "MARK_OUT_FOR_DELIVERY": {
          // Driver has departed the shop. Requires a driver to be
          // assigned — otherwise there's nothing operationally true to
          // tell the customer.
          const driver = orderData.driver || {};
          const hasDriver = !!(driver.id || driver.name || driver.phone);
          if (!hasDriver) {
            throw new functions.https.HttpsError(
              "failed-precondition",
              "Assign a driver before marking the order out for delivery.",
            );
          }
          patch = {
            ...patch,
            status: "out_for_delivery",
            outForDeliveryAt: now,
            outForDeliveryBy: context.auth?.uid || merchantId,
          };
          break;
        }

        case "MARK_DELIVERED": {
          // Terminal state for delivery orders — parallel to
          // MARK_COLLECTED for pickup. We also flip `collected: true`
          // so legacy reads (sales filters, BNPL fulfilment checks)
          // that key off `collected` continue to work without
          // duplicating the meaning of "the customer has the goods".
          patch = {
            ...patch,
            status: "delivered",
            collected: true,
            deliveredAt: now,
            collectedAt: now,
            deliveredBy: context.auth?.uid || merchantId,
          };
          if (customerId) {
            await finalizeInventoryOnce({ merchantId, orderId, customerId });
          }
          break;
        }

        case "ACCEPT_BNPL": {
          patch = {
            ...patch,
            paymentMethod: "BNPL",
            paymentStatus: "approved",
            status: "bnpl_outstanding",
            collected: false,
          };

          if (customerId) {
            await db
              .collection("users")
              .doc(merchantId)
              .collection("customers")
              .doc(customerId)
              .collection("transactions")
              .add({
                type: "Credit",
                amount,
                date: now,
                status: "DUE",
                products,
                orderId,
                source: "updateOrderPayment",
              });
          } else {
            console.warn(
              "[updateOrderPayment] ACCEPT_BNPL: missing customerId, skipping customer transaction",
            );
          }
          break;
        }

        case "REJECT_BNPL": {
          patch = {
            ...patch,
            paymentMethod: "BNPL",
            paymentStatus: "rejected",
            status: "bnpl_rejected",
            bnplRejectedAt: now,
            collected: false,
          };

          if (customerId) {
            const txCol = db
              .collection("users")
              .doc(merchantId)
              .collection("customers")
              .doc(customerId)
              .collection("transactions");

            const dueTxSnap = await txCol
              .where("orderId", "==", orderId)
              .where("status", "==", "DUE")
              .where("source", "==", "updateOrderPayment")
              .get();

            const batch = db.batch();
            dueTxSnap.forEach((doc) => {
              batch.update(doc.ref, {
                status: "VOID",
                voidedAt: now,
                voidReason: "BNPL_REJECTED",
              });
            });
            if (!dueTxSnap.empty) await batch.commit();
          }
          break;
        }

        case "MARK_COLLECTED": {
          patch = {
            ...patch,
            collected: true,
            collectedAt: now,
            status: "collected",
          };

          // 👇 Also a valid point to finalize inventory (idempotent)
          if (customerId) {
            await finalizeInventoryOnce({ merchantId, orderId, customerId });
          }
          break;
        }

        case "CANCEL_ORDER": {
          const reservationId = String(
            orderData.inventoryReservationId ?? "",
          ).trim();
          if (
            orderData.paymentRail === "paystack_v2" &&
            orderData.paymentStatus === "paid"
          ) {
            refundIntentId = String(orderData.paymentIntentId ?? "");
            refundAmountMinor =
              Number(orderData.amountMinor) || Math.round(amount * 100);
          } else if (reservationId && orderData.inventoryReserved === true) {
            await releaseOwnedInventoryReservation({
              reservationId,
              reason: "order_cancelled",
            });
          }
          patch = {
            ...patch,
            status: "cancelled",
            paymentStatus: refundIntentId
              ? "refund_pending"
              : orderData.paymentStatus || "cancelled",
            cancelledAt: now,
          };
          // Remove cart lock if this order owns it (no item clear, no stock changes)
          const cartDoc = db
            .collection("users")
            .doc(merchantId)
            .collection("carts")
            .doc(customerId);
          await cartDoc.set({ lock: FieldValue.delete() }, { merge: true });
          break;
        }
      }

      const customer = customerId
        ? await db.doc(`users/${merchantId}/customers/${customerId}`).get()
        : null;
      const notice = legacyOrderNotice({
        merchantId,
        orderId,
        action: paymentAction,
        order: { ...orderData, ...patch },
        customer: customer?.data(),
      });
      const notificationId = commerceNotificationDocumentId(notice);
      const outboxRef = db.doc(`commerceNotificationOutbox/${notificationId}`);
      await db.runTransaction(async (tx) => {
        const existingNotice = await tx.get(outboxRef);
        if (refundIntentId) {
          const refund = await openRefundCaseInTransactionV2(tx, {
            intentId: refundIntentId,
            idempotencyKey: `owned-order-cancel:${orderId}`,
            refundAmountMinor,
            reason: "merchant_cancelled_owned_order",
            owner: "operations",
          });
          refundCaseId = refund.refundCaseId;
          patch.refundCaseId = refundCaseId;
        }
        tx.update(ref, patch);
        if (!existingNotice.exists) {
          enqueueCommerceOrderNotification(tx, notice);
        }
      });
      if (refundCaseId) {
        await executePaystackRefundV2(refundCaseId).catch(() => undefined);
      }
      const notification = await deliverLegacyOrderNotice(notificationId);
      return { ok: true, notification };
    } catch (err: any) {
      console.error("updateOrderPayment error", err);
      if (err?.code && err?.message) throw err;
      throw new functions.https.HttpsError(
        "internal",
        "Failed to update order",
      );
    }
  },
);
