/**
 * @function heartbeatMerchantApp
 * @description Merchants call this on app launch to report (version, build, platform).
 *              Server stores the latest values and timestamp for per-merchant gating.
 * @param {Object} data
 * @param {string} data.merchantId
 * @param {string} data.appVersion   - semantic version, e.g. "1.14.3"
 * @param {number} data.buildNumber  - monotonically increasing build
 * @param {"android"|"ios"} data.platform
 * @returns {Promise<{ok:true, ts:number}>}
 */

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db, functions } from "../config/main";

async function assertCallerIsMerchantAdmin(uid: string, merchantId: string) {
  // Project model: merchants are stored under users/{merchantId}.
  // Authorization: the caller must be the same user as the merchantId.
  if (uid !== merchantId) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Not authorized for this merchant.",
    );
  }
  return true;
}

export const heartbeatMerchantApp = functions.https.onCall(
  async (data, context) => {
    // 1) Auth required
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in required.",
      );
    }

    // 2) (Optional) Enforce App Check if you’ve enabled it in console
    // if (!context.app) {
    //   throw new functions.https.HttpsError("failed-precondition", "App Check required.");
    // }

    // 3) Validate input
    const { merchantId, appVersion, buildNumber, platform } = data || {};
    if (
      !merchantId ||
      typeof appVersion !== "string" ||
      typeof buildNumber !== "number" ||
      !["android", "ios"].includes(platform)
    ) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Missing/invalid fields.",
      );
    }

    // 4) Authorization check
    await assertCallerIsMerchantAdmin(context.auth.uid, merchantId);

    // 5) Persist heartbeat
    const now = FieldValue.serverTimestamp();
    await db.doc(`users/${merchantId}`).set(
      {
        appVersion,
        buildNumber,
        platform,
        lastHeartbeatAt: now,
      },
      { merge: true },
    );

    // 6) Return ms epoch for client logging
    const serverNow = Timestamp.now().toMillis();
    return { ok: true, ts: serverNow };
  },
);
