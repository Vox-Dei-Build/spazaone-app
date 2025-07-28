import { db, functions } from "../config/main";
import * as admin from "firebase-admin";

/**
 * HTTP endpoint to add a product to a customer's cart.
 *
 * @param {functions.https.Request} req Express request containing `merchantId`, `customerId`, `productId` and optional `quantity`.
 * @param {functions.Response} res Express response object.
 * @returns {Promise<void>}
 */
export const addToCart = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const { merchantId, customerId, productId, quantity = 1 } = req.body;

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

    await itemRef.set(
      { quantity: admin.firestore.FieldValue.increment(Number(quantity)) },
      { merge: true },
    );

    res.status(200).json({ success: true });
  } catch (error) {
    console.error("Error adding to cart:", error);
    res.status(500).json({ error: "Failed to add item" });
  }
});
