import { functions } from "../config/main";
import { updateBalancesWithEdit } from "./onTransactionAdded";

/**
 * HTTP endpoint to trigger balance update manually.
 * @param {functions.https.Request} req
 * @param {functions.Response} res
 * This function simulates the Firestore onWrite trigger for testing purposes.
 */
exports.testUpdateBalances = functions.https.onRequest(async (req, res) => {
  try {
    const { userId, customerId } = req.body;

    if (!userId || !customerId) {
      res
        .status(400)
        .json({ success: false, error: "Missing required fields." });
    }

    // Call the balance update function
    await updateBalancesWithEdit(userId, customerId);

    res
      .status(200)
      .send({ success: true, message: "Balance updated successfully" });
  } catch (error) {
    console.error("Error in testUpdateBalances:", error);
    res.status(500).send({ success: false, error: "Internal Server Error" });
  }
});
