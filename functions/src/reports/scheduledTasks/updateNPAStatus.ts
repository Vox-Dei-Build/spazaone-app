import {
  DocumentData,
  FieldPath,
  FieldValue,
  QueryDocumentSnapshot,
  QuerySnapshot,
} from "firebase-admin/firestore";
import { functions, db } from "../../config/main";

const LEGACY_NPA_AUDIT_BATCH_SIZE = 10;
const LEGACY_NPA_AUDIT_REST_MS = 24 * 60 * 60 * 1000;
const LEGACY_NPA_AUDIT_STATE_PATH = "maintenanceState/npaLegacyAudit";

/**
 * Scheduled function to update Non-Performing Assets (NPA) status for customers.
 *
 * The current source-of-truth rule is simple: a customer is NPA iff
 * `balance < 0`. The primary writer of `isNPA` is now the transaction
 * trigger (see `onTransactionAdded.ts`), which keeps the flag in lockstep
 * with `balance`. This scheduled job is a safety net that repairs persisted
 * contradictions without rereading every correctly classified debtor each
 * hour:
 *
 *   1. Catches customers with a negative balance whose `isNPA` is false.
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
    const result = await updateNPAs();
    console.log("📊 NPA status update result", result);
    console.log("✅ NPA status update completed.");
    return null;
  });

/**
 * Updates the NPA status of customers.
 */
export async function updateNPAs(): Promise<{
  scanned: number;
  corrected: number;
  legacyAudited: number;
  legacyCorrected: number;
}> {
  // Query only contradictions. New customers always persist isNPA=false and
  // every transaction write recomputes it, so a permanent full legacy scan is
  // unnecessary and repeatedly bills reads for rows that need no update.
  const negativeBalance = await sweep(
    db
      .collectionGroup("customers")
      .where("isNPA", "==", false)
      .where("balance", "<", 0)
      .orderBy("balance", "asc"),
    "negative-balance-not-flagged",
  );

  const settledBalance = await sweep(
    db
      .collectionGroup("customers")
      .where("isNPA", "==", true)
      .where("balance", ">=", 0)
      .orderBy("balance", "asc"),
    "settled-balance-still-flagged",
  );
  const legacy = await auditLegacyNPAState();
  return {
    scanned: negativeBalance.scanned + settledBalance.scanned,
    corrected: negativeBalance.corrected + settledBalance.corrected,
    legacyAudited: legacy.scanned,
    legacyCorrected: legacy.corrected,
  };
}

/**
 * Repairs old customer rows where isNPA is absent, which Firestore cannot
 * select with an equality filter. The persisted cursor caps this fallback at
 * ten reads per hourly run and rests for a day after completing a full cycle.
 */
async function auditLegacyNPAState(): Promise<{
  scanned: number;
  corrected: number;
}> {
  const stateRef = db.doc(LEGACY_NPA_AUDIT_STATE_PATH);
  const state = await stateRef.get();
  const stateData = state.data() ?? {};
  const nowMs = Date.now();
  if (Number(stateData.nextCycleAtMs ?? 0) > nowMs) {
    return { scanned: 0, corrected: 0 };
  }

  const cursorPath = String(stateData.cursorPath ?? "");
  let query = db
    .collectionGroup("customers")
    .orderBy(FieldPath.documentId(), "asc")
    .limit(LEGACY_NPA_AUDIT_BATCH_SIZE);
  if (/^users\/[^/]+\/customers\/[^/]+$/.test(cursorPath)) {
    query = query.startAfter(cursorPath);
  }
  const snapshot = await query.get();
  const batch = db.batch();
  let corrected = 0;
  for (const customer of snapshot.docs) {
    const derived = await checkAndUpdateNPA(customer);
    if (customer.data().isNPA !== derived) {
      batch.update(customer.ref, { isNPA: derived });
      corrected += 1;
    }
  }

  const cycleComplete = snapshot.size < LEGACY_NPA_AUDIT_BATCH_SIZE;
  batch.set(
    stateRef,
    {
      cursorPath:
        cycleComplete || snapshot.empty
          ? FieldValue.delete()
          : snapshot.docs[snapshot.docs.length - 1].ref.path,
      nextCycleAtMs: cycleComplete
        ? nowMs + LEGACY_NPA_AUDIT_REST_MS
        : FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await batch.commit();
  return { scanned: snapshot.size, corrected };
}

/**
 * Pages through a query, recomputing isNPA for each customer and writing
 * only when the stored value disagrees with the derived value.
 */
async function sweep(
  baseQuery: FirebaseFirestore.Query<DocumentData>,
  label: string,
): Promise<{ scanned: number; corrected: number }> {
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
        console.error(
          `❌ [${label}] Error processing customer ${doc.id}:`,
          error,
        );
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
  return { scanned: processedCount, corrected: writeCount };
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
