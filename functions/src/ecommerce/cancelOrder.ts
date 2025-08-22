// functions/src/http/cancelOrder.ts
import { db, functions } from "../config/main";
import * as admin from "firebase-admin";
import { getMerchantFcmTokens } from "./onSaleCancelledNotify";

export const cancelOrder = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  try {
    const { merchantId, orderId, customerId } = req.body || {};
    if (!merchantId || !orderId || !customerId) {
      res
        .status(400)
        .json({ error: "merchantId, orderId, customerId are required" });
      return;
    }

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
      const snap = await tx.get(saleRef);
      if (!snap.exists) throw new Error("ORDER_NOT_FOUND");
      const sale = snap.data() || {};
      if (sale.inventoryFinalized) return; // already finalized; ignore cancel

      tx.update(saleRef, {
        status: "cancelled",
        paymentStatus: sale.paymentStatus || "cancelled",
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // unlock cart (do NOT delete items)
      tx.set(
        cartDoc,
        { lock: admin.firestore.FieldValue.delete() },
        { merge: true },
      );
    });

    // inside cancelOrder.ts, after await db.runTransaction(...)
    try {
      // reuse helpers from above or inline minimally:
      const tokens = await getMerchantFcmTokens(merchantId); // same helper as trigger
      if (tokens.length) {
        await admin.messaging().sendEachForMulticast({
          tokens,
          notification: { title: "Order cancelled", body: `Order #${orderId}` },
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
    return;
  }
});
