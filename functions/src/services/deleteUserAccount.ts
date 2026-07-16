import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import type { Bucket, File } from "@google-cloud/storage";
import { createHash } from "crypto";
import { functions, db } from "../config/main";
import { formatPhoneNumber } from "../utils/phoneUtils";

const BATCH_DELETE_LIMIT = 300;
const RECENT_LOGIN_MAX_AGE_SECONDS = 5 * 60;

type QueryCallback = (
  doc: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>,
) => void;

function resolveBucket(): Bucket | null {
  try {
    return getStorage().bucket();
  } catch (error) {
    console.warn(
      "Storage bucket not configured, skipping object cleanup.",
      error,
    );
    return null;
  }
}

/**
 * HTTPS callable that permanently deletes a merchant account across Auth,
 * Firestore, and Cloud Storage. This is a destructive operation designed for
 * user-initiated account deletion inside the app, not automated cleanup.
 *
 * Safety considerations:
 * - Caller must be authenticated with a recently refreshed ID token
 *   (enforced via auth_time threshold).
 * - Firestore data is removed using batched paging plus recursiveDelete for
 *   nested subcollections to avoid orphaned documents.
 * - Storage objects are deleted via known prefixes and any explicit media URLs
 *   referenced by messaging templates before they are removed.
 * - Finally the Firebase Auth user is deleted so future sign-ins fail until
 *   the merchant registers again.
 */
export const deleteUserAccount = functions
  .runWith({ timeoutSeconds: 540, memory: "1GB" })
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication is required to delete an account.",
      );
    }

    const { uid, token } = context.auth;
    const authTimeSeconds = Number(token?.auth_time ?? 0);
    const nowSeconds = Math.floor(Date.now() / 1000);
    if (
      !authTimeSeconds ||
      nowSeconds - authTimeSeconds > RECENT_LOGIN_MAX_AGE_SECONDS
    ) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "RECENT_LOGIN_REQUIRED",
      );
    }

    const memberships = await db
      .collection("operators")
      .doc(uid)
      .collection("stores")
      .get();
    const ownedStoreIds = new Set(
      memberships.docs
        .filter(
          (doc) =>
            doc.data().role === "owner" && doc.data().status !== "disabled",
        )
        .map((doc) => doc.id),
    );
    const ownedStoreMetadata = await db
      .collection("stores")
      .where("ownerUid", "==", uid)
      .get();
    ownedStoreMetadata.docs.forEach((store) => ownedStoreIds.add(store.id));

    // A legacy account may not have adopted its membership metadata yet.
    const legacyUser = await db.doc(`users/${uid}`).get();
    const legacyStore = await db.doc(`stores/${uid}`).get();
    if (
      legacyUser.exists &&
      (!legacyStore.exists || legacyStore.data()?.ownerUid === uid)
    ) {
      ownedStoreIds.add(uid);
    }

    // Do all ownership checks before the first destructive write. Deleting an
    // owner while another active operator depends on the store would orphan
    // access and make recovery much harder than a deliberate transfer flow.
    for (const storeId of ownedStoreIds) {
      const activeOperators = await db
        .collection(`stores/${storeId}/operators`)
        .where("status", "==", "active")
        .get();
      if (activeOperators.docs.some((member) => member.id !== uid)) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "STORE_HAS_OTHER_OPERATORS: Remove all other operators before deleting this account.",
        );
      }
    }

    const storagePaths = new Set<string>();
    for (const storeId of ownedStoreIds) {
      await deleteCollectionWhere(
        "messagingTemplates",
        "userId",
        storeId,
        (doc) => {
          const data = doc.data();
          const url = data?.channels?.whatsapp?.mediaUrl as string | undefined;
          const path = extractStoragePath(url);
          if (path) storagePaths.add(path);
        },
      );
      await deleteCollectionWhere("promotions", "merchantId", storeId);
      await deleteCollectionWhere("payoutRequests", "merchantId", storeId);
      await deleteCollectionWhere("paymentReferences", "merchantId", storeId);

      for (const root of ["notifications", "users"] as const) {
        const ref = db.collection(root).doc(storeId);
        if ((await ref.get()).exists) {
          await admin.firestore().recursiveDelete(ref);
        }
      }
      await deleteStoreMetadata(storeId);
    }

    // Operator-only memberships are revoked without touching the stores.
    for (const membership of memberships.docs) {
      if (!ownedStoreIds.has(membership.id)) {
        const storeMembershipRef = db.doc(
          `stores/${membership.id}/operators/${uid}`,
        );
        const storeMembership = await storeMembershipRef.get();
        const tokenData = storeMembership.data() ?? membership.data();
        const tokenList = Array.isArray(tokenData.fcmTokens)
          ? tokenData.fcmTokens
          : [];
        const tokens = [tokenData.fcmToken, ...tokenList]
          .filter((value): value is string => typeof value === "string")
          .map((value) => value.trim())
          .filter(Boolean);
        const batch = db.batch();
        batch.delete(membership.ref);
        batch.delete(storeMembershipRef);
        if (tokens.length) {
          const legacyStoreRef = db.doc(`users/${membership.id}`);
          const legacyStore = await legacyStoreRef.get();
          const legacyScalar = String(legacyStore.data()?.fcmToken ?? "");
          batch.set(
            legacyStoreRef,
            {
              fcmTokens: FieldValue.arrayRemove(...tokens),
              ...(tokens.includes(legacyScalar)
                ? { fcmToken: FieldValue.delete() }
                : {}),
            },
            { merge: true },
          );
        }
        await batch.commit();
      }
    }

    const operatorRef = db.doc(`operators/${uid}`);
    if ((await operatorRef.get()).exists) {
      await admin.firestore().recursiveDelete(operatorRef);
    }

    const authUser = await admin.auth().getUser(uid);
    const phone = formatPhoneNumber(authUser.phoneNumber ?? "");
    if (phone) {
      for (const root of ["operatorPhoneLookup", "operatorInvites"] as const) {
        const ref = db.doc(`${root}/${hashPhone(phone)}`);
        if ((await ref.get()).exists) {
          await admin.firestore().recursiveDelete(ref);
        }
      }
    }

    const bucket = resolveBucket();
    if (bucket) {
      for (const storeId of ownedStoreIds) {
        await deleteStoragePrefix(bucket, `products/${storeId}/`);
        await deleteStoragePrefix(bucket, `profile_images/${storeId}/`);
        await deleteStoragePrefix(bucket, `whatsapp_media/${storeId}/`);
        await deleteStoragePrefix(bucket, `users/${storeId}/`);
      }
      await deleteSpecificFiles(bucket, Array.from(storagePaths));
    }

    await admin.auth().deleteUser(uid);

    return { success: true };
  });

function hashPhone(phone: string): string {
  return createHash("sha256").update(phone).digest("hex");
}

async function deleteStoreMetadata(storeId: string): Promise<void> {
  const storeRef = db.doc(`stores/${storeId}`);
  const members = await storeRef.collection("operators").get();
  for (const member of members.docs) {
    await db.doc(`operators/${member.id}/stores/${storeId}`).delete();
  }
  if ((await storeRef.get()).exists) {
    await admin.firestore().recursiveDelete(storeRef);
  }
}

async function deleteCollectionWhere(
  collectionPath: string,
  field: string,
  value: string,
  each?: QueryCallback,
): Promise<number> {
  let totalDeleted = 0;
  let hasMore = true;

  while (hasMore) {
    const snapshot = await db
      .collection(collectionPath)
      .where(field, "==", value)
      .limit(BATCH_DELETE_LIMIT)
      .get();

    if (snapshot.empty) {
      break;
    }

    const batch = db.batch();
    snapshot.docs.forEach((doc) => {
      each?.(doc);
      batch.delete(doc.ref);
    });

    await batch.commit();
    totalDeleted += snapshot.size;

    hasMore = snapshot.size >= BATCH_DELETE_LIMIT;
  }

  return totalDeleted;
}

async function deleteStoragePrefix(
  bucket: Bucket,
  prefix: string,
): Promise<void> {
  if (!prefix) return;
  const [files] = await bucket.getFiles({ prefix });
  await deleteStorageFiles(files);
}

async function deleteSpecificFiles(
  bucket: Bucket,
  paths: string[],
): Promise<void> {
  if (!paths.length) return;
  const files = paths.map((p) => bucket.file(p));
  await deleteStorageFiles(files);
}

async function deleteStorageFiles(files: File[]): Promise<void> {
  const chunkSize = 25;
  for (let i = 0; i < files.length; i += chunkSize) {
    const chunk = files.slice(i, i + chunkSize);
    await Promise.all(
      chunk.map((file) =>
        file
          .delete()
          .then(() => null)
          .catch((error: Error) => {
            console.error(
              `Failed to delete storage object ${file.name}:`,
              error.message,
            );
          }),
      ),
    );
  }
}

function extractStoragePath(url?: string): string | null {
  if (!url) return null;
  try {
    const marker = "/o/";
    const markerIndex = url.indexOf(marker);
    if (markerIndex === -1) return null;
    const pathAndParams = url.substring(markerIndex + marker.length);
    const [encodedPath] = pathAndParams.split("?");
    return decodeURIComponent(encodedPath);
  } catch (error) {
    console.warn("Unable to extract storage path from URL", url, error);
    return null;
  }
}
