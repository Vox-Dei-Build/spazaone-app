import { db, functions } from "../config/main";

export const getCart = functions.https.onRequest(async (req, res) => {
  const merchantId = (req.query.merchantId || req.body.merchantId) as string;
  const customerId = (req.query.customerId || req.body.customerId) as string;

  if (!merchantId || !customerId) {
    res.status(400).json({ error: "merchantId and customerId are required" });
    return;
  }

  try {
    const itemsSnap = await db
      .collection("users")
      .doc(merchantId)
      .collection("carts")
      .doc(customerId)
      .collection("items")
      .get();

    const items: Array<{ productId: string; quantity: number; details?: any }> = [];
    let total = 0;

    for (const doc of itemsSnap.docs) {
      const { quantity = 0 } = doc.data();
      const productRef = db
        .collection("users")
        .doc(merchantId)
        .collection("products")
        .doc(doc.id);
      const productDoc = await productRef.get();
      const productData = productDoc.exists ? productDoc.data() : {};
      const price = productData?.productPrice || 0;
      total += price * quantity;
      items.push({ productId: doc.id, quantity, details: productData });
    }

    res.status(200).json({ items, total });
  } catch (error) {
    console.error("Error fetching cart:", error);
    res.status(500).json({ error: "Failed to fetch cart" });
  }
});
