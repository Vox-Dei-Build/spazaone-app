import { db, functions } from "../../config/main";

/**
 * HTTP function to update the status of an airtime or electricity order in Firestore.
 *
 * @param {functions.https.Request} req - The HTTP request object. It should contain the orderId, orderType (airtime/electricity), and the new status in the body.
 * @param {functions.Response} res - The HTTP response object. Returns a success message or an error message.
 *
 * @example
 * // POST request body:
 * // {
 * //   "orderId": "some-order-id",
 * //   "orderType": "airtime", // or "electricity"
 * //   "accepted": true
 * // }
 */
exports.updateOrderStatus = functions.https.onRequest(async (req, res) => {
  const { orderId, orderType, accepted } = req.body;

  if (!orderId || !orderType || accepted === undefined) {
    res
      .status(400)
      .send("Order ID, order type, and accepted status are required");
    return;
  }

  const collection =
    orderType === "airtime" ? "airtimeOrders" : "electricityOrders";

  try {
    const orderRef = db
      .collection("orders")
      .doc("vas")
      .collection(collection)
      .doc(orderId);
    await orderRef.update({
      accepted: accepted,
      confirmation: "confirmed",
      updatedAt: new Date(),
    });
    console.log(`Order ${orderId} updated to accepted: ${accepted}`);
    res.status(200).send(`Order ${orderId} updated successfully`);
  } catch (error) {
    console.error(`Error updating order ${orderId}:`, error);
    res.status(500).send(`Error updating order ${orderId}`);
  }
});
