import {
  DocumentData,
  QueryDocumentSnapshot,
  QuerySnapshot,
} from "firebase-admin/firestore";
import { functions, db } from "../../config/main";

/**
 * Scheduled function to update Non-Performing Assets (NPA) status for customers.
 *
 * The current source-of-truth rule is simple: a customer is NPA iff
 * `balance < 0`. The primary writer of `isNPA` is now the transaction
 * trigger (see `onTransactionAdded.ts`), which keeps the flag in lockstep
 * with `balance`. This scheduled job is a safety net that:
 *
 *   1. Catches customers with a negative balance whose `isNPA` is missing
 *      or wrong (e.g. legacy rows, manual edits, dropped trigger events).
 *   2. Clears stale `isNPA: true` flags on customers who have since paid
 *      up (`balance >= 0`). The previous query only inspected
 *      negative-balance customers, so paid-up customers could remain
 *      marked NPA indefinitely — that is the trust-recovery bug
 *      addressed by PAS-UX-08.
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
  // Sweep 1: customers with a negative balance — ensure isNPA === true.
  await sweep(
    db
      .collectionGroup("customers")
      .where("balance", "<", 0)
      .orderBy("balance"),
    "negative-balance",
  );

  // Sweep 2: customers still flagged isNPA === true — clear the flag for
  // any whose balance is now >= 0. This is the missing reset path.
  await sweep(
    db.collectionGroup("customers").where("isNPA", "==", true),
    "flagged-isNPA",
  );
}

/**
 * Pages through a query, recomputing isNPA for each customer and writing
 * only when the stored value disagrees with the derived value.
 */
async function sweep(
  baseQuery: FirebaseFirestore.Query<DocumentData>,
  label: string,
) {
  const batchSize = 500;
  let lastDoc: QueryDocumentSnapshot<DocumentData> | null = null;
  let moreCustomers = true;
  let processedCount = 0;
  let writeCount = 0;

  while (moreCustomers) {
    console.log(
      `📌 [${label}] Fetching next batch of up to ${batchSize} customers...`,
    );

    const query = lastDoc
      ? baseQuery.startAfter(lastDoc).limit(batchSize)
      : baseQuery.limit(batchSize);

    const snapshot: QuerySnapshot<DocumentData> = await query.get();

    if (snapshot.empty) {
      console.log(`🛑 [${label}] No more customers to process.`);
      moreCustomers = false;
      break;
    }

    console.log(
      `🔍 [${label}] Processing ${snapshot.docs.length} customers in this batch...`,
    );

    const batch = db.batch();
    let pendingWrites = 0;

    for (const doc of snapshot.docs) {
      try {
        const derived = await checkAndUpdateNPA(doc);
        const stored = doc.data().isNPA;
        if (stored !== derived) {
          batch.update(doc.ref, { isNPA: derived });
          pendingWrites++;
        }
        processedCount++;
      } catch (error) {
        console.error(`❌ [${label}] Error processing customer ${doc.id}:`, error);
      }
    }

    if (pendingWrites > 0) {
      await batch.commit();
      writeCount += pendingWrites;
    }
    lastDoc = snapshot.docs[snapshot.docs.length - 1];
  }

  console.log(
    `✅ [${label}] Completed: scanned ${processedCount}, corrected ${writeCount}.`,
  );
}

/**
 * Derives whether a customer qualifies as NPA from their stored balance.
 *
 * Rule: a customer is NPA iff `balance < 0`. This is the single source of
 * truth used by the transaction trigger, the scheduled sweep, and (as a
 * client-side safeguard) the customer list stream.
 *
 * @param {FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>} customerDoc - The customer document.
 * @return {Promise<boolean>} - Whether the customer is NPA.
 */
async function checkAndUpdateNPA(
  customerDoc: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>,
): Promise<boolean> {
  const customerData = customerDoc.data();
  const balance = (customerData.balance as number | undefined) ?? 0;
  return balance < 0;
}
