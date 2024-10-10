import { normalizePhoneNumber } from "..";
import { functions, db } from "../config/main";

/**
 * HTTP GET Function to fetch the most recent customer and merchant details based on the phone number.
 *
 * This function queries Firestore to retrieve both the customer details (e.g., name, balance)
 * and the associated merchant (user) details (e.g., merchant name, shop name) based on
 * the provided phone number. It compares the `lastTransaction.date` for customers and
 * `lastUpdated` for merchants to return the most recent details.
 *
 * @param {functions.https.Request} req - The HTTP request object. The phone number should be provided as a query parameter (e.g., `number=whatsapp:+123456789`).
 * @param {functions.Response} res - The HTTP response object. It will return the customer and merchant details as JSON.
 *
 * @returns {Promise<void>} - Responds with the customer and merchant details or an error message.
 *
 * @example
 * // Example request:
 * // GET https://your-firebase-url.cloudfunctions.net/fetchCustomerAndMerchantDetails?number=whatsapp:+123456789
 *
 * // Example response:
 * {
 *   "customerDetails": {
 *       "customerId": "customer1",
 *       "customerName": "John Doe",
 *       "customerBalance": 150.00,
 *       "customerNumber": "0648370009"
 *   },
 *   "merchantDetails": {
 *       "merchantId": "merchant1",
 *       "merchantName": "Jane Smith",
 *       "shopName": "Jane's Grocery Store",
 *       "merchantNumber": "0621234567"
 *   }
 * }
 *
 * @throws {400} - If the phone number is not provided in the request.
 * @throws {404} - If no customer or merchant details are found for the provided phone number.
 * @throws {500} - If there is a server error while querying Firestore.
 */
exports.fetchCustomerAndMerchantDetails = functions.https.onRequest(
  async (req, res) => {
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
      // Query customers based on the phone number
      const customersRef = db.collectionGroup("customers");
      const customerSnapshot = await customersRef
        .where("number", "==", normalizedNumber)
        .get();

      if (customerSnapshot.empty) {
        res.status(404).send("No customers found with this number.");
        return;
      }

      // Variables to store the most recent customer and merchant details
      let mostRecentCustomer = null;
      let mostRecentMerchant = null;

      let latestCustomerDate = new Date(0); // Initialize with an old date
      let latestMerchantDate = new Date(0); // Initialize with an old date

      // Process each customer document
      const customerPromises = customerSnapshot.docs.map(
        async (customerDoc: any) => {
          const customer = customerDoc.data();

          // Get the last transaction date for the customer
          const lastTransactionDate = customer.lastTransaction?.date?.toDate();

          if (lastTransactionDate && lastTransactionDate > latestCustomerDate) {
            latestCustomerDate = lastTransactionDate;
            mostRecentCustomer = {
              customerId: customerDoc?.id,
              customerName: customer?.name || "Unknown Customer",
              customerBalance: customer?.balance || 0,
              customerNumber: customer?.number || "Unknown",
            };

            // Fetch the corresponding merchant (user) details
            const pathSegments = customerDoc.ref.path.split("/");
            const userId = pathSegments[1];
            const userRef = db.collection("users").doc(userId);
            const userDoc = await userRef.get();

            if (userDoc.exists) {
              const merchant = userDoc.data();

              const merchantLastUpdated =
                merchant?.balanceData?.lastUpdated?.toDate();

              // Compare lastUpdated date for merchants
              if (
                merchantLastUpdated &&
                merchantLastUpdated > latestMerchantDate
              ) {
                latestMerchantDate = merchantLastUpdated;
                mostRecentMerchant = {
                  merchantId: userId,
                  merchantName: merchant?.name || "Unknown Merchant",
                  shopName: merchant?.shopName || "Unknown Shop",
                  merchantNumber: merchant?.mobileNumber || "Unknown",
                };
              }
            }
          }
        },
      );

      await Promise.all(customerPromises);

      if (!mostRecentCustomer || !mostRecentMerchant) {
        res.status(404).send("No recent customer or merchant found.");
        return;
      }

      // Send response with the most recent customer and merchant details
      res.status(200).send({
        customerDetails: mostRecentCustomer,
        merchantDetails: mostRecentMerchant,
      });
    } catch (error) {
      console.error("Failed to fetch customer and merchant details:", error);
      res.status(500).send("Failed to fetch customer and merchant details.");
    }
  },
);
