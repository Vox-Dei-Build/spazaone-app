import { db, functions } from "../../../config/main";

/**
 * HTTP function to create an electricity order in Firestore.
 *
 * @param {functions.https.Request} req - The HTTP request object. It should contain the order data in the body.
 * @param {functions.Response} res - The HTTP response object. Returns the created order ID or an error message.
 *
 * @example
 * // POST request body:
 * {
 *   "meterNumber": "12345678910",
 *   "electricityMobileNumber": "648370009",
 *   "electricityRechargeAmount": 50,
 *   "merchantId": "GrOyq2IN3KUbsRhNLniiSFy24LG3",
 *   "customerId": "rchR772G652P5G0mPfvW"
 * }
 */
exports.createElectricityOrder = functions.https.onRequest(async (req, res) => {
  try {
    const orderData = req.body;
    const orderRef = db
      .collection("orders")
      .doc("vas")
      .collection("electricityOrders")
      .doc();
    const orderDetails = {
      ...orderData,
      createdAt: new Date(),
      updatedAt: new Date(),
      confirmation: "pending",
      accepted: false,
    };
    await orderRef.set(orderDetails);
    console.log("Electricity order created:", orderRef.id);
    res.status(200).send({ orderId: orderRef.id });
  } catch (error) {
    console.error("Error creating electricity order:", error);
    res.status(500).send("Error creating electricity order");
  }
});
