import { functions, db } from "../../config/main"; // Firebase config import
import axios from "axios";

const PAYSTACK_SECRET_KEY = process.env.PAYSTACK_TEST_SECRET_KEY;

/**
 * Webhook function to verify Paystack transactions.
 * @param {functions.https.Request} req - The HTTP request object.
 * @param {functions.Response} res - The HTTP response object.
 * @returns {Promise<void>}
 */
exports.verifyPaystackTransaction = functions.https.onRequest(
  async (req: functions.https.Request, res: functions.Response) => {
    try {
      const { event, data } = req.body;

      // Check if the event is a successful charge
      if (event !== "charge.success") {
        res.status(400).json({ error: "Invalid event type" });
        return;
      }

      const reference = data.reference;
      const userId = data.metadata?.userId;
      const amount = data.amount / 100; // Convert back to Rands

      if (!reference || !userId || !amount) {
        res.status(400).json({ error: "Missing transaction details" });
        return;
      }

      // ✅ Step 1: Verify transaction with Paystack API
      const verifyResponse = await axios.get(
        `https://api.paystack.co/transaction/verify/${reference}`,
        {
          headers: { Authorization: `Bearer ${PAYSTACK_SECRET_KEY}` },
        },
      );

      const paystackData = verifyResponse.data;
      if (!paystackData.status || paystackData.data.status !== "success") {
        throw new Error("Transaction verification failed");
      }

      // ✅ Step 2: Check if the transaction already exists
      const transactionRef = db
        .collection("users")
        .doc(userId)
        .collection("topUpTransactions")
        .doc(reference);

      const transactionSnapshot = await transactionRef.get();
      if (transactionSnapshot.exists) {
        console.log(`Transaction ${reference} already recorded.`);
        res.status(200).json({ success: true });
        return;
      }

      // ✅ Step 3: Update Firestore balance & log transaction
      const userRef = db.collection("users").doc(userId);

      await db.runTransaction(async (transaction) => {
        const userSnapshot = await transaction.get(userRef);
        const currentBalance = userSnapshot.data()?.virtualBalance || 0;

        transaction.update(userRef, {
          virtualBalance: currentBalance + amount,
        });

        transaction.set(transactionRef, {
          amount,
          status: "success",
          reference,
          createdAt: new Date(),
        });
      });

      console.log(`Transaction ${reference} verified and recorded.`);
      res.status(200).json({ success: true });
    } catch (error: any) {
      console.error("Error verifying Paystack transaction:", error);
      res.status(500).json({ error: "Transaction verification failed" });
    }
  },
);
