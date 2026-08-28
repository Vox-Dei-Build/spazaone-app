import { FieldPath, FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import {
  whatsappCatalogMerchantAllowed,
  whatsappCatalogRuntimeConfig,
} from "./catalogConfig";
import { enqueueMerchantProductCatalogSync } from "./catalogQueue";

const RECONCILIATION_STATE_PATH =
  "whatsappCatalogSyncState/productReconciliation";

function productIdentity(path: string): {
  merchantId: string;
  productId: string;
} | null {
  const parts = path.split("/");
  return parts.length === 4 && parts[0] === "users" && parts[2] === "products"
    ? { merchantId: parts[1], productId: parts[3] }
    : null;
}

async function enqueueWithConcurrency(
  products: readonly { merchantId: string; productId: string }[],
): Promise<number> {
  let next = 0;
  let queued = 0;
  const workers = Array.from(
    { length: Math.min(5, products.length) },
    async () => {
      while (next < products.length) {
        const product = products[next++];
        const result = await enqueueMerchantProductCatalogSync(product);
        if (result === "queued") queued += 1;
      }
    },
  );
  await Promise.all(workers);
  return queued;
}

export async function runWhatsAppCatalogReconciliationOnce(
  limit = 200,
): Promise<{ disabled: boolean; inspected: number; queued: number }> {
  const config = whatsappCatalogRuntimeConfig();
  if (
    !config.queueEnabled ||
    (config.environment === "production" && !config.syncEnabled)
  ) {
    return { disabled: true, inspected: 0, queued: 0 };
  }
  const stateRef = db.doc(RECONCILIATION_STATE_PATH);
  const state = await stateRef.get();
  const cursorPath = String(state.data()?.cursorPath ?? "").trim();
  let query = db
    .collectionGroup("products")
    .orderBy(FieldPath.documentId())
    .limit(Math.max(1, Math.min(500, limit)));
  if (cursorPath) query = query.startAfter(db.doc(cursorPath));
  const snapshot = await query.get();
  const identities = snapshot.docs
    .map((doc) => productIdentity(doc.ref.path))
    .filter(
      (item): item is { merchantId: string; productId: string } =>
        item !== null,
    )
    .filter(
      (item) =>
        !config.syncEnabled ||
        whatsappCatalogMerchantAllowed(config, item.merchantId),
    );
  const queued = await enqueueWithConcurrency(identities);
  const last = snapshot.docs[snapshot.docs.length - 1];
  const cycleComplete = snapshot.empty || snapshot.size < limit;
  await stateRef.set(
    {
      cursorPath: cycleComplete ? null : last.ref.path,
      lastInspected: snapshot.size,
      lastQueued: queued,
      ...(cycleComplete
        ? { cycleCompletedAt: FieldValue.serverTimestamp() }
        : {}),
      updatedAt: FieldValue.serverTimestamp(),
      updatedAtMs: Date.now(),
      schemaVersion: 1,
    },
    { merge: true },
  );
  return { disabled: false, inspected: snapshot.size, queued };
}

/** Safety net for missed triggers; product writes still enqueue immediately. */
export const reconcileWhatsAppMerchantCatalog = functions
  .runWith({ timeoutSeconds: 240, memory: "512MB", maxInstances: 1 })
  .pubsub.schedule("every 24 hours")
  .timeZone("Africa/Johannesburg")
  .onRun(() => runWhatsAppCatalogReconciliationOnce());
