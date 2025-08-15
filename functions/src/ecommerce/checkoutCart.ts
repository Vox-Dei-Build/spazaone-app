import { db, functions } from "../config/main";
import * as admin from "firebase-admin";

/**
 * Convert a customer's cart into a sale (collection-first).
 * - Computes total from product docs (sellingPrice || price || productPrice)
 * - Saves itemsCount, products map, and item snapshots
 * - Sets initial status per paymentType (not "paid" for Cash/BNPL)
 * - Decrements product stock (if product.quantity exists)
 * - Clears the cart items
 */
export const checkoutCart = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  try {
    const {
      merchantId,
      customerId,
      paymentType = "Online",
      deliveryInfo = "",
      remarks = "",
      pickupAt = null,
      pickupLabel = null,
    } = (req.body || {}) as {
      merchantId: string;
      customerId: string;
      paymentType?: "Cash" | "Online" | "BNPL" | string;
      deliveryInfo?: string;
      remarks?: string;
      pickupAt?: string | null;
      pickupLabel?: string | null;
    };

    if (!merchantId || !customerId) {
      res.status(400).json({ error: "merchantId and customerId are required" });
      return;
    }

    const cartDoc = db
      .collection("users")
      .doc(merchantId)
      .collection("carts")
      .doc(customerId);
    const itemsSnap = await cartDoc.collection("items").get();

    if (itemsSnap.empty) {
      res.status(400).json({ error: "Cart is empty" });
      return;
    }

    // Collect product refs for a batched fetch
    const productIds: string[] = [];
    const quantities: Record<string, number> = {};
    itemsSnap.forEach((d) => {
      const q = Number((d.data() || {}).quantity || 0);
      if (q > 0) {
        productIds.push(d.id);
        quantities[d.id] = q;
      }
    });

    // Batch fetch product docs to avoid N+1
    const productRefs = productIds.map((pid) =>
      db.collection("users").doc(merchantId).collection("products").doc(pid),
    );
    const productDocs = productRefs.length
      ? await db.getAll(...productRefs)
      : [];

    // Build lines with snapshots
    type SaleItem = {
      productId: string;
      quantity: number;
      details: {
        productId: string;
        name: string;
        productName: string;
        price: number;
        sellingPrice: number;
        imageUrl: string | null;
        image: string | null;
        description: string;
      };
    };

    const items: SaleItem[] = [];
    let total = 0;
    let itemsCount = 0;

    for (const snap of productDocs) {
      const pid = snap.id;
      const qty = Number(quantities[pid] || 0);
      itemsCount += qty;

      const data = snap.exists ? snap.data() || {} : {};
      const unit =
        Number(data.sellingPrice ?? data.price ?? data.productPrice ?? 0) || 0;

      total += unit * qty;

      items.push({
        productId: pid,
        quantity: qty,
        details: {
          productId: pid,
          name: (data.name ?? data.productName ?? data.title ?? pid) as string,
          productName: (data.productName ??
            data.name ??
            data.title ??
            pid) as string,
          price: unit,
          sellingPrice: unit,
          imageUrl: (data.imageUrl ?? data.image ?? null) || null,
          image: (data.image ?? null) || null,
          description: (data.description ?? "") as string,
        },
      });
    }

    // Initial status by payment type (merchant/app will update later)
    const initialStatus = (() => {
      const t = (paymentType || "").toLowerCase();
      if (t === "cash") return "awaiting_collection";
      if (t === "bnpl") return "pending_review";
      if (t === "online") return "pending_payment";
      return "pending";
    })();

    // Sale doc
    const saleRef = db
      .collection("users")
      .doc(merchantId)
      .collection("sales")
      .doc();
    const now = admin.firestore.FieldValue.serverTimestamp();

    const productsMap: Record<string, number> = {};
    Object.keys(quantities).forEach(
      (pid) => (productsMap[pid] = Number(quantities[pid] || 0)),
    );

    const saleData = {
      id: saleRef.id,
      customerId,
      type: paymentType,
      status: initialStatus, // ✅ NOT "paid" for Cash/BNPL
      amount: total, // ✅ total saved
      itemsCount, // ✅ count saved
      currency: "ZAR",
      products: productsMap, // quick map
      items, // rich snapshots for UI
      deliveryInfo: deliveryInfo || "",
      remarks: remarks || "",
      pickupAt: pickupAt || null, // optional collection time
      pickupLabel: pickupLabel || null,
      dateAdded: now,
      updatedAt: now,
    };

    // Write sale
    await saleRef.set(saleData, { merge: true });

    // Decrement stock where product.quantity exists
    const stockBatch = db.batch();
    productDocs.forEach((snap) => {
      if (snap.exists) {
        const pid = snap.id;
        const q = Number(quantities[pid] || 0);
        if (q > 0 && snap.get("quantity") !== undefined) {
          stockBatch.update(snap.ref, {
            quantity: admin.firestore.FieldValue.increment(-q),
          });
        }
      }
    });
    await stockBatch.commit().catch(() => {
      /* ignore non-fatal stock errors */
    });

    // Clear cart items (and zero summary if you maintain one)
    const clearBatch = db.batch();
    itemsSnap.docs.forEach((d) => clearBatch.delete(d.ref));
    clearBatch.set(
      cartDoc,
      { total: 0, itemsCount: 0, updatedAt: now },
      { merge: true },
    );
    await clearBatch.commit();

    // (Optional) merchant snapshot
    await db
      .collection("users")
      .doc(merchantId)
      .set(
        {
          lastSaleTransaction: {
            ...saleData,
            items: null,
            products: null,
          },
        },
        { merge: true },
      );

    res.status(200).json({
      success: true,
      saleId: saleRef.id,
      total,
      itemsCount,
      status: initialStatus,
    });
  } catch (error: any) {
    console.error("Error completing checkout:", error?.message || error);
    res.status(500).json({ error: "Failed to checkout" });
  }
});
