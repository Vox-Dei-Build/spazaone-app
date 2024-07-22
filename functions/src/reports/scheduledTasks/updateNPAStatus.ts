import {
  DocumentData,
  QueryDocumentSnapshot,
  QuerySnapshot,
} from "firebase-admin/firestore";
import { functions, db } from "../../config/main";

/**
 * Scheduled function to update Non-Performing Assets (NPA) status for customers.
 *
 * An NPA customer is determined based on the following conditions:
 * 1. The customer has a negative balance.
 * 2. The customer's last transaction was a credit transaction that is due and is older than a month.
 * OR
 * 3. The customer's last transaction was a payment, but a previous credit transaction is due and is older than a month.
 *
 * The function performs two main checks:
 * - Direct Query: Directly fetches customers with a negative balance whose last credit transaction is due and is older than a month.
 * - Extended Check: For customers with a negative balance whose last transaction was a payment, it checks their transaction history to find the last credit transaction that is due and is older than a month.
 *
 */
export const scheduledNPAUpdate = functions.pubsub
  .schedule("every 24 hours")
  .onRun(async () => {
    console.log("Running scheduled NPA update");
    await updateNPAs();
    console.log("NPA status updated for all customers");
    return null;
  });

/**
 * Updates the NPA status of customers.
 */
async function updateNPAs() {
  const batchSize = 500;
  const currentDate = new Date();
  const oneMonthAgo = new Date(
    currentDate.getFullYear(),
    currentDate.getMonth() - 1,
    currentDate.getDate(),
  );

  let lastDoc: QueryDocumentSnapshot<DocumentData> | null = null;
  let moreCustomers = true;

  while (moreCustomers) {
    const query = db
      .collectionGroup("customers")
      .orderBy("balance")
      .startAfter(lastDoc)
      .limit(batchSize);

    const snapshot: QuerySnapshot<DocumentData> = await query.get();
    if (snapshot.empty) {
      console.log("No more customers to process");
      moreCustomers = false;
      break;
    }

    // Process each customer in the batch
    for (const doc of snapshot.docs) {
      await checkAndUpdateNPA(doc, oneMonthAgo);
    }

    // Prepare for the next batch
    lastDoc = snapshot.docs[snapshot.docs.length - 1];
  }
}
/**
 * Checks and updates the NPA status for a specific customer.
 * @param {FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>} customerDoc - The customer document.
 * @param {Date} oneMonthAgo - Date one month before the current date.
 */
async function checkAndUpdateNPA(
  customerDoc: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>,
  oneMonthAgo: Date,
) {
  const customerData = customerDoc.data();
  const lastTransaction = customerData.lastTransaction;
  const lastTransactionDate = lastTransaction.date.toDate();
  let isNPA = false;

  if (customerData.balance < 0) {
    // Check if the last transaction was a credit transaction that is due and older than a month
    if (
      lastTransaction.type === "Credit" &&
      lastTransaction.status === "DUE" &&
      lastTransactionDate <= oneMonthAgo
    ) {
      isNPA = true;
    }
  }

  console.log("updating to isNPA");
  console.log(isNPA);
  console.log("For");
  console.log(customerData);

  // Update the customer's NPA status
  await customerDoc.ref.update({ isNPA });
}
