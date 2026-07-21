import { functions, db } from "../config/main";
import { verifyBotRequest } from "../security/requestAuth";

export const STORE_ROLES = ["owner", "admin", "operator"] as const;
export type StoreRole = (typeof STORE_ROLES)[number];

export type StoreAccess = {
  storeId: string;
  uid: string;
  role: StoreRole;
  legacyOwner: boolean;
};

const STORE_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

export function requireStoreId(value: unknown): string {
  const storeId = String(value ?? "").trim();
  if (!STORE_ID_PATTERN.test(storeId)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid storeId is required.",
    );
  }
  return storeId;
}

export function parseStoreRole(value: unknown): StoreRole {
  const role = String(value ?? "operator").trim();
  if (!STORE_ROLES.includes(role as StoreRole) || role === "owner") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Role must be admin or operator.",
    );
  }
  return role as StoreRole;
}

/**
 * Authorizes an authenticated operator against a store.
 *
 * The uid === storeId fallback preserves every released version of the app
 * while legacy owners are adopted into the v2 membership collections. It is
 * intentionally restricted to an existing users/{storeId} document, so an
 * attacker cannot invent a matching path and gain access.
 */
export async function assertStoreAccess(
  uid: string,
  storeIdValue: unknown,
  allowedRoles: readonly StoreRole[] = STORE_ROLES,
): Promise<StoreAccess> {
  const storeId = requireStoreId(storeIdValue);
  const membershipRef = db.doc(`stores/${storeId}/operators/${uid}`);
  const membership = await membershipRef.get();

  if (membership.exists) {
    const data = membership.data() ?? {};
    const role = data.role as StoreRole;
    if (
      data.status === "active" &&
      STORE_ROLES.includes(role) &&
      allowedRoles.includes(role)
    ) {
      return { storeId, uid, role, legacyOwner: false };
    }
  }

  if (uid === storeId && allowedRoles.includes("owner")) {
    const legacyStore = await db.doc(`users/${storeId}`).get();
    if (legacyStore.exists) {
      return { storeId, uid, role: "owner", legacyOwner: true };
    }
  }

  throw new functions.https.HttpsError(
    "permission-denied",
    "You do not have access to this store.",
  );
}

export async function assertCallableStoreAccess(
  context: functions.https.CallableContext,
  storeId: unknown,
  allowedRoles: readonly StoreRole[] = STORE_ROLES,
): Promise<StoreAccess> {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign in is required.",
    );
  }
  return assertStoreAccess(context.auth.uid, storeId, allowedRoles);
}

export async function authorizeCallableStoreOrBot(
  context: functions.https.CallableContext,
  storeId: unknown,
): Promise<boolean> {
  if (verifyBotRequest(context.rawRequest)) return true;
  if (!context.auth) return false;
  try {
    await assertStoreAccess(context.auth.uid, storeId);
    return true;
  } catch (error) {
    if (error instanceof functions.https.HttpsError) return false;
    throw error;
  }
}
