import { db, functions } from "../config/main";

export const getProducts = functions.https.onRequest(async (req, res) => {
  const merchantId = (req.query.merchantId || req.body.merchantId) as string;
  if (!merchantId) {
    res.status(400).json({ error: "merchantId is required" });
    return;
  }
  try {
    const snapshot = await db
      .collection("users")
      .doc(merchantId)
      .collection("products")
      .get();
    const products = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    res.status(200).json({ products });
  } catch (error) {
    console.error("Error fetching products:", error);
    res.status(500).json({ error: "Failed to fetch products" });
  }
});
