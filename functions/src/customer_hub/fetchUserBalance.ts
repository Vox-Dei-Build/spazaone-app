import { functions, db } from "../config/main";
import {
  MerchantDetails,
  normalizePhoneNumber,
} from "../contact/fetchUserBalance";
import { requireBotRequest } from "../security/requestAuth";

/**
 * HTTP GET Function to fetch the user balance.
 * @param {functions.https.Request} req - The HTTP request object.
 * @param {functions.Response} res - The HTTP response object.
 * @return {Promise<void>} - Sends the balance as an HTTP response.
 */
exports.fetchUserBalanceOption = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    const rawNumber = req.query.number as string; // Get phone number from query paramsnumber from the callable data

    if (!rawNumber) {
      console.error("No phone number provided in the request.");
      throw new functions.https.HttpsError(
        "invalid-argument",
        "The phone number must be provided.",
      );
    }

    const normalizedNumber = normalizePhoneNumber(
      rawNumber.replace("whatsapp:", ""),
    );
    console.log(`Normalized incoming number for matching: ${normalizedNumber}`);

    try {
      const customersRef = db.collectionGroup("customers");
      const querySnapshot = await customersRef
        .where("number", "==", normalizedNumber)
        .get();

      if (querySnapshot.empty) {
        res.status(404).send("No account found for this number.");
        return;
      }

      let totalBalance = 0;
      const merchantBalances: Record<string, MerchantDetails> = {};

      const promises = querySnapshot.docs.map(async (doc: any) => {
        const customer = doc.data();
        totalBalance += customer.balance;

        const pathSegments = doc.ref.path.split("/");
        const userId = pathSegments[1]; // Fetch the user ID from the path

        // Fetch merchant details
        const userRef = db.collection("users").doc(userId);
        const userDoc = await userRef.get();
        const user = userDoc.data();
        const name = user?.name || "Unknown";
        const shopName = user?.shopName || "Unknown Shop";

        // Combine balances per merchant
        if (!merchantBalances[userId]) {
          merchantBalances[userId] = {
            name: name,
            shopName: shopName,
            balance: 0,
          };
        }
        merchantBalances[userId].balance += customer.balance;
      });

      await Promise.all(promises);

      let message = "💰 Your current balance is:\n";
      for (const userId in merchantBalances) {
        if (Object.prototype.hasOwnProperty.call(merchantBalances, userId)) {
          const details = merchantBalances[userId];
          message += `\nMerchant: ${details.name} (${details.shopName}) - Balance: R${details.balance.toFixed(2)}\n`;
        }
      }
      message += `\nTotal balance across all accounts: R${totalBalance.toFixed(2)}`;

      console.log(`Final user balance response: ${message}`);
      res.status(200).send({ message });
    } catch (error) {
      console.error("Failed to fetch user balance:", error);
      res.status(500).send("Failed to fetch user balance.");
    }
  });
