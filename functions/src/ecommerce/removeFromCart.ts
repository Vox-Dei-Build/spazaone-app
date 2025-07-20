import { db, functions } from "../config/main";

export const removeFromCart = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const { merchantId, customerId, productId } = req.body;

  if (!merchantId || !customerId || !productId) {
    res.status(400).json({ error: "merchantId, customerId and productId are required" });
    return;
  }

  try {
    const itemRef = db
      .collection("users")
      .doc(merchantId)
      .collection("carts")
      .doc(customerId)
      .collection("items")
      .doc(productId);

    await itemRef.delete();
    res.status(200).json({ success: true });
  } catch (error) {
    console.error("Error removing from cart:", error);
    res.status(500).json({ error: "Failed to remove item" });
  }
});
