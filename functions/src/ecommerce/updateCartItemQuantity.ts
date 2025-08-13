import { db, functions } from "../config/main";
import * as admin from "firebase-admin";

/**
 * HTTP endpoint to set an item's quantity in a cart.
 * Body: { merchantId: string, customerId: string, productId: string, quantity: number }  // quantity >= 0
 * Behavior:
 *  - If quantity === 0: delete the item.
 *  - Else: set item.quantity = quantity (upsert).
 * In all cases, updates cart summary (total, itemsCount) consistently.
 * Returns: { success: true, total: number, itemsCount: number, quantity: number }
 */
export const updateCartItemQuantity = functions.https.onRequest(
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const { merchantId, customerId, productId } = req.body || {};
    let quantity = req.body?.quantity;

    if (!merchantId || !customerId || !productId || quantity === undefined) {
      res.status(400).json({
        error: "merchantId, customerId, productId and quantity are required",
      });
      return;
    }

    // Normalize & validate quantity
    quantity = Number(quantity);
    if (!Number.isInteger(quantity) || quantity < 0) {
      res.status(400).json({ error: "quantity must be an integer >= 0" });
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

        const prevItem = itemSnap.exists ? itemSnap.data() || {} : {};
        const prevQty = Number(prevItem.quantity ?? 0);

        // Resolve unit price (prefer snapshot, fallback to product doc)
        let unit = Number(
          prevItem.details?.sellingPrice ?? prevItem.details?.price ?? 0,
        );

        if (!Number.isFinite(unit) || unit <= 0) {
          const prodSnap = await tx.get(productRef);
          const prod = prodSnap.exists ? prodSnap.data() || {} : {};
          unit =
            Number(prod.sellingPrice ?? prod.price ?? prod.productPrice ?? 0) ||
            0;
          // If no snapshot exists, consider writing details snapshot on upsert
          if (quantity > 0 && !itemSnap.exists) {
            prevItem.details = {
              productId,
              name: prod.name ?? prod.productName ?? prod.title ?? productId,
              productName:
                prod.productName ?? prod.name ?? prod.title ?? productId,
              price: unit,
              sellingPrice: unit,
              imageUrl: prod.imageUrl ?? prod.image ?? null,
              image: prod.image ?? null,
              description: prod.description ?? "",
            };
          }
        }

        const deltaQty = quantity - prevQty; // can be negative
        const deltaTotal = unit * deltaQty;

        const prevTotal = Number(cartSnap.get("total") ?? 0);
        const prevCount = Number(cartSnap.get("itemsCount") ?? 0);

        const newTotal = Math.max(0, prevTotal + deltaTotal);
        const newCount = Math.max(0, prevCount + deltaQty);

        if (quantity === 0) {
          // Delete item
          if (itemSnap.exists) tx.delete(itemRef);
        } else {
          // Upsert with new quantity (+ snapshot if needed)
          tx.set(
            itemRef,
            {
              quantity,
              ...(prevItem.details ? { details: prevItem.details } : {}),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }

        // Update summary
        tx.set(
          cartRef,
          {
            total: newTotal,
            itemsCount: newCount,
            currency: "ZAR",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        return { total: newTotal, itemsCount: newCount, quantity };
      });

      res.status(200).json({ success: true, ...result });
    } catch (error: any) {
      console.error("Error updating cart quantity:", error?.message || error);
      res.status(500).json({ error: "Failed to update item quantity" });
    }
  },
);
