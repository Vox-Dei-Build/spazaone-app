/**
 * @function heartbeatMerchantApp
 * @description Merchants call this on app launch to report (version, build, platform).
 *              Server stores the latest values and timestamp for per-merchant gating.
 * @param {Object} data
 * @param {string} data.merchantId
 * @param {string} data.appVersion   - semantic version, e.g. "1.14.3"
 * @param {number} data.buildNumber  - monotonically increasing build
 * @param {"android"|"ios"} data.platform
 * @param {string=} data.commitSha   - immutable source commit from CI
 * @returns {Promise<{ok:true, ts:number}>}
 */

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { assertStoreAccess } from "../stores/storeAccess";

async function assertCallerIsMerchantAdmin(uid: string, merchantId: string) {
  await assertStoreAccess(uid, merchantId);
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
    const commitSha = String(data?.commitSha ?? "")
      .trim()
      .toLowerCase();
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
    if (commitSha && !/^[a-f0-9]{40}$/.test(commitSha)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Invalid build provenance.",
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
        ...(commitSha ? { appCommitSha: commitSha } : {}),
        lastHeartbeatAt: now,
      },
      { merge: true },
    );

    // 6) Return ms epoch for client logging
    const serverNow = Timestamp.now().toMillis();
    return { ok: true, ts: serverNow };
  },
);
