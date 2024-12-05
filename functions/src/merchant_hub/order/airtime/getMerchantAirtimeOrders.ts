import { db, functions } from "../../../config/main";
import { AirtimeOrder } from "../types/orderModel";

/**
 * HTTP function to retrieve all pending airtime orders for a specific merchant.
 *
 * @param {functions.https.Request} req - The HTTP request object. It should contain the merchantId as a query parameter.
 * @param {functions.Response} res - The HTTP response object. Returns a list of pending airtime orders for the merchant or an error message.
 *
 * @example
 * // GET request:
 * // https://your-cloud-function-url/merchantAirtimeOrders?merchantId=GrOyq2IN3KUbsRhNLniiSFy24LG3
 */
exports.getMerchantAirtimeOrders = functions.https.onRequest(
  async (req, res) => {
    const merchantId = req.query.merchantId;
    if (!merchantId) {
      res.status(400).send("Merchant ID is required");
      return;
    }

    try {
      const ordersSnapshot = await db
        .collection("orders")
        .doc("vas")
        .collection("airtimeOrders")
        .where("merchantId", "==", merchantId)
        .where("accepted", "==", false)
        .where("confirmation", "==", "pending")
        .get();

      if (ordersSnapshot.empty) {
        res.status(404).send("No airtime orders found for this merchant.");
        return;
      }
      const orders: AirtimeOrder[] = [];
      ordersSnapshot.forEach((doc: any) => {
        orders.push({ id: doc.id, ...doc.data() });
      });

      res.status(200).send(orders);
    } catch (error) {
      console.error("Error fetching merchant airtime orders:", error);
      res.status(500).send("Error fetching merchant airtime orders");
    }
  },
);
