// functions/src/http/updateOrderPayment.ts
import { db, functions } from "../config/main";
import * as admin from "firebase-admin";

const ALLOWED = new Set([
  "ACCEPT_ORDER",
  "REJECT_ORDER",
  "ASSIGN_DRIVER",
  "ACCEPT_BNPL",
  "REJECT_BNPL",
  "MARK_CASH_RECEIVED",
  "MARK_COLLECTED",
  "SETTLE_BNPL",
  "CANCEL_ORDER",
]);

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

  await db.runTransaction(async (tx) => {
    // --- READS (all of them) ---
    const saleSnap = await tx.get(saleRef);
    if (!saleSnap.exists) throw new Error("SALE_NOT_FOUND");

    const sale = saleSnap.data() || {};
    if (sale.inventoryFinalized) {
      // Idempotent: already finalized
      return;
    }

    const productIds: string[] = Object.keys(sale.products || {});
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
          quantity: admin.firestore.FieldValue.increment(-q),
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
        lock: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    // 3) Mark sale as inventory finalized
    tx.update(saleRef, {
      inventoryFinalized: true,
      inventoryFinalizedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
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
 * @returns {Promise<{ok: boolean}>} Returns `{ ok: true }` if the update succeeds.
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
            await cartDoc.set(
              { lock: admin.firestore.FieldValue.delete() },
              { merge: true },
            );
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

        case "MARK_CASH_RECEIVED": {
          const existingMethod = String(
            orderData.paymentMethod || orderData.type || "",
          );
          patch = {
            ...patch,
            paymentMethod:
              existingMethod.toLowerCase() === "transfer" ||
              existingMethod.toLowerCase() === "eft"
                ? "Transfer"
                : "Cash",
            paymentStatus: "paid",
            status: "paid",
            cashReceivedAt: now,
          };
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

        case "SETTLE_BNPL": {
          patch = {
            ...patch,
            paymentStatus: "paid",
            status: "paid",
            paidAt: now,
          };
          break;
        }

        case "CANCEL_ORDER": {
          patch = {
            ...patch,
            status: "cancelled",
            paymentStatus: orderData.paymentStatus || "cancelled",
            cancelledAt: now,
          };
          // Remove cart lock if this order owns it (no item clear, no stock changes)
          const cartDoc = db
            .collection("users")
            .doc(merchantId)
            .collection("carts")
            .doc(customerId);
          await cartDoc.set(
            { lock: admin.firestore.FieldValue.delete() },
            { merge: true },
          );
          break;
        }
      }

      await ref.update(patch);
      return { ok: true };
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
