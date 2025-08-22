// functions/src/http/finalizeOnlinePaid.ts
import { db, functions } from "../config/main";
import * as admin from "firebase-admin";

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
 * @param {string} merchantId - The merchant's user ID in Firestore.
 * @param {string} orderId - The order ID referencing the sale document.
 * @param {string} customerId - The customer ID whose cart will be cleared.
 * @throws {Error} If the sale document is not found.
 * @return {Promise<void>} Resolves once the transaction completes successfully.
 */
async function finalizeInventoryOnce(
  merchantId: string,
  orderId: string,
  customerId: string,
) {
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
    const saleSnap = await tx.get(saleRef);
    if (!saleSnap.exists) throw new Error("SALE_NOT_FOUND");
    const sale = saleSnap.data() || {};

    if (sale.inventoryFinalized) return;
    if ((sale.type || "").toLowerCase() !== "online")
      throw new Error("NOT_ONLINE");
    const st = String(sale.status || sale.paymentStatus || "").toLowerCase();
    if (
      !["paid", "completed", "success", "settled", "fulfilled"].includes(st)
    ) {
      throw new Error("NOT_PAID");
    }

    const productIds: string[] = Object.keys(sale.products || {});
    for (const pid of productIds) {
      const pref = db
        .collection("users")
        .doc(merchantId)
        .collection("products")
        .doc(pid);
      const psnap = await tx.get(pref);
      if (psnap.exists && psnap.get("quantity") !== undefined) {
        const q = Number((sale.products || {})[pid] || 0);
        if (q > 0)
          tx.update(pref, {
            quantity: admin.firestore.FieldValue.increment(-q),
          });
      }
    }

    // clear cart and unlock
    const itemsSnap = await tx.get(cartDoc.collection("items"));
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

    tx.update(saleRef, {
      inventoryFinalized: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

/**
 * finalizeOnlinePaid (HTTP) – finalize after payment success
 *
 * @param {import("firebase-functions").https.Request} req - Incoming HTTP request (POST).
 * @param {import("firebase-functions").Response} res - Outgoing HTTP response.
 * @returns {Promise<void>}
 */
export const finalizeOnlinePaid = functions.https.onRequest(
  async (req, res) => {
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
      await finalizeInventoryOnce(merchantId, orderId, customerId);
      res.status(200).json({ ok: true });
    } catch (e: any) {
      const msg = e?.message || "";
      const code = ["NOT_PAID", "NOT_ONLINE"].includes(msg) ? 409 : 500;
      res.status(code).json({ error: msg || "Failed to finalize" });
      return;
    }
  },
);
