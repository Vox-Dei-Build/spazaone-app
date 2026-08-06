import { db, functions } from "../config/main";
import { FieldValue } from "firebase-admin/firestore";

/**
 * HTTP endpoint to remove a product (entirely) from a customer's cart.
 * Body: { merchantId, customerId, productId }
 * Returns: { success: true, total: number, itemsCount: number }
 */
export const removeFromCart = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const { merchantId, customerId, productId } = req.body || {};
  if (!merchantId || !customerId || !productId) {
    res
      .status(400)
      .json({ error: "merchantId, customerId and productId are required" });
    return;
  }

  try {
    const cartRef = db
      .collection("users")
      .doc(merchantId)
      .collection("carts")
      .doc(customerId);

    const itemRef = cartRef.collection("items").doc(productId);
    const productRef = db
      .collection("users")
      .doc(merchantId)
      .collection("products")
      .doc(productId);

    const result = await db.runTransaction(async (tx) => {
      const [itemSnap, cartSnap] = await Promise.all([
        tx.get(itemRef),
        tx.get(cartRef),
      ]);

      if (!itemSnap.exists) {
        // Nothing to remove; return current summary if any
        const total = Number(cartSnap.get("total") ?? 0);
        const itemsCount = Number(cartSnap.get("itemsCount") ?? 0);
        return { total, itemsCount };
      }

      const item = itemSnap.data() || {};
      const qty = Number(item.quantity ?? 0);

      // Prefer snapshot price; fallback to product doc
      let unit = Number(item.details?.sellingPrice ?? item.details?.price ?? 0);

      if (!Number.isFinite(unit) || unit <= 0) {
        const prodSnap = await tx.get(productRef);
        const prod = prodSnap.exists ? prodSnap.data() || {} : {};
        unit =
          Number(prod.sellingPrice ?? prod.price ?? prod.productPrice ?? 0) ||
          0;
      }

      const line = Math.max(0, unit * qty);

      const prevTotal = Number(cartSnap.get("total") ?? 0);
      const prevCount = Number(cartSnap.get("itemsCount") ?? 0);

      const newTotal = Math.max(0, prevTotal - line);
      const newCount = Math.max(0, prevCount - qty);

      // Delete item, update summary
      tx.delete(itemRef);
      tx.set(
        cartRef,
        {
          total: newTotal,
          itemsCount: newCount,
          currency: "ZAR",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      return { total: newTotal, itemsCount: newCount };
    });

    res.status(200).json({
      success: true,
      total: result.total,
      itemsCount: result.itemsCount,
    });
  } catch (error: any) {
    console.error("Error removing from cart:", error?.message || error);
    res.status(500).json({ error: "Failed to remove item" });
  }
});
