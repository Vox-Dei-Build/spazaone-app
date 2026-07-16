// functions/src/triggers/onSaleCancelledNotify.ts
import { db, functions } from "../config/main";
import * as admin from "firebase-admin";
import { readStoreNotificationTokens } from "../notifications/storeNotificationTokens";

/**
 * getMerchantFcmTokens
 * Fetches all unique FCM tokens for a merchant from:
 *  - users/{merchantId}.fcmTokens: string[]
 *  - users/{merchantId}/devices/* where { active: true, fcmToken: string }
 *
 * Notes:
 *  - Duplicates are removed.
 *  - Empty/invalid tokens are filtered out.
 *  - Safe to call on hot paths; consider caching upstream if needed.
 *
 * @param {string} merchantId Firestore user/merchant document ID.
 * @return {Promise<string[]>} Array of unique, non-empty FCM tokens.
 */
export async function getMerchantFcmTokens(
  merchantId: string,
): Promise<string[]> {
  return readStoreNotificationTokens(merchantId);
}

/**
 * onSaleCancelledNotify
 * Firestore trigger: when a sale transitions to "cancelled",
 * send a push notification to the merchant's devices.
 *
 * Path: users/{merchantId}/sales/{saleId}
 * Event: onUpdate
 *
 * Detects transition by comparing previous vs current status/paymentStatus.
 * Sends an FCM multicast with a small notification and data payload:
 *  - eventType: "ORDER_CANCELLED"
 *  - merchantId, orderId, customerId, amount
 *
 * Idempotence: Only fires when the status *changes to* cancelled.
 *
 * @param {functions.Change<functions.firestore.DocumentSnapshot>} change Firestore change object
 * @param {functions.EventContext} context Event context (params: merchantId, saleId)
 * @returns {Promise<void>}
 */
export const onSaleCancelledNotify = functions.firestore
  .document("users/{merchantId}/sales/{saleId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const prev = String(
      before.status || before.paymentStatus || "",
    ).toLowerCase();
    const curr = String(
      after.status || after.paymentStatus || "",
    ).toLowerCase();

    // only when it actually becomes "cancelled"
    if (prev === "cancelled" || curr !== "cancelled") return;

    const merchantId = context.params.merchantId as string;
    const saleId = context.params.saleId as string;

    // optional: fetch customer display name
    let customerName = "";
    try {
      const cid = String(after.customerId || "");
      if (cid) {
        const cs = await db
          .collection("users")
          .doc(merchantId)
          .collection("customers")
          .doc(cid)
          .get();
        customerName = (cs.get("name") ||
          cs.get("displayName") ||
          "") as string;
      }
    } catch (e: any) {
      console.warn(
        "[onSaleCancelledNotify] push notify failed:",
        e?.message || e,
      );
    }

    const tokens = await getMerchantFcmTokens(merchantId);
    if (!tokens.length) {
      console.warn(`[push] No FCM tokens for merchant ${merchantId}`);
      return;
    }

    const title = "Order cancelled";
    const body = `Order #${saleId}${customerName ? ` by ${customerName}` : ""}`;

    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: {
        eventType: "ORDER_CANCELLED",
        merchantId,
        orderId: saleId,
        amount: String(after.amount ?? after.total ?? 0),
        customerId: String(after.customerId ?? ""),
      },
    });
  });
