import { FieldValue } from "firebase-admin/firestore";
import { db } from "../config/main";

function addTokens(target: Set<string>, data: FirebaseFirestore.DocumentData) {
  const scalar = data.fcmToken;
  if (typeof scalar === "string" && scalar.trim()) target.add(scalar.trim());
  if (Array.isArray(data.fcmTokens)) {
    for (const value of data.fcmTokens) {
      if (typeof value === "string" && value.trim()) target.add(value.trim());
    }
  }
}

/**
 * V2 stores source device tokens only from active operator memberships.
 * Legacy stores keep using users/{storeId} until their metadata is adopted.
 */
export async function readStoreNotificationTokens(
  storeId: string,
): Promise<string[]> {
  const store = await db.doc(`stores/${storeId}`).get();
  const tokens = new Set<string>();
  if (store.exists) {
    const members = await db
      .collection(`stores/${storeId}/operators`)
      .where("status", "==", "active")
      .get();
    members.docs.forEach((member) => addTokens(tokens, member.data()));
    return [...tokens];
  }

  const user = await db.doc(`users/${storeId}`).get();
  if (user.exists) addTokens(tokens, user.data() ?? {});
  const devices = await db
    .collection(`users/${storeId}/devices`)
    .where("active", "==", true)
    .get();
  devices.docs.forEach((device) => addTokens(tokens, device.data()));
  return [...tokens];
}

export async function removeInvalidStoreNotificationTokens(
  storeId: string,
  invalidTokens: string[],
): Promise<void> {
  const unique = [...new Set(invalidTokens.filter(Boolean))];
  if (unique.length === 0) return;
  const store = await db.doc(`stores/${storeId}`).get();
  if (!store.exists) {
    const legacy = await db.doc(`users/${storeId}`).get();
    const scalar = legacy.data()?.fcmToken;
    await legacy.ref.set(
      {
        fcmTokens: FieldValue.arrayRemove(...unique),
        ...(typeof scalar === "string" && unique.includes(scalar)
          ? { fcmToken: FieldValue.delete() }
          : {}),
      },
      { merge: true },
    );
    return;
  }

  const members = await db.collection(`stores/${storeId}/operators`).get();
  const batch = db.batch();
  for (const member of members.docs) {
    const scalar = member.data().fcmToken;
    batch.set(
      member.ref,
      {
        fcmTokens: FieldValue.arrayRemove(...unique),
        ...(typeof scalar === "string" && unique.includes(scalar)
          ? { fcmToken: FieldValue.delete() }
          : {}),
      },
      { merge: true },
    );
  }
  await batch.commit();
}
