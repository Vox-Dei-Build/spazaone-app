import { db, functions } from "../config/main";
import * as admin from "firebase-admin";
import { MulticastMessage } from "firebase-admin/messaging";

const ADD_CUSTOMER_ROUTE = "/addContactPage";
const MAX_CUSTOMERS_FOR_NUDGE = 3;
const MAX_NUDGES_PER_MERCHANT = 3;
const MIN_DAYS_BETWEEN_NUDGES = 5;

type NudgeState = {
  addCustomer?: {
    count?: number;
    lastSentAt?: FirebaseFirestore.Timestamp;
  };
};

/**
 * Nudges merchants who have not yet built a useful customer list.
 *
 * The notification is intentionally capped: a merchant receives at most three
 * add-customer nudges, separated by at least five days, and stops qualifying
 * once they have three saved customers.
 */
export const nudgeMerchantsToAddCustomers = functions.pubsub
  .schedule("every 24 hours")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    const usersSnap = await db.collection("users").get();
    let sentCount = 0;
    let skippedCount = 0;

    for (const userDoc of usersSnap.docs) {
      const merchantId = userDoc.id;
      const userData = userDoc.data() || {};
      const tokens = readMerchantTokens(userData);

      if (!tokens.length) {
        skippedCount++;
        continue;
      }

      const customerCount = await countCustomersForNudge(merchantId);
      if (customerCount >= MAX_CUSTOMERS_FOR_NUDGE) {
        skippedCount++;
        continue;
      }

      const nudgeState = (userData.notificationNudges || {}) as NudgeState;
      if (!shouldSendAddCustomerNudge(nudgeState)) {
        skippedCount++;
        continue;
      }

      const copy = addCustomerNudgeCopy(customerCount);
      const message: MulticastMessage = {
        tokens,
        notification: copy,
        android: {
          priority: "normal",
          notification: {
            channelId: "default_channel",
            sound: "default",
          },
        },
        data: {
          type: "ADD_CUSTOMER_NUDGE",
          route: ADD_CUSTOMER_ROUTE,
          customerCount: String(customerCount),
          source: "nudgeMerchantsToAddCustomers",
        },
      };

      try {
        const response = await admin.messaging().sendEachForMulticast(message);
        const badTokens = response.responses
          .map((result, index) => ({ result, token: tokens[index] }))
          .filter(({ result }) =>
            String(result.error?.code || "").includes(
              "registration-token-not-registered",
            ),
          )
          .map(({ token }) => token);

        if (badTokens.length) {
          await removeBadTokens(userDoc.ref, userData, badTokens);
        }

        if (response.successCount > 0) {
          await markAddCustomerNudgeSent(userDoc.ref, nudgeState);
          sentCount++;
        }
      } catch (error) {
        console.error(
          `[nudgeMerchantsToAddCustomers] failed for ${merchantId}:`,
          error,
        );
      }
    }

    console.log(
      `[nudgeMerchantsToAddCustomers] sent=${sentCount} skipped=${skippedCount}`,
    );
  });

/**
 * Reads all known FCM tokens from the merchant user document.
 *
 * @param {FirebaseFirestore.DocumentData} data User document data.
 * @returns {string[]} Unique non-empty FCM tokens.
 */
function readMerchantTokens(data: FirebaseFirestore.DocumentData): string[] {
  const tokens = new Set<string>();
  if (Array.isArray(data.fcmTokens)) {
    for (const token of data.fcmTokens) {
      if (token) tokens.add(String(token));
    }
  }
  if (data.fcmToken) tokens.add(String(data.fcmToken));
  return [...tokens];
}

/**
 * Counts up to the nudge threshold. We only need to know whether the merchant
 * has 0, 1, 2 or 3+ customers, so this avoids scanning large customer lists.
 *
 * @param {string} merchantId Merchant user id.
 * @returns {Promise<number>} Count capped at MAX_CUSTOMERS_FOR_NUDGE.
 */
async function countCustomersForNudge(merchantId: string): Promise<number> {
  const snap = await db
    .collection("users")
    .doc(merchantId)
    .collection("customers")
    .limit(MAX_CUSTOMERS_FOR_NUDGE)
    .get();
  return snap.size;
}

/**
 * Decides whether the add-customer nudge is allowed for this merchant.
 *
 * @param {NudgeState} state Existing notification nudge state.
 * @returns {boolean} True when the nudge can be sent.
 */
function shouldSendAddCustomerNudge(state: NudgeState): boolean {
  const addCustomer = state.addCustomer || {};
  const count = addCustomer.count || 0;
  if (count >= MAX_NUDGES_PER_MERCHANT) return false;

  const lastSentAt = addCustomer.lastSentAt;
  if (!lastSentAt) return true;

  const lastSentMs = lastSentAt.toMillis();
  const minGapMs = MIN_DAYS_BETWEEN_NUDGES * 24 * 60 * 60 * 1000;
  return Date.now() - lastSentMs >= minGapMs;
}

/**
 * Writes the nudge cap state after at least one device accepted the push.
 *
 * @param {FirebaseFirestore.DocumentReference} userRef Merchant user ref.
 * @param {NudgeState} state Existing notification nudge state.
 * @returns {Promise<void>}
 */
async function markAddCustomerNudgeSent(
  userRef: FirebaseFirestore.DocumentReference,
  state: NudgeState,
): Promise<void> {
  const currentCount = state.addCustomer?.count || 0;
  await userRef.set(
    {
      notificationNudges: {
        addCustomer: {
          count: currentCount + 1,
          lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      },
    },
    { merge: true },
  );
}

/**
 * Removes rejected FCM tokens from both legacy and array token fields.
 *
 * @param {FirebaseFirestore.DocumentReference} userRef Merchant user ref.
 * @param {FirebaseFirestore.DocumentData} userData Existing user data.
 * @param {string[]} badTokens Tokens rejected by FCM as unregistered.
 * @returns {Promise<void>}
 */
async function removeBadTokens(
  userRef: FirebaseFirestore.DocumentReference,
  userData: FirebaseFirestore.DocumentData,
  badTokens: string[],
): Promise<void> {
  const update: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
    fcmTokens: admin.firestore.FieldValue.arrayRemove(...badTokens),
  };

  if (userData.fcmToken && badTokens.includes(String(userData.fcmToken))) {
    update.fcmToken = admin.firestore.FieldValue.delete();
  }

  await userRef.set(update, { merge: true });
}

/**
 * Returns push copy based on current customer-list progress.
 *
 * @param {number} customerCount Number of saved customers, capped below 3.
 * @returns {{title: string; body: string}} Notification copy.
 */
function addCustomerNudgeCopy(customerCount: number): {
  title: string;
  body: string;
} {
  if (customerCount === 0) {
    return {
      title: "Add your first customer",
      body: "Start with one regular so SpazaOne can track tabs, reminders and orders.",
    };
  }

  return {
    title: "Add a few regular customers",
    body: "The more customers you add, the easier it is to track who owes, paid and ordered.",
  };
}
