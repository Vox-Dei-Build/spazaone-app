import { db, functions } from "../config/main";
import * as admin from "firebase-admin";

type AddToCartBody = {
  merchantId: string;
  customerId: string;
  productId: string;
  quantity?: number; // positive integer
};

export const addToCart = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const {
    merchantId,
    customerId,
    productId,
    quantity = 1,
  } = (req.body || {}) as AddToCartBody;

  if (!merchantId || !customerId || !productId) {
    res
      .status(400)
      .json({ error: "merchantId, customerId and productId are required" });
    return;
  }

  const qtyToAdd = Number(quantity);
  if (
    !Number.isFinite(qtyToAdd) ||
    qtyToAdd <= 0 ||
    !Number.isInteger(qtyToAdd)
  ) {
    res.status(400).json({ error: "quantity must be a positive integer" });
    return;
  }

  try {
    const productRef = db
      .collection("users")
      .doc(merchantId)
      .collection("products")
      .doc(productId);

    const cartSummaryRef = db
      .collection("users")
      .doc(merchantId)
      .collection("carts")
      .doc(customerId);

    const itemRef = cartSummaryRef.collection("items").doc(productId);

    const result = await db.runTransaction(async (tx) => {
      // 1) Load product (for price + details snapshot)
      const productSnap = await tx.get(productRef);
      if (!productSnap.exists) {
        throw new Error("Product not found");
      }
      const product = productSnap.data() || {};

      const unit = Number(product.sellingPrice ?? product.price ?? 0);
      if (!Number.isFinite(unit) || unit < 0) {
        throw new Error("Invalid product price");
      }

      // 2) Read current item and summary (create-if-missing)
      const [itemSnap, cartSnap] = await Promise.all([
        tx.get(itemRef),
        tx.get(cartSummaryRef),
      ]);

      const prevQty = Number(itemSnap.get("quantity") ?? 0);
      const newQty = prevQty + qtyToAdd;

      const prevTotal = Number(cartSnap.get("total") ?? 0);
      const prevCount = Number(cartSnap.get("itemsCount") ?? 0);

      // 3) Compute increments
      const lineIncrement = unit * qtyToAdd;
      const newTotal = prevTotal + lineIncrement;
      const newCount = prevCount + qtyToAdd;

      // 4) Upsert item with product snapshot
      tx.set(
        itemRef,
        {
          quantity: newQty,
          // snapshot used by UI (your cart step already reads these keys)
          details: {
            productId,
            name:
              product.name ?? product.productName ?? product.title ?? productId,
            productName:
              product.productName ?? product.name ?? product.title ?? productId,
            price: unit,
            sellingPrice: unit,
            imageUrl: product.imageUrl ?? product.image ?? null,
            image: product.image ?? null,
            description: product.description ?? "",
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      // 5) Upsert cart summary (denormalized running total)
      tx.set(
        cartSummaryRef,
        {
          total: newTotal,
          itemsCount: newCount,
          currency: "ZAR",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      return { total: newTotal, itemsCount: newCount, unitPrice: unit };
    });

    res.status(200).json({
      success: true,
      total: result.total,
      itemsCount: result.itemsCount,
    });
  } catch (error: any) {
    console.error("Error adding to cart:", error?.message || error);
    const code =
      error?.message === "Product not found" ||
      error?.message === "Invalid product price"
        ? 400
        : 500;
    res.status(code).json({ error: error?.message || "Failed to add item" });
  }
});
