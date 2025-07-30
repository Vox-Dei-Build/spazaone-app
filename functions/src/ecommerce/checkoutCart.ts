import { db, functions } from "../config/main";
import * as admin from "firebase-admin";
/**
 * HTTP endpoint to convert a customer's cart into a sale.
 * Records payment type, delivery info and marks status based on payment.
 *
 * @param {functions.https.Request} req Express request with merchant/customer ids and options.
 * @param {functions.Response} res Express response with sale id.
 * @returns {Promise<void>}
 */

export const checkoutCart = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const {
    merchantId,
    customerId,
    paymentType = "Online",
    deliveryInfo = "",
    remarks = "",
  } = req.body;
  if (!merchantId || !customerId) {
    res.status(400).json({ error: "merchantId and customerId are required" });
    return;
  }

  try {
    const cartRef = db
      .collection("users")
      .doc(merchantId)
      .collection("carts")
      .doc(customerId)
      .collection("items");

    const itemsSnap = await cartRef.get();
    if (itemsSnap.empty) {
      res.status(400).json({ error: "Cart is empty" });
      return;
    }

    const products: Record<string, number> = {};
    let total = 0;

    for (const doc of itemsSnap.docs) {
      const { quantity = 0 } = doc.data();
      products[doc.id] = quantity;
      const productRef = db
        .collection("users")
        .doc(merchantId)
        .collection("products")
        .doc(doc.id);
      const productDoc = await productRef.get();
      const productData = productDoc.exists ? productDoc.data() : {};
      const price = productData?.productPrice || 0;
      total += price * quantity;
      if (productDoc.exists && productData?.quantity !== undefined) {
        await productRef.update({
          quantity: admin.firestore.FieldValue.increment(-quantity),
        });
      }
    }

    const saleData = {
      amount: total,
      type: paymentType,
      status: paymentType === "Online" ? "pending" : "paid",
      customerId,
      dateAdded: admin.firestore.Timestamp.now(),
      products,
      remarks,
      deliveryInfo,
    };

    const saleRef = await db
      .collection("users")
      .doc(merchantId)
      .collection("sales")
      .add(saleData);

    await db
      .collection("users")
      .doc(merchantId)
      .update({ lastSaleTransaction: saleData });

    const batch = db.batch();
    itemsSnap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    res.status(200).json({ success: true, saleId: saleRef.id });
  } catch (error) {
    console.error("Error completing checkout:", error);
    res.status(500).json({ error: "Failed to checkout" });
  }
});
