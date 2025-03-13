import { db, functions } from "../config/main"; // Firebase or GCP cloud function import
import moment from "moment"; // To calculate dates
import { normalizePhoneNumber } from "../contact/fetchUserBalance";
import axios from "axios";

/**
 * Google Cloud Function to send promotional messages to active customers using Twilio.
 * Test mode is used to prevent actual sending during testing.
 */
exports.sendPromoToActiveCustomers = functions.https.onRequest(
  async (req, res) => {
    const {
      templateId,
      testMode = true,
      excludedMerchantNumbers = [],
      excludedCustomerNumbers = [],
    } = req.body; // Template ID, testMode flag, and excluded merchant numbers

    try {
      const usersRef = db.collection("users");
      const usersSnapshot = await usersRef.get();

      // Process each user
      const promises = usersSnapshot.docs.map(async (userDoc) => {
        const userData = userDoc.data();
        const balanceData = userData.balanceData;
        const userPhoneNumber = userData.mobileNumber;

        // Skip merchants that are in the exclusion list
        if (excludedMerchantNumbers.includes(userPhoneNumber)) {
          console.log(`Skipping merchant with phone number ${userPhoneNumber}`);
          return;
        }

        if (balanceData) {
          const lastUpdatedDate = moment(balanceData.lastUpdated.toDate());
          const oneMonthAgo = moment().subtract(1, "month");
          // Filter for active users (lastUpdated within the last month)
          if (lastUpdatedDate.isAfter(oneMonthAgo)) {
            console.log("=====================================");
            console.log("Active User");
            console.log(userData.name);
            console.log(userData.shopName);
            console.log(userData.mobileNumber);
            console.log(balanceData.totalCustomers);
            const customersRef = usersRef
              .doc(userDoc.id)
              .collection("customers");
            const customersSnapshot = await customersRef.get();

            // Process each customer
            const messagePromises = customersSnapshot.docs.map(
              async (customerDoc) => {
                const customerData = customerDoc.data();
                const phoneNumber = customerData.number;

                if (!phoneNumber) {
                  console.log(`No phone number for customer ${customerDoc.id}`);
                  return; // Skip if no phone number
                }

                if (excludedCustomerNumbers.includes(phoneNumber)) {
                  console.log(
                    `Skipping customer with phone number ${phoneNumber}`,
                  );
                  return;
                }

                // Normalize the phone number
                const normalizedNumber = normalizePhoneNumber(phoneNumber);
                const whatsappNumber = `whatsapp:+27${normalizedNumber.slice(1)}`; // Format for WhatsApp

                const templateParams = {
                  merchant_name: userData.name, // Merchant name from user data
                  shop_name: userData.shopName, // Shop name from user data
                };

                // Logging details for debugging
                console.log(
                  `Prepared message for ${whatsappNumber} for customer ${customerDoc.id}`,
                );
                console.log(`Template Params:`, templateParams);

                // If testMode is on, just log the message and don't send it
                if (testMode) {
                  console.log(
                    `[TEST MODE] Message to ${whatsappNumber} would have been sent here.`,
                  );
                } else {
                  // Sending the message via axios POST request when not in test mode
                  const messageData = {
                    to: whatsappNumber,
                    templateId,
                    templateParams,
                    botType: "Customer", // Assuming this is customer related
                  };

                  try {
                    const response = await axios.post(
                      "https://us-central1-pasella-ledger.cloudfunctions.net/sendTwilioMessage",
                      messageData,
                    );

                    console.log(
                      `Successfully sent message to via sendTwilioMessage ${whatsappNumber}:`,
                      response.data,
                    );
                  } catch (err) {
                    console.error(
                      `Failed to send message to ${whatsappNumber}:`,
                      err,
                    );
                  }
                }
              },
            );

            // Wait for all customer messages to be processed
            await Promise.all(messagePromises);
          } else {
            console.log(
              `Skipping user ${userDoc.id}: Not active in the last month.`,
            );
          }
        } else {
          console.log(`Skipping user ${userDoc.id}: Doesn't have balance data`);
        }
      });

      // Wait for all users to be processed
      await Promise.all(promises);

      res.status(200).send("Promotional messages processed successfully!");
    } catch (error) {
      console.error("Error processing promotional messages:", error);
      res.status(500).send("Failed to process promotional messages");
    }
  },
);
