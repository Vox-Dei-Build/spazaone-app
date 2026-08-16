// functions/src/http/finalizeOnlinePaid.ts
import { db, functions } from "../config/main";
import { FieldValue } from "firebase-admin/firestore";
import { consumeOwnedInventoryReservation } from "../payments/v2/inventoryReservations";

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

  const cartRef = db
    .collection("users")
    .doc(merchantId)
    .collection("carts")
    .doc(customerId);

  const now = FieldValue.serverTimestamp();

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
    // ── PHASE A: READS (no writes here)
    const saleSnap = await tx.get(saleRef);
    if (!saleSnap.exists) throw new Error("SALE_NOT_FOUND");
    const sale = saleSnap.data() || {};

    // Only finalize ONLINE orders that are paid/successful
    if ((sale.type || "").toLowerCase() !== "online")
      throw new Error("NOT_ONLINE");
    if (sale.inventoryFinalized) return; // idempotent no-op

    const st = String(sale.status || sale.paymentStatus || "").toLowerCase();
    const isPaid = [
      "paid",
      "completed",
      "success",
      "settled",
      "fulfilled",
    ].includes(st);
    if (!isPaid) throw new Error("NOT_PAID");

    // Gather product updates: read ALL product docs before ANY writes
    const saleProducts: Record<string, number> = sale.products || {};
    const productIds = Object.keys(saleProducts);
    const productReads: Array<{
      ref: FirebaseFirestore.DocumentReference;
      qty: number;
      hasQtyField: boolean;
    }> = [];
    for (const pid of reservationId ? [] : productIds) {
      const pref = db
        .collection("users")
        .doc(merchantId)
        .collection("products")
        .doc(pid);
      const psnap = await tx.get(pref);
      if (!psnap.exists) continue;
      const hasQtyField = psnap.get("quantity") !== undefined;
      const qty = Number(saleProducts[pid] || 0);
      productReads.push({ ref: pref, qty, hasQtyField });
    }

    // Read cart doc + possible subcollections (both "items" and "cartItems")
    const cartSnap = await tx.get(cartRef);
    const itemsCollRef = cartRef.collection("items");
    const altItemsCollRef = cartRef.collection("cartItems"); // just in case your schema used this name
    const [itemsQuerySnap, altItemsQuerySnap] = await Promise.all([
      tx.get(itemsCollRef),
      tx.get(altItemsCollRef),
    ]);

    // ── PHASE B: WRITES (now we can write)
    // 1) Decrement stock where applicable
    for (const pr of productReads) {
      if (pr.hasQtyField && pr.qty > 0) {
        tx.update(pr.ref, {
          quantity: FieldValue.increment(-pr.qty),
          updatedAt: now,
        });
      }
    }

    // 2) Clear cart subcollections
    itemsQuerySnap.docs.forEach((d) => tx.delete(d.ref));
    altItemsQuerySnap.docs.forEach((d) => tx.delete(d.ref));

    // 3) Clear/normalize cart doc fields (support both array/map shapes)
    // NOTE: If your UI expects a specific shape, keep that one and drop the other.
    const clearedFields: Record<string, any> = {
      items: [], // array shape
      products: {}, // map shape
      itemsCount: 0,
      subtotal: 0,
      total: 0,
      discounts: 0,
      tax: 0,
      lock: FieldValue.delete(),
      lastClearedBecause: "online_payment_finalized",
      updatedAt: now,
    };
    if (cartSnap.exists) {
      tx.set(cartRef, clearedFields, { merge: true });
    } else {
      // Ensure doc exists to make the UI state unambiguous
      tx.set(cartRef, clearedFields, { merge: true });
    }

    // 4) Mark sale as finalized
    tx.update(saleRef, {
      inventoryFinalized: true,
      ...(reservationId
        ? {
            inventoryReservationConsumed: true,
            inventoryReservationConsumedAt: now,
          }
        : {}),
      finalizedAt: now,
      updatedAt: now,
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
    }
  },
);
