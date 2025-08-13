import { db, functions } from "../config/main";

/**
 * HTTP endpoint to fetch a customer's cart with items and total.
 *
 * Accepts merchantId, customerId in query or body.
 * Returns: { items: Array<{ productId, quantity, details }>, total: number, itemsCount?: number }
 */
export const getCart = functions.https.onRequest(async (req, res) => {
  try {
    const merchantId = (req.query.merchantId || req.body?.merchantId) as string;
    const customerId = (req.query.customerId || req.body?.customerId) as string;

    if (!merchantId || !customerId) {
      res.status(400).json({ error: "merchantId and customerId are required" });
      return;
    }

    const cartDocRef = db
      .collection("users")
      .doc(merchantId)
      .collection("carts")
      .doc(customerId);

    // 1) Read summary (if you maintain one). We'll prefer its 'total' if present.
    const cartSummarySnap = await cartDocRef.get();
    const summary = cartSummarySnap.exists ? cartSummarySnap.data() || {} : {};
    const summaryTotal =
      typeof summary.total === "number" ? summary.total : null;
    const summaryCount =
      typeof summary.itemsCount === "number" ? summary.itemsCount : null;

    // 2) Load items
    const itemsSnap = await cartDocRef.collection("items").get();
    const items: Array<{ productId: string; quantity: number; details?: any }> =
      [];

    if (itemsSnap.empty) {
      // No items; short-circuit
      res.status(200).json({ items: [], total: 0, itemsCount: 0 });
      return;
    }

    // 3) Stage data for batch product lookup (only for items missing snapshots)
    const missingRefs: FirebaseFirestore.DocumentReference[] = [];
    const indexById: Record<string, number> = {};

    itemsSnap.forEach((doc) => {
      const data = doc.data() || {};
      const quantity = Number(data.quantity || 0);
      const details = data.details || null; // preferred snapshot (from addToCart upgrade)

      items.push({ productId: doc.id, quantity, details });
      indexById[doc.id] = items.length - 1;

      // If no snapshot, we'll fetch product doc later in one batch
      if (!details) {
        const ref = db
          .collection("users")
          .doc(merchantId)
          .collection("products")
          .doc(doc.id);
        missingRefs.push(ref);
      }
    });

    // 4) Batch fetch product docs for items without details snapshot (avoid N+1)
    if (missingRefs.length > 0) {
      // Firestore supports getAll with a spread of refs; chunk if you fear very large carts
      const missingDocs = await db.getAll(...missingRefs);
      missingDocs.forEach((snap) => {
        const pid = snap.id;
        const idx = indexById[pid];
        if (idx == null) return;

        const productData = snap.exists ? snap.data() || {} : {};
        // Normalize fields for UI
        const unit = Number(
          productData.sellingPrice ??
            productData.price ??
            productData.productPrice ??
            0,
        );

        // Merge as details so the bot UI is consistent
        items[idx].details = {
          productId: pid,
          name:
            productData.name ??
            productData.productName ??
            productData.title ??
            pid,
          productName:
            productData.productName ??
            productData.name ??
            productData.title ??
            pid,
          price: unit,
          sellingPrice: unit,
          imageUrl: productData.imageUrl ?? productData.image ?? null,
          image: productData.image ?? null,
          description: productData.description ?? "",
        };
      });
    }

    // 5) Compute total if summary missing; otherwise trust summary total
    let total: number;
    if (typeof summaryTotal === "number") {
      total = summaryTotal;
    } else {
      total = items.reduce((sum, it) => {
        const unit = Number(it.details?.sellingPrice ?? it.details?.price ?? 0);
        const qty = Number(it.quantity || 0);
        return sum + unit * qty;
      }, 0);
    }

    // 6) itemsCount (prefer summary, else compute)
    const itemsCount =
      typeof summaryCount === "number"
        ? summaryCount
        : items.reduce((acc, it) => acc + Number(it.quantity || 0), 0);

    res.status(200).json({ items, total, itemsCount });
  } catch (error: any) {
    console.error("Error fetching cart:", error?.message || error);
    res.status(500).json({ error: "Failed to fetch cart" });
  }
});
