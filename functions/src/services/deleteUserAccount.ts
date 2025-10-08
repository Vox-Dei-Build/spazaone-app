import * as admin from "firebase-admin";
import { getStorage } from "firebase-admin/storage";
import type { Bucket, File } from "@google-cloud/storage";
import { functions, db } from "../config/main";

const BATCH_DELETE_LIMIT = 300;
const RECENT_LOGIN_MAX_AGE_SECONDS = 5 * 60;

type QueryCallback = (
  doc: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>,
) => void;

function resolveBucket(): Bucket | null {
  try {
    return getStorage().bucket();
  } catch (error) {
    console.warn("Storage bucket not configured, skipping object cleanup.", error);
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

    const storagePaths = new Set<string>();

    await deleteCollectionWhere("messagingTemplates", "userId", uid, (doc) => {
      const data = doc.data();
      const url = data?.channels?.whatsapp?.mediaUrl as string | undefined;
      const path = extractStoragePath(url);
      if (path) storagePaths.add(path);
    });

    await deleteCollectionWhere("promotions", "merchantId", uid);
    await deleteCollectionWhere("payoutRequests", "merchantId", uid);
    await deleteCollectionWhere("paymentReferences", "merchantId", uid);

    const notificationsRef = db.collection("notifications").doc(uid);
    if ((await notificationsRef.get()).exists) {
      await admin.firestore().recursiveDelete(notificationsRef);
    }

    const userRef = db.collection("users").doc(uid);
    if ((await userRef.get()).exists) {
      await admin.firestore().recursiveDelete(userRef);
    }

    const bucket = resolveBucket();
    if (bucket) {
      await deleteStoragePrefix(bucket, `products/${uid}/`);
      await deleteStoragePrefix(bucket, `profile_images/${uid}/`);
      await deleteStoragePrefix(bucket, `whatsapp_media/${uid}/`);
      await deleteStoragePrefix(bucket, `users/${uid}/`);
      await deleteSpecificFiles(bucket, Array.from(storagePaths));
    }

    await admin.auth().deleteUser(uid);

    return { success: true };
  });

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

async function deleteStoragePrefix(bucket: Bucket, prefix: string): Promise<void> {
  if (!prefix) return;
  const [files] = await bucket.getFiles({ prefix });
  await deleteStorageFiles(files);
}

async function deleteSpecificFiles(bucket: Bucket, paths: string[]): Promise<void> {
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
