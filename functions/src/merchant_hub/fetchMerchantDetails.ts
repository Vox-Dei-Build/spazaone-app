import { normalizePhoneNumber } from "..";
import { functions, db } from "../config/main";
import { requireBotRequest } from "../security/requestAuth";

/**
 * HTTP GET Function to fetch the most recent merchant details based on the phone number.
 *
 * This function queries Firestore to retrieve merchant (user) details (e.g., merchant name, shop name)
 * based on the provided phone number. It compares the `lastUpdated` for merchants to return the most recent details.
 *
 * @param {functions.https.Request} req - The HTTP request object. The phone number should be provided as a query parameter (e.g., `number=whatsapp:+123456789`).
 * @param {functions.Response} res - The HTTP response object. It will return the merchant details as JSON.
 *
 * @returns {Promise<void>} - Responds with the merchant details or an error message.
 *
 * @example
 * // Example request:
 * // GET https://your-firebase-url.cloudfunctions.net/fetchMerchantDetails?number=whatsapp:+123456789
 *
 * // Example response:
 * {
 *   "merchantDetails": {
 *       "merchantId": "merchant1",
 *       "merchantName": "Jane Smith",
 *       "shopName": "Jane's Grocery Store",
 *       "merchantNumber": "0621234567"
 *   }
 * }
 *
 * @throws {400} - If the phone number is not provided in the request.
 * @throws {404} - If no merchant details are found for the provided phone number.
 * @throws {500} - If there is a server error while querying Firestore.
 */
exports.fetchMerchantDetails = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    const rawNumber = req.query.number as string; // Get phone number from query params
    if (!rawNumber) {
      res.status(400).send("The phone number must be provided.");
      return;
    }
    const normalizedNumber = normalizePhoneNumber(
      rawNumber.replace("whatsapp:", ""),
    );
    console.log(`Normalized incoming number for matching: ${normalizedNumber}`);
    try {
      // Query users (merchants) based on the phone number
      const usersRef = db.collection("users");
      const userSnapshot = await usersRef
        .where("mobileNumber", "==", normalizedNumber)
        .get();

      if (userSnapshot.empty) {
        res.status(404).send("No merchants found with this number.");
        return;
      }

      // Variables to store the most recent merchant details
      let mostRecentMerchant = null;
      let latestMerchantDate = new Date(0); // Initialize with an old date

      // Process each user document
      userSnapshot.docs.forEach((userDoc) => {
        const merchant = userDoc.data();
        const merchantLastUpdated =
          merchant?.balanceData?.lastUpdated?.toDate();
        if (merchantLastUpdated && merchantLastUpdated > latestMerchantDate) {
          latestMerchantDate = merchantLastUpdated;
          mostRecentMerchant = {
            merchantId: userDoc.id,
            merchantName: merchant?.name || "Unknown Merchant",
            shopName: merchant?.shopName || "Unknown Shop",
            merchantNumber: merchant?.mobileNumber || "Unknown",
          };
        }
      });

      if (!mostRecentMerchant) {
        res.status(404).send("No recent merchant found.");
        return;
      }

      // Send response with the most recent merchant details
      res.status(200).send({ merchantDetails: mostRecentMerchant });
    } catch (error) {
      console.error("Failed to fetch merchant details:", error);
      res.status(500).send("Failed to fetch merchant details.");
    }
  });
