import * as admin from "firebase-admin";
import { createHash } from "crypto";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { functions, db } from "../config/main";
import { formatPhoneNumber } from "../utils/phoneUtils";
import {
  assertCallableStoreAccess,
  parseStoreRole,
  requireStoreId,
  StoreRole,
} from "./storeAccess";
import { isSharedCampaignCreditsEnrollmentAllowed } from "../wallet/campaignCredits";

const INVITE_TTL_DAYS = 7;
const MAX_STORES_PER_OPERATOR = 25;

type MembershipWrite = {
  storeId: string;
  uid: string;
  role: StoreRole;
  storeName: string;
  displayName: string;
  phoneLast4: string;
  phoneHash?: string;
  fcmTokens?: string[];
  campaignWalletStoreId?: string;
  sharedCampaignCredits?: boolean;
  source: "legacy-adoption" | "direct-invite" | "claimed-invite" | "created";
};

type MembershipWriter = {
  set(
    documentRef: FirebaseFirestore.DocumentReference,
    data: FirebaseFirestore.DocumentData,
    options: FirebaseFirestore.SetOptions,
  ): unknown;
};

function requireAuth(context: functions.https.CallableContext) {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign in is required.",
    );
  }
  return context.auth;
}

function cleanName(value: unknown, field: string): string {
  const name = String(value ?? "")
    .trim()
    .replace(/\s+/g, " ");
  if (name.length < 2 || name.length > 80) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `${field} must be between 2 and 80 characters.`,
    );
  }
  return name;
}

function phoneHash(phone: string): string {
  return createHash("sha256").update(phone).digest("hex");
}

function phoneLast4(phone: string | undefined): string {
  return phone?.replace(/\D/g, "").slice(-4) ?? "";
}

function setMembership(
  batch: MembershipWriter,
  value: MembershipWrite,
): void {
  const now = FieldValue.serverTimestamp();
  const fcmTokens = [...new Set(value.fcmTokens ?? [])];
  const shared = {
    storeId: value.storeId,
    uid: value.uid,
    role: value.role,
    status: "active",
    displayName: value.displayName,
    phoneLast4: value.phoneLast4,
    joinedAt: now,
    updatedAt: now,
    source: value.source,
    schemaVersion: 2,
    ...(fcmTokens.length
      ? {
          fcmToken: fcmTokens[0],
          fcmTokens,
          notificationUpdatedAt: now,
        }
      : {}),
  };
  batch.set(db.doc(`stores/${value.storeId}/operators/${value.uid}`), shared, {
    merge: true,
  });
  batch.set(
    db.doc(`operators/${value.uid}/stores/${value.storeId}`),
    { ...shared, storeName: value.storeName },
    { merge: true },
  );
  if (value.phoneHash) {
    batch.set(
      db.doc(`operatorPhoneLookup/${value.phoneHash}/stores/${value.storeId}`),
      {
        storeId: value.storeId,
        uid: value.uid,
        role: value.role,
        status: "active",
        storeName: value.storeName,
        updatedAt: now,
      },
      { merge: true },
    );
  }
  if (value.sharedCampaignCredits && value.campaignWalletStoreId) {
    batch.set(
      db.doc(
        `campaignWalletAccess/${value.campaignWalletStoreId}/members/${value.uid}`,
      ),
      {
        uid: value.uid,
        walletStoreId: value.campaignWalletStoreId,
        storeIds: FieldValue.arrayUnion(value.storeId),
        updatedAt: now,
      },
      { merge: true },
    );
  }
}

async function loadMemberships(uid: string) {
  const snapshot = await db
    .collection("operators")
    .doc(uid)
    .collection("stores")
    .where("status", "==", "active")
    .get();

  const storeSnapshots = snapshot.empty
    ? []
    : await db.getAll(
        ...snapshot.docs.map((doc) => db.doc(`stores/${doc.id}`)),
      );
  const storesById = new Map(
    storeSnapshots.map((store) => [store.id, store.data() ?? {}]),
  );

  return snapshot.docs
    .map((doc) => {
      const data = doc.data();
      const store = storesById.get(doc.id) ?? {};
      const configuredWalletStoreId = String(
        store.campaignWalletStoreId ?? "",
      ).trim();
      const sharedCampaignCredits =
        store.sharedCampaignCreditsEnabled === true &&
        /^[A-Za-z0-9_-]{1,128}$/.test(configuredWalletStoreId);
      return {
        storeId: doc.id,
        storeName: String(data.storeName ?? "Store"),
        role: String(data.role ?? "operator"),
        campaignWalletStoreId: sharedCampaignCredits
          ? configuredWalletStoreId
          : doc.id,
        sharedCampaignCredits,
      };
    })
    .sort((a, b) => a.storeName.localeCompare(b.storeName));
}

async function adoptLegacyOwner(
  uid: string,
  displayName: string,
  phone: string,
): Promise<boolean> {
  const userRef = db.doc(`users/${uid}`);
  const storeRef = db.doc(`stores/${uid}`);
  const [legacy, store] = await Promise.all([userRef.get(), storeRef.get()]);
  if (!legacy.exists || store.exists) return false;

  const data = legacy.data() ?? {};
  const legacyTokens = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
  const storeName = String(data.shopName ?? data.name ?? "My Store").trim();
  const batch = db.batch();
  batch.set(storeRef, {
    name: storeName,
    ownerUid: uid,
    status: "active",
    legacyUserPath: `users/${uid}`,
    schemaVersion: 2,
    migratedAt: FieldValue.serverTimestamp(),
    migrationSource: "legacy-owner-v1",
  });
  setMembership(batch, {
    storeId: uid,
    uid,
    role: "owner",
    storeName,
    displayName: displayName || String(data.name ?? "Owner"),
    phoneLast4: phoneLast4(phone || String(data.mobileNumber ?? "")),
    phoneHash: phone ? phoneHash(phone) : undefined,
    fcmTokens: [data.fcmToken, ...legacyTokens]
      .filter((token): token is string => typeof token === "string")
      .map((token) => token.trim())
      .filter(Boolean),
    source: "legacy-adoption",
  });
  await batch.commit();
  return true;
}

async function claimPendingInvites(
  uid: string,
  displayName: string,
  phone: string,
): Promise<number> {
  if (!phone) return 0;
  const inviteCollection = db
    .collection("operatorInvites")
    .doc(phoneHash(phone))
    .collection("stores");
  const invites = await inviteCollection.where("status", "==", "pending").get();
  const valid = invites.docs.filter((doc) => {
    const expiresAt = doc.data().expiresAt as Timestamp | undefined;
    return !expiresAt || expiresAt.toMillis() > Date.now();
  });
  if (valid.length === 0) return 0;

  const existingMemberships = await loadMemberships(uid);
  const remainingCapacity = Math.max(
    0,
    MAX_STORES_PER_OPERATOR - existingMemberships.length,
  );
  if (remainingCapacity === 0) return 0;
  const claimable = valid.slice(0, remainingCapacity);
  const stores = await db.getAll(
    ...claimable.map((invite) => db.doc(`stores/${invite.id}`)),
  );
  const storesById = new Map(
    stores.map((store) => [store.id, store.data() ?? {}]),
  );

  const batch = db.batch();
  for (const invite of claimable) {
    const data = invite.data();
    const storeId = requireStoreId(invite.id);
    const store = storesById.get(storeId) ?? {};
    const campaignWalletStoreId = String(
      store.campaignWalletStoreId ?? "",
    ).trim();
    const sharedCampaignCredits =
      store.sharedCampaignCreditsEnabled === true &&
      /^[A-Za-z0-9_-]{1,128}$/.test(campaignWalletStoreId);
    setMembership(batch, {
      storeId,
      uid,
      role: data.role === "admin" ? "admin" : "operator",
      storeName: String(data.storeName ?? "Store"),
      displayName,
      phoneLast4: phoneLast4(phone),
      phoneHash: phoneHash(phone),
      campaignWalletStoreId: sharedCampaignCredits
        ? campaignWalletStoreId
        : undefined,
      sharedCampaignCredits,
      source: "claimed-invite",
    });
    batch.set(
      invite.ref,
      {
        status: "claimed",
        claimedBy: uid,
        claimedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    batch.set(
      db.doc(`stores/${storeId}/invites/${phoneHash(phone)}`),
      {
        status: "claimed",
        claimedBy: uid,
        claimedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  await batch.commit();
  return claimable.length;
}

/**
 * Initializes store access after authentication. The operation is idempotent:
 * legacy owners are adopted once and phone-based invitations are claimed once.
 */
export const bootstrapStoreAccess = functions.https.onCall(
  async (_data, context) => {
    const auth = requireAuth(context);
    const displayName = String(auth.token.name ?? "Operator").trim();
    const phone = formatPhoneNumber(String(auth.token.phone_number ?? ""));

    const existing = await loadMemberships(auth.uid);
    let adoptedLegacyStore = false;
    if (existing.length === 0) {
      adoptedLegacyStore = await adoptLegacyOwner(auth.uid, displayName, phone);
    }
    const claimedInvites = await claimPendingInvites(
      auth.uid,
      displayName,
      phone,
    );

    return {
      stores: await loadMemberships(auth.uid),
      adoptedLegacyStore,
      claimedInvites,
      sharedCampaignCreditsEnrollmentAllowed:
        await isSharedCampaignCreditsEnrollmentAllowed(auth.uid),
    };
  },
);

export const createStore = functions.https.onCall(async (data, context) => {
  const auth = requireAuth(context);
  if (auth.token.firebase?.sign_in_provider === "anonymous") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Register your account before creating another store.",
    );
  }
  const existing = await loadMemberships(auth.uid);
  if (existing.length >= MAX_STORES_PER_OPERATOR) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      "This account has reached the store limit.",
    );
  }

  const storeName = cleanName(data?.name, "Store name");
  const operatorName = cleanName(
    data?.operatorName ?? auth.token.name ?? "Owner",
    "Operator name",
  );
  const supportsSharedCampaignCredits =
    data?.campaignCreditsMode === "shared-v1" ||
    typeof data?.shareCampaignCredits === "boolean";
  const phone = formatPhoneNumber(String(auth.token.phone_number ?? ""));
  const storeRef = db.collection("stores").doc();
  const storeId = storeRef.id;
  const now = FieldValue.serverTimestamp();
  const ownedStores = existing.filter(
    (membership) => membership.role === "owner",
  );

  // A user's first owned store remains isolated. Every additional store they
  // own must share the same campaign/top-up wallet. This is a server
  // invariant, not a Remote Config enrollment choice: otherwise an old flag
  // value can silently create an empty secondary wallet and block sends.
  if (ownedStores.length > 0 && !supportsSharedCampaignCredits) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Update SpazaOne before adding another store.",
    );
  }

  const sharedOwnedStores = ownedStores.filter(
    (membership) => membership.sharedCampaignCredits,
  );
  const unsharedOwnedStores = ownedStores.filter(
    (membership) => !membership.sharedCampaignCredits,
  );
  const sharedWalletIds = new Set(
    sharedOwnedStores.map((membership) => membership.campaignWalletStoreId),
  );
  if (
    sharedWalletIds.size > 1 ||
    (sharedOwnedStores.length > 0 && unsharedOwnedStores.length > 0) ||
    (sharedOwnedStores.length === 0 && unsharedOwnedStores.length > 1)
  ) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Existing stores need a one-time campaign credit migration before another store can be added.",
    );
  }

  const canonicalMembership =
    sharedOwnedStores[0] ?? unsharedOwnedStores[0];
  const sharedCampaignCredits = canonicalMembership != null;
  const campaignWalletStoreId = sharedCampaignCredits
    ? canonicalMembership.campaignWalletStoreId
    : storeId;

  await db.runTransaction(async (transaction) => {
    let campaignBalance = 0;
    if (sharedCampaignCredits) {
      const [canonicalStore, canonicalWallet] = await Promise.all([
        transaction.get(db.doc(`stores/${campaignWalletStoreId}`)),
        transaction.get(
          db.doc(`users/${campaignWalletStoreId}/wallet/current`),
        ),
      ]);
      if (
        !canonicalStore.exists ||
        String(canonicalStore.data()?.ownerUid ?? "") !== auth.uid ||
        !canonicalWallet.exists
      ) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "The existing campaign credit wallet is unavailable.",
        );
      }
      const configuredWalletStoreId = String(
        canonicalStore.data()?.campaignWalletStoreId ?? campaignWalletStoreId,
      );
      if (
        canonicalStore.data()?.sharedCampaignCreditsEnabled === true &&
        configuredWalletStoreId !== campaignWalletStoreId
      ) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Existing campaign credit wallet configuration is inconsistent.",
        );
      }
      campaignBalance = Number(
        canonicalWallet.data()?.virtualBalance ?? 0,
      );
      if (!Number.isFinite(campaignBalance) || campaignBalance < 0) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "The existing campaign credit balance is invalid.",
        );
      }
    }

    transaction.set(storeRef, {
      name: storeName,
      ownerUid: auth.uid,
      status: "active",
      legacyUserPath: `users/${storeId}`,
      schemaVersion: 2,
      createdAt: now,
      ...(sharedCampaignCredits
        ? {
            sharedCampaignCreditsEnabled: true,
            campaignWalletStoreId,
            sharedCampaignCreditsEnrolledAt: now,
            sharedCampaignCreditsSource: "automatic-store-creation",
          }
        : {}),
    });
    if (sharedCampaignCredits) {
      transaction.set(
        db.doc(`stores/${campaignWalletStoreId}`),
        {
          sharedCampaignCreditsEnabled: true,
          campaignWalletStoreId,
          sharedCampaignCreditsEnrolledAt: now,
          sharedCampaignCreditsSource: "automatic-store-creation",
        },
        { merge: true },
      );
      transaction.set(
        db.doc(`campaignWalletBalances/${campaignWalletStoreId}`),
        {
          walletStoreId: campaignWalletStoreId,
          balance: campaignBalance,
          shared: true,
          sourceStoreId: storeId,
          updatedAt: now,
        },
        { merge: true },
      );
    }
    transaction.set(db.doc(`users/${storeId}`), {
      name: operatorName,
      shopName: storeName,
      mobileNumber: phone,
      mobileNumberNormalized: phone,
      ownerUid: auth.uid,
      multiStoreSchemaVersion: 2,
      referralCount: 0,
      createdAt: now,
    });
    transaction.set(db.doc(`users/${storeId}/wallet/current`), {
      // The signup credit belongs to an account, not every store it creates.
      virtualBalance: 0.0,
      cashAdvanceBalance: 0.0,
      salesVirtualBalance: 0.0,
      cashAdvanceWithdrawn: 0.0,
      cashAdvanceDueDate: null,
      penaltyFee: 0.0,
      accountSuspended: false,
      totalCashAdvanceGiven: 0.0,
      totalCashAdvanceRepaid: 0.0,
      repaymentHistory: [],
    });
    setMembership(transaction, {
      storeId,
      uid: auth.uid,
      role: "owner",
      storeName,
      displayName: operatorName,
      phoneLast4: phoneLast4(phone),
      phoneHash: phone ? phoneHash(phone) : undefined,
      campaignWalletStoreId: sharedCampaignCredits
        ? campaignWalletStoreId
        : undefined,
      sharedCampaignCredits,
      source: "created",
    });
  });
  return {
    storeId,
    storeName,
    role: "owner",
    campaignWalletStoreId,
    sharedCampaignCredits,
  };
});

export const inviteStoreOperator = functions.https.onCall(
  async (data, context) => {
    const auth = requireAuth(context);
    const storeId = requireStoreId(data?.storeId);
    await assertCallableStoreAccess(context, storeId, ["owner", "admin"]);
    const role = parseStoreRole(data?.role);
    const phone = formatPhoneNumber(String(data?.phone ?? ""));
    if (!phone) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Enter a valid South African mobile number.",
      );
    }
    if (phone === formatPhoneNumber(String(auth.token.phone_number ?? ""))) {
      throw new functions.https.HttpsError(
        "already-exists",
        "You already have access to this store.",
      );
    }

    const store = await db.doc(`stores/${storeId}`).get();
    const legacy = store.exists ? null : await db.doc(`users/${storeId}`).get();
    const storeName = String(
      store.data()?.name ?? legacy?.data()?.shopName ?? "Store",
    );
    const campaignWalletStoreId = String(
      store.data()?.campaignWalletStoreId ?? "",
    ).trim();
    const sharedCampaignCredits =
      store.data()?.sharedCampaignCreditsEnabled === true &&
      /^[A-Za-z0-9_-]{1,128}$/.test(campaignWalletStoreId);

    try {
      const target = await admin.auth().getUserByPhoneNumber(phone);
      const targetStores = await db
        .collection("operators")
        .doc(target.uid)
        .collection("stores")
        .where("status", "==", "active")
        .limit(MAX_STORES_PER_OPERATOR)
        .get();
      if (targetStores.size >= MAX_STORES_PER_OPERATOR) {
        throw new functions.https.HttpsError(
          "resource-exhausted",
          "That operator has reached the store limit.",
        );
      }
      const existing = await db
        .doc(`stores/${storeId}/operators/${target.uid}`)
        .get();
      if (existing.exists && existing.data()?.status === "active") {
        throw new functions.https.HttpsError(
          "already-exists",
          "That operator already has access.",
        );
      }
      const batch = db.batch();
      setMembership(batch, {
        storeId,
        uid: target.uid,
        role,
        storeName,
        displayName: target.displayName ?? "Operator",
        phoneLast4: phoneLast4(phone),
        phoneHash: phoneHash(phone),
        campaignWalletStoreId: sharedCampaignCredits
          ? campaignWalletStoreId
          : undefined,
        sharedCampaignCredits,
        source: "direct-invite",
      });
      batch.delete(
        db.doc(`operatorInvites/${phoneHash(phone)}/stores/${storeId}`),
      );
      batch.delete(db.doc(`stores/${storeId}/invites/${phoneHash(phone)}`));
      await batch.commit();
      return { status: "added", phoneLast4: phoneLast4(phone), role };
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      const code = (error as { code?: string }).code ?? "";
      if (code !== "auth/user-not-found") throw error;
    }

    const inviteRef = db.doc(
      `operatorInvites/${phoneHash(phone)}/stores/${storeId}`,
    );
    const inviteBatch = db.batch();
    inviteBatch.set(inviteRef, {
      storeId,
      storeName,
      role,
      status: "pending",
      phoneLast4: phoneLast4(phone),
      invitedBy: auth.uid,
      invitedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(
        Date.now() + INVITE_TTL_DAYS * 24 * 60 * 60 * 1000,
      ),
      schemaVersion: 2,
    });
    inviteBatch.set(db.doc(`stores/${storeId}/invites/${phoneHash(phone)}`), {
      inviteId: phoneHash(phone),
      phoneLast4: phoneLast4(phone),
      role,
      status: "pending",
      invitedBy: auth.uid,
      invitedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(
        Date.now() + INVITE_TTL_DAYS * 24 * 60 * 60 * 1000,
      ),
      schemaVersion: 2,
    });
    await inviteBatch.commit();
    return { status: "invited", phoneLast4: phoneLast4(phone), role };
  },
);

export const listStoreOperators = functions.https.onCall(
  async (data, context) => {
    const storeId = requireStoreId(data?.storeId);
    const access = await assertCallableStoreAccess(context, storeId);
    const operators = await db
      .collection("stores")
      .doc(storeId)
      .collection("operators")
      .where("status", "==", "active")
      .get();
    const invites =
      access.role === "owner" || access.role === "admin"
        ? await db
            .collection(`stores/${storeId}/invites`)
            .where("status", "==", "pending")
            .get()
        : null;
    return {
      canManage: access.role === "owner" || access.role === "admin",
      operators: operators.docs.map((doc) => ({
        uid: doc.id,
        displayName: String(doc.data().displayName ?? "Operator"),
        phoneLast4: String(doc.data().phoneLast4 ?? ""),
        role: String(doc.data().role ?? "operator"),
      })),
      pendingInvites:
        invites?.docs.map((doc) => ({
          inviteId: doc.id,
          phoneLast4: String(doc.data().phoneLast4 ?? ""),
          role: String(doc.data().role ?? "operator"),
          expiresAt: doc.data().expiresAt ?? null,
        })) ?? [],
    };
  },
);

export const cancelStoreOperatorInvite = functions.https.onCall(
  async (data, context) => {
    const storeId = requireStoreId(data?.storeId);
    await assertCallableStoreAccess(context, storeId, ["owner", "admin"]);
    const inviteId = String(data?.inviteId ?? "")
      .trim()
      .toLowerCase();
    if (!/^[a-f0-9]{64}$/.test(inviteId)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid invitation is required.",
      );
    }
    const batch = db.batch();
    batch.delete(db.doc(`operatorInvites/${inviteId}/stores/${storeId}`));
    batch.delete(db.doc(`stores/${storeId}/invites/${inviteId}`));
    await batch.commit();
    return { success: true };
  },
);

export const removeStoreOperator = functions.https.onCall(
  async (data, context) => {
    const auth = requireAuth(context);
    const storeId = requireStoreId(data?.storeId);
    await assertCallableStoreAccess(context, storeId, ["owner", "admin"]);
    const operatorUid = String(data?.operatorUid ?? "").trim();
    if (!operatorUid || operatorUid === auth.uid) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Select another operator to remove.",
      );
    }
    const [target, store] = await Promise.all([
      db.doc(`stores/${storeId}/operators/${operatorUid}`).get(),
      db.doc(`stores/${storeId}`).get(),
    ]);
    if (!target.exists) {
      throw new functions.https.HttpsError("not-found", "Operator not found.");
    }
    if (target.data()?.role === "owner") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Store ownership must be transferred before removing the owner.",
      );
    }
    const batch = db.batch();
    const targetData = target.data() ?? {};
    const targetTokenList = Array.isArray(targetData.fcmTokens)
      ? targetData.fcmTokens
      : [];
    const targetTokens = [targetData.fcmToken, ...targetTokenList]
      .filter((token): token is string => typeof token === "string")
      .map((token) => token.trim())
      .filter(Boolean);
    const disabled = {
      status: "disabled",
      disabledBy: auth.uid,
      disabledAt: FieldValue.serverTimestamp(),
    };
    batch.set(db.doc(`stores/${storeId}/operators/${operatorUid}`), disabled, {
      merge: true,
    });
    batch.set(db.doc(`operators/${operatorUid}/stores/${storeId}`), disabled, {
      merge: true,
    });
    const campaignWalletStoreId = String(
      store.data()?.campaignWalletStoreId ?? "",
    ).trim();
    if (
      store.data()?.sharedCampaignCreditsEnabled === true &&
      /^[A-Za-z0-9_-]{1,128}$/.test(campaignWalletStoreId)
    ) {
      batch.set(
        db.doc(
          `campaignWalletAccess/${campaignWalletStoreId}/members/${operatorUid}`,
        ),
        {
          storeIds: FieldValue.arrayRemove(storeId),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    if (targetTokens.length) {
      const legacyStore = db.doc(`users/${storeId}`);
      const legacyData = (await legacyStore.get()).data() ?? {};
      batch.set(
        legacyStore,
        {
          fcmTokens: FieldValue.arrayRemove(...targetTokens),
          ...(targetTokens.includes(String(legacyData.fcmToken ?? ""))
            ? { fcmToken: FieldValue.delete() }
            : {}),
        },
        { merge: true },
      );
    }
    try {
      const targetUser = await admin.auth().getUser(operatorUid);
      const targetPhone = formatPhoneNumber(targetUser.phoneNumber ?? "");
      if (targetPhone) {
        batch.delete(
          db.doc(
            `operatorPhoneLookup/${phoneHash(targetPhone)}/stores/${storeId}`,
          ),
        );
      }
    } catch (error) {
      // A deleted Auth user should not block revoking its Firestore access.
      console.warn("Unable to clear operator phone lookup", { operatorUid });
    }
    await batch.commit();
    return { success: true };
  },
);
