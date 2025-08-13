import { db, functions } from "../config/main";
/**
 * HTTP endpoint to list all orders for a customer.
 *
 * @param {functions.https.Request} req Express request with `merchantId` and `customerId`.
 * @param {functions.Response} res Express response containing an array of orders.
 * @returns {Promise<void>}
 */

export const getCustomerOrders = functions.https.onRequest(async (req, res) => {
  const merchantId = (req.query.merchantId || req.body.merchantId) as string;
  const customerId = (req.query.customerId || req.body.customerId) as string;

  if (!merchantId || !customerId) {
    res.status(400).json({ error: "merchantId and customerId are required" });
    return;
  }

  try {
    const ordersSnap = await db
      .collection("users")
      .doc(merchantId)
      .collection("sales")
      .where("customerId", "==", customerId)
      .orderBy("dateAdded", "desc")
      .get();

    const orders = ordersSnap.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));

    res.status(200).json({ orders });
  } catch (error) {
    console.error("Error fetching orders:", error);
    res.status(500).json({ error: "Failed to fetch orders" });
  }
});
