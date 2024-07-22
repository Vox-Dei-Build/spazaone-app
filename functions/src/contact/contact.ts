import { functions } from "../config/main";
import * as admin from "firebase-admin";

exports.addPayment = functions.https.onCall(async (data, context) => {
  // Ensure the user is authenticated
  if (!context.auth) {
    console.warn("User not authenticated.");
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated to generate a report.",
    );
  }

  // Validate input data
  const { customerId, currentUserId, transactionData } = data;
  if (!customerId || !currentUserId || !transactionData) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Required fields are missing.",
    );
  }

  const customerRef = admin
    .firestore()
    .collection("users")
    .doc(currentUserId)
    .collection("customers")
    .doc(customerId);

  const transactionRef = customerRef.collection("transactions").doc();

  let customerData;
  try {
    // First, fetch the latest customer data outside the transaction
    const customerDoc = await customerRef.get();
    customerData = customerDoc.data();
  } catch (error) {
    console.error("Error fetching customer data:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to fetch customer data.",
    );
  }

  const updates: any = {
    lastTransaction: transactionData,
  };

  if (customerData) {
    const balance = customerData["balance"];
    const lastTransaction = customerData["lastTransaction"];

    if (balance >= 0) {
      updates.isNPA = false;
    } else if (
      lastTransaction["type"] === "Credit" &&
      lastTransaction["status"] === "DUE"
    ) {
      const lastCreditDate = lastTransaction["date"].toDate();
      const currentDate = new Date();
      const oneMonthAgo = new Date(
        currentDate.setMonth(currentDate.getMonth() - 1),
      );

      if (lastCreditDate > oneMonthAgo) {
        updates.isNPA = false;
      }
    }
  }

  try {
    // Now, use the transaction to perform all the writes
    await admin.firestore().runTransaction(async (transaction) => {
      transaction.set(transactionRef, transactionData);
      transaction.update(customerRef, updates);
    });
  } catch (error) {
    console.error("Error during transaction:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to process transaction.",
    );
  }

  return { success: true };
});
