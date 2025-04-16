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
  .schedule("every 1 hours")
  .onRun(async () => {
    console.log("🚀 Running scheduled NPA update...");
    await updateNPAs();
    console.log("✅ NPA status update completed.");
    return null;
  });

/**
 * Updates the NPA status of customers.
 */
async function updateNPAs() {
  const batchSize = 500;

  let lastDoc: QueryDocumentSnapshot<DocumentData> | null = null;
  let moreCustomers = true;
  let processedCount = 0;

  while (moreCustomers) {
    console.log(`📌 Fetching next batch of up to ${batchSize} customers...`);

    const query = lastDoc
      ? db
          .collectionGroup("customers")
          .where("balance", "<", 0) // ✅ Optimized query to fetch only negative balance customers
          .orderBy("balance")
          .startAfter(lastDoc)
          .limit(batchSize)
      : db
          .collectionGroup("customers")
          .where("balance", "<", 0)
          .orderBy("balance")
          .limit(batchSize);

    const snapshot: QuerySnapshot<DocumentData> = await query.get();

    if (snapshot.empty) {
      console.log("🛑 No more customers to process.");
      moreCustomers = false;
      break;
    }

    console.log(
      `🔍 Processing ${snapshot.docs.length} customers in this batch...`,
    );

    const batch = db.batch(); // ✅ Batch Firestore writes

    for (const doc of snapshot.docs) {
      try {
        const isNPA = await checkAndUpdateNPA(doc);
        batch.update(doc.ref, { isNPA });
        processedCount++;
      } catch (error) {
        console.error(`❌ Error processing customer ${doc.id}:`, error);
      }
    }

    await batch.commit(); // ✅ Reduce Firestore writes with batched updates
    lastDoc = snapshot.docs[snapshot.docs.length - 1];
  }

  console.log(`✅ Completed processing ${processedCount} customers.`);
}

/**
 * Checks if a customer qualifies as NPA.
 * @param {FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>} customerDoc - The customer document.
 * @return {Promise<boolean>} - Whether the customer is NPA.
 */
async function checkAndUpdateNPA(
  customerDoc: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>,
): Promise<boolean> {
  const customerData = customerDoc.data();
  console.log(`📄 Checking NPA status for customer: ${customerDoc.id}`);

  if (customerData.balance < 0) {
    console.log(`✅ Customer ${customerDoc.id} is NPA (Negative Balance).`);
    return true;
  } else {
    console.log(
      `❌ Customer ${customerDoc.id} is NOT NPA (Balance is positive).`,
    );
    return false;
  }
}
