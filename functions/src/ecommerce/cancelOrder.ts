// functions/src/http/cancelOrder.ts
import { db, functions } from "../config/main";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { getMerchantFcmTokens } from "./onSaleCancelledNotify";
import { releaseOwnedInventoryReservation } from "../payments/v2/inventoryReservations";
import {
  executePaystackRefundV2,
  openRefundCaseInTransactionV2,
} from "../payments/v2/refunds";
import {
  authenticateFirebaseRequest,
  verifyBotRequest,
} from "../security/requestAuth";
import { assertStoreAccess, requireStoreId } from "../stores/storeAccess";

export function shouldReleaseReservationOnCancel(
  sale: Record<string, unknown>,
  reservationId: string,
): boolean {
  if (!reservationId || sale.inventoryReserved !== true) return false;
  const paymentRail = String(sale.paymentRail ?? "").toLowerCase();
  const paymentStatus = String(sale.paymentStatus ?? "").toLowerCase();
  if (
    paymentRail === "paystack_v2" &&
    ["paid", "refund_pending", "refunded"].includes(paymentStatus)
  ) {
    return false;
  }
  return true;
}

/**
 * Cancel an order and clear the customer's cart.
 *
 * Idempotent:
 * - Safe to re-run; sale stays "cancelled" and cart remains cleared.
 *
 * Transaction phases:
 *   READS:   sale doc, cart doc, cart subcollections
 *   WRITES:  sale -> cancelled, delete cart subcollection docs, clear cart doc fields
 *
 * Request body:
 *   { merchantId: string, orderId: string, customerId: string }
 */
export const cancelOrder = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN", "PAYSTACK_SECRET_KEY"] })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    try {
      const {
        merchantId: merchantIdValue,
        orderId,
        customerId,
      } = req.body || {};
      const merchantId = requireStoreId(merchantIdValue);
      if (!merchantId || !orderId || !customerId) {
        res
          .status(400)
          .json({ error: "merchantId, orderId, customerId are required" });
        return;
      }
      if (!verifyBotRequest(req)) {
        const uid = await authenticateFirebaseRequest(req, res, {
          requireAppCheck: true,
        });
        if (!uid) return;
        await assertStoreAccess(uid, merchantId);
      }

      const saleRef = db
        .collection("users")
        .doc(merchantId)
        .collection("sales")
        .doc(orderId);

      const cartRef = db
        .collection("users")
        .doc(merchantId)
        .collection("carts")
        .doc(customerId);

      const now = FieldValue.serverTimestamp();

      const saleBeforeCancel = await saleRef.get();
      const reservationId = String(
        saleBeforeCancel.data()?.inventoryReservationId ?? "",
      ).trim();
      const saleBefore = saleBeforeCancel.data() ?? {};
      if (
        String(saleBefore.customerId ?? saleBefore.customerID ?? "") !==
        customerId
      ) {
        res.status(409).json({ error: "Order customer does not match." });
        return;
      }
      let refundCaseId = "";
      if (shouldReleaseReservationOnCancel(saleBefore, reservationId)) {
        await releaseOwnedInventoryReservation({
          reservationId,
          reason: "order_cancelled",
        });
      }

      await db.runTransaction(async (tx) => {
        // ── READS (no writes here)
        const saleSnap = await tx.get(saleRef);
        if (!saleSnap.exists) throw new Error("ORDER_NOT_FOUND");
        const sale = saleSnap.data() || {};
        if (String(sale.customerId ?? sale.customerID ?? "") !== customerId) {
          throw new Error("ORDER_CUSTOMER_MISMATCH");
        }

        // Read cart doc + possible subcollections
        const cartSnap = await tx.get(cartRef);
        const itemsCollRef = cartRef.collection("items");
        const altItemsCollRef = cartRef.collection("cartItems"); // if you ever used this name
        const [itemsQuerySnap, altItemsQuerySnap] = await Promise.all([
          tx.get(itemsCollRef),
          tx.get(altItemsCollRef),
        ]);

        if (
          sale.paymentRail === "paystack_v2" &&
          sale.paymentStatus === "paid"
        ) {
          const refund = await openRefundCaseInTransactionV2(tx, {
            intentId: String(sale.paymentIntentId ?? ""),
            idempotencyKey: `owned-order-cancel:${orderId}`,
            refundAmountMinor: Number(sale.amountMinor),
            reason: "merchant_cancelled_owned_order",
            owner: "operations",
          });
          refundCaseId = refund.refundCaseId;
        }

        // ── WRITES (after all reads)
        // 1) Update sale status (idempotent)
        tx.update(saleRef, {
          status: "cancelled",
          paymentStatus: refundCaseId
            ? "refund_pending"
            : sale.paymentStatus || "cancelled",
          ...(refundCaseId ? { refundCaseId } : {}),
          cancelledAt: now,
          updatedAt: now,
        });

        // 2) Clear cart subcollections (delete item docs)
        itemsQuerySnap.docs.forEach((d) => tx.delete(d.ref));
        altItemsQuerySnap.docs.forEach((d) => tx.delete(d.ref));

        // 3) Clear/normalize cart doc fields so UI is definitely empty & unlocked
        const clearedCart: Record<string, any> = {
          items: [], // array shape (if your UI reads this)
          products: {}, // map shape (if your UI reads this)
          itemsCount: 0,
          subtotal: 0,
          total: 0,
          discounts: 0,
          tax: 0,
          lastClearedBecause: "order_cancelled",
          updatedAt: now,
          // remove any lock flag
          lock: FieldValue.delete(),
        };

        if (cartSnap.exists) {
          tx.set(cartRef, clearedCart, { merge: true });
        } else {
          // Ensure the doc exists in a clean state
          tx.set(cartRef, clearedCart, { merge: true });
        }
      });

      if (refundCaseId) {
        await executePaystackRefundV2(refundCaseId).catch(() => undefined);
      }

      // Push notify merchant (best-effort)
      try {
        const tokens = await getMerchantFcmTokens(merchantId);
        if (tokens.length) {
          await admin.messaging().sendEachForMulticast({
            tokens,
            notification: {
              title: "Order cancelled",
              body: `Order #${orderId}`,
            },
            data: {
              eventType: "ORDER_CANCELLED",
              merchantId,
              orderId,
              customerId,
            },
          });
        } else {
          console.warn(`[push] No FCM tokens for merchant ${merchantId}`);
        }
      } catch (e: any) {
        console.warn("[cancelOrder] push notify failed:", e?.message || e);
      }

      res.status(200).json({ ok: true });
    } catch (e: any) {
      console.error("cancelOrder error", e?.message || e);
      res.status(500).json({ error: "Failed to cancel order" });
    }
  });
