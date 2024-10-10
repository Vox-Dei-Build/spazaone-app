import { db, functions } from "../../../config/main";

/**
 * HTTP function to create an airtime order in Firestore.
 *
 * @param {functions.https.Request} req - The HTTP request object. It should contain the order data in the body.
 * @param {functions.Response} res - The HTTP response object. Returns the created order ID or an error message.
 *
 * @example
 * // POST request body:
 * {
 *   "mobileNumber": "0648370009",
 *   "airtimeRechargeAmount": 50,
 *   "mobileProvider": "Vodacom",
 *   "merchantId": "GrOyq2IN3KUbsRhNLniiSFy24LG3",
 *   "customerId": "rchR772G652P5G0mPfvW"
 *   "confirmation": "Yes"
 * }
 */
exports.createAirtimeOrder = functions.https.onRequest(async (req, res) => {
  try {
    const orderData = req.body;
    const orderRef = db
      .collection("orders")
      .doc("vas")
      .collection("airtimeOrders")
      .doc();
    const orderDetails = {
      ...orderData,
      createdAt: new Date(),
      updatedAt: new Date(),
      confirmation: "pending",
      accepted: false,
    };
    await orderRef.set(orderDetails);
    console.log("Airtime order created:", orderRef.id);
    res.status(200).send({ orderId: orderRef.id });
  } catch (error) {
    console.error("Error creating airtime order:", error);
    res.status(500).send("Error creating airtime order");
  }
});
