import { functions } from "../../config/main"; // Firebase or GCP cloud function import
import axios from "axios";

const PAYSTACK_SECRET_KEY = process.env.PAYSTACK_TEST_SECRET_KEY; // 🔥 Use live key for production

/**
 * Cloud Function to create a Paystack transaction.
 *
 * @param {functions.https.Request} req - The HTTP request object.
 * @param {functions.Response} res - The HTTP response object.
 * @returns {Promise<void>} - JSON response with Paystack authorization URL.
 */
exports.createPaystackTransaction = functions.https.onRequest(
  async (req: functions.https.Request, res: functions.Response) => {
    try {
      const { userId, amount, email } = req.body;

      // Validate input
      if (
        !userId ||
        !amount ||
        typeof amount !== "number" ||
        amount <= 0 ||
        !email
      ) {
        res.status(400).json({ error: "Invalid userId, amount, or email" });
        return;
      }

      // Call Paystack API to initialize transaction
      const paystackResponse = await axios.post(
        "https://api.paystack.co/transaction/initialize",
        {
          email: email,
          amount: amount * 100, // Convert Rands to cents
          currency: "ZAR",
          callback_url: "myapp://payment-success",
          metadata: { userId },
        },
        {
          headers: {
            Authorization: `Bearer ${PAYSTACK_SECRET_KEY}`,
            "Content-Type": "application/json",
          },
        },
      );

      if (!paystackResponse.data.status) {
        throw new Error("Paystack transaction initialization failed");
      }

      // ✅ Send response with checkout URL
      res.status(200).json({
        success: true,
        authorizationUrl: paystackResponse.data.data.authorization_url,
      });
    } catch (error: any) {
      console.error("Error creating Paystack transaction:", error);
      res.status(500).json({
        error: "Failed to create transaction",
        details: error.message,
      });
    }
  },
);
