import { createHash } from "crypto";
import { formatPhoneNumber, normalizePhoneNumber } from "../utils/phoneUtils";
import { functions, db } from "../config/main";
import { requireBotRequest } from "../security/requestAuth";
import { resolveBotStore } from "../stores/botStoreSelection";

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
    const rawPhone = rawNumber.replace("whatsapp:", "");
    const e164Number = formatPhoneNumber(rawPhone);
    const normalizedNumber = normalizePhoneNumber(rawPhone);
    if (!e164Number) {
      res.status(400).send("A valid South African phone number is required.");
      return;
    }
    console.log("Resolving merchant phone", {
      phoneLast4: normalizedNumber.slice(-4),
    });
    try {
      // Multi-store operators are mapped by a one-way phone hash. If an
      // operator belongs to several stores the bot must ask which store they
      // mean instead of silently performing an action in an arbitrary shop.
      const hash = createHash("sha256").update(e164Number).digest("hex");
      const access = await db
        .collection("operatorPhoneLookup")
        .doc(hash)
        .collection("stores")
        .where("status", "==", "active")
        .get();
      const requestedStoreId = String(req.query.storeId ?? "").trim();
      const requestedChoice = String(req.query.storeChoice ?? "").trim();
      const availableStores = access.docs.map((doc) => ({
        merchantId: doc.id,
        shopName: String(doc.data().storeName ?? "Store"),
        role: String(doc.data().role ?? "operator"),
      }));
      const resolution = resolveBotStore(
        availableStores,
        requestedStoreId,
        requestedChoice,
      );

      if (resolution.kind === "forbidden") {
        res.status(403).send("Operator does not have access to that store.");
        return;
      }
      if (resolution.kind === "selection-required") {
        res.status(200).send({
          requiresStoreSelection: true,
          prompt: "Which store would you like to use?",
          stores: resolution.stores.map((store, index) => ({
            ...store,
            choice: String(index + 1),
          })),
        });
        return;
      }
      if (resolution.kind === "selected") {
        const selected = resolution.store;
        const selectedStore = await db
          .doc(`users/${selected.merchantId}`)
          .get();
        if (!selectedStore.exists) {
          res.status(404).send("Selected store was not found.");
          return;
        }
        const merchant = selectedStore.data() ?? {};
        res.status(200).send({
          merchantDetails: {
            merchantId: selected.merchantId,
            merchantName: merchant.name || "Unknown Merchant",
            shopName: merchant.shopName || selected.shopName,
            merchantNumber: merchant.mobileNumber || "Unknown",
            operatorRole: selected.role,
          },
        });
        return;
      }

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
