import { createHash } from "crypto";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { functions, db } from "../config/main";
import {
  assertCallableStoreAccess,
  requireStoreId,
} from "../stores/storeAccess";

const MAX_CAMPAIGN_CREDIT_OPERATION = 100_000;
const OPERATION_ID_PATTERN = /^[A-Za-z0-9:_-]{1,180}$/;

export type CampaignWalletContext = {
  storeId: string;
  walletStoreId: string;
  shared: boolean;
};

type CampaignCreditOperation = {
  id: string;
  kind:
    | "client-message"
    | "payment-request-reservation"
    | "payment-request-settlement"
    | "payment-request-release"
    | "payment-request-recovery"
    | "promotion-reservation"
    | "promotion-send"
    | "promotion-refund"
    | "promotion-settlement"
    | "promotion-recovery"
    | "paystack-topup"
    | "admin-adjustment"
    | "sales-transfer"
    | "legacy-wallet-sync";
  initiatedBy?: string;
  metadata?: Record<string, unknown>;
};

type MutationResult = {
  balance: number;
  deduped: boolean;
};

export type CampaignReservation = {
  id: string;
  walletContext: CampaignWalletContext;
  amount: number;
};

function amount(value: unknown): number {
  const parsed = Number(value);
  if (
    !Number.isFinite(parsed) ||
    parsed <= 0 ||
    parsed > MAX_CAMPAIGN_CREDIT_OPERATION
  ) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Enter a valid campaign credit amount.",
    );
  }
  return Math.round(parsed * 100) / 100;
}

function operationId(value: unknown): string {
  const id = String(value ?? "").trim();
  if (!OPERATION_ID_PATTERN.test(id)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid operationId is required.",
    );
  }
  return id;
}

export function campaignWalletRef(walletStoreId: string) {
  return db.doc(`users/${walletStoreId}/wallet/current`);
}

export function campaignBalanceRef(walletStoreId: string) {
  return db.doc(`campaignWalletBalances/${walletStoreId}`);
}

export function campaignOperationRef(walletStoreId: string, id: string) {
  return db.doc(
    `campaignWalletOperations/${walletStoreId}/entries/${operationId(id)}`,
  );
}

/**
 * Resolves the authoritative campaign-credit wallet for a store.
 *
 * Stores without explicit enrollment retain their existing wallet path.
 * Once enrolled, both the selected store and the canonical store must carry
 * matching metadata. A broken pointer fails closed instead of charging a
 * different merchant or silently falling back to an isolated balance.
 */
export async function resolveCampaignWallet(
  storeIdValue: unknown,
): Promise<CampaignWalletContext> {
  const storeId = requireStoreId(storeIdValue);
  const store = await db.doc(`stores/${storeId}`).get();
  const storeData = store.data() ?? {};

  if (!store.exists || storeData.sharedCampaignCreditsEnabled !== true) {
    return { storeId, walletStoreId: storeId, shared: false };
  }

  const walletStoreId = requireStoreId(storeData.campaignWalletStoreId);
  const canonicalStore = await db.doc(`stores/${walletStoreId}`).get();
  const canonical = canonicalStore.data() ?? {};
  if (
    !canonicalStore.exists ||
    canonical.sharedCampaignCreditsEnabled !== true ||
    String(canonical.campaignWalletStoreId ?? "") !== walletStoreId ||
    String(canonical.ownerUid ?? "") !== String(storeData.ownerUid ?? "")
  ) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Shared campaign credits are temporarily unavailable for this store.",
    );
  }

  return { storeId, walletStoreId, shared: true };
}

export async function isSharedCampaignCreditsEnrollmentAllowed(
  ownerUid: string,
): Promise<boolean> {
  const control = await db
    .doc("releaseControls/sharedCampaignCredits")
    .get();
  const data = control.data() ?? {};
  const ownerAllowlist = Array.isArray(data.ownerUids)
    ? data.ownerUids.map((value: unknown) => String(value))
    : [];
  return (
    control.exists &&
    data.enabled === true &&
    ownerAllowlist.includes(ownerUid)
  );
}

export function campaignWalletContextFromCharge(
  storeIdValue: unknown,
  walletStoreIdValue: unknown,
  shared: boolean,
): CampaignWalletContext {
  return {
    storeId: requireStoreId(storeIdValue),
    walletStoreId: requireStoreId(walletStoreIdValue),
    shared,
  };
}

/**
 * Applies an idempotent debit or credit inside the caller's transaction.
 * The legacy users/{owner}/wallet/current document remains authoritative so
 * released app versions still work. Shared clients read the balance-only
 * projection, which prevents secondary-store operators from seeing sales or
 * payout fields belonging to the canonical store.
 */
export async function mutateCampaignCredits(
  tx: FirebaseFirestore.Transaction,
  context: CampaignWalletContext,
  deltaValue: number,
  operation: CampaignCreditOperation,
): Promise<MutationResult> {
  const delta = Math.round(Number(deltaValue) * 100) / 100;
  if (
    !Number.isFinite(delta) ||
    delta === 0 ||
    Math.abs(delta) > MAX_CAMPAIGN_CREDIT_OPERATION
  ) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Enter a valid campaign credit amount.",
    );
  }

  const walletRef = campaignWalletRef(context.walletStoreId);
  const entryRef = campaignOperationRef(context.walletStoreId, operation.id);
  const [wallet, existingEntry] = await Promise.all([
    tx.get(walletRef),
    tx.get(entryRef),
  ]);

  const currentBalance = Number(wallet.data()?.virtualBalance ?? 0);
  if (!Number.isFinite(currentBalance)) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Campaign credit balance is invalid. Contact support.",
    );
  }

  if (existingEntry.exists) {
    const existing = existingEntry.data() ?? {};
    if (
      Number(existing.delta) !== delta ||
      String(existing.storeId ?? "") !== context.storeId
    ) {
      throw new functions.https.HttpsError(
        "already-exists",
        "That campaign credit operation was already used.",
      );
    }
    return {
      balance: Number(existing.balanceAfter ?? currentBalance),
      deduped: true,
    };
  }

  const nextBalance = Math.round((currentBalance + delta) * 100) / 100;
  if (nextBalance < 0) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "INSUFFICIENT_CAMPAIGN_CREDITS",
    );
  }

  const now = FieldValue.serverTimestamp();
  tx.set(
    walletRef,
    {
      virtualBalance: nextBalance,
      campaignCreditsUpdatedAt: now,
    },
    { merge: true },
  );
  if (context.shared) {
    tx.set(
      campaignBalanceRef(context.walletStoreId),
      {
        walletStoreId: context.walletStoreId,
        balance: nextBalance,
        shared: true,
        sourceStoreId: context.storeId,
        updatedAt: now,
      },
      { merge: true },
    );
  }
  tx.create(entryRef, {
    operationId: operation.id,
    kind: operation.kind,
    storeId: context.storeId,
    walletStoreId: context.walletStoreId,
    shared: context.shared,
    delta,
    balanceBefore: currentBalance,
    balanceAfter: nextBalance,
    initiatedBy: operation.initiatedBy ?? null,
    metadata: operation.metadata ?? {},
    createdAt: now,
  });

  return { balance: nextBalance, deduped: false };
}

function reservationRef(walletStoreId: string, reservationId: string) {
  void walletStoreId;
  return db.doc(`campaignWalletReservations/${operationId(reservationId)}`);
}

/**
 * Reserves a campaign's server-calculated worst-case cost before the first
 * provider call. Competing stores therefore serialize against the same
 * canonical balance and can never both spend funds that only exist once.
 */
export async function reserveCampaignCredits(
  walletContext: CampaignWalletContext,
  promotionId: string,
  requestedAmount: number,
  initiatedBy?: string,
): Promise<CampaignReservation | null> {
  const reservationAmount = Math.round(requestedAmount * 100) / 100;
  if (reservationAmount <= 0) return null;
  amount(reservationAmount);
  // One reservation per saved promotion. A callable retry or a second device
  // cannot reserve and send the same campaign twice.
  const id = `promo_${createHash("sha256")
    .update(promotionId)
    .digest("hex")}`;
  const ref = reservationRef(walletContext.walletStoreId, id);
  await db.runTransaction(async (tx) => {
    const existingReservation = await tx.get(ref);
    if (existingReservation.exists) {
      throw new functions.https.HttpsError(
        "already-exists",
        "This campaign is already running or has already been sent.",
      );
    }
    await mutateCampaignCredits(tx, walletContext, -reservationAmount, {
      id: `reserve:${id}`,
      kind: "promotion-reservation",
      initiatedBy,
      metadata: { promotionId },
    });
    tx.create(ref, {
      reservationId: id,
      promotionId,
      storeId: walletContext.storeId,
      walletStoreId: walletContext.walletStoreId,
      shared: walletContext.shared,
      amount: reservationAmount,
      spent: 0,
      status: "active",
      expiresAt: Timestamp.fromMillis(Date.now() + 15 * 60 * 1000),
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { id, walletContext, amount: reservationAmount };
}

export async function recordCampaignReservationSpend(
  tx: FirebaseFirestore.Transaction,
  reservation: CampaignReservation,
  costValue: number,
): Promise<void> {
  const cost = amount(costValue);
  const ref = reservationRef(
    reservation.walletContext.walletStoreId,
    reservation.id,
  );
  const snapshot = await tx.get(ref);
  const data = snapshot.data() ?? {};
  if (!snapshot.exists || data.status !== "active") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Campaign credit reservation is no longer active.",
    );
  }
  const reserved = Number(data.amount ?? 0);
  const spent = Number(data.spent ?? 0);
  const nextSpent = Math.round((spent + cost) * 100) / 100;
  if (
    !Number.isFinite(reserved) ||
    !Number.isFinite(spent) ||
    nextSpent > reserved
  ) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Campaign cost exceeded its reserved credits.",
    );
  }
  tx.update(ref, {
    spent: nextSpent,
    messageCount: FieldValue.increment(1),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

export async function settleCampaignReservation(
  reservation: CampaignReservation,
  recovery = false,
): Promise<void> {
  const ref = reservationRef(
    reservation.walletContext.walletStoreId,
    reservation.id,
  );
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const data = snapshot.data() ?? {};
    if (!snapshot.exists || data.status !== "active") return;
    const reserved = Number(data.amount ?? 0);
    const spent = Number(data.spent ?? 0);
    if (
      !Number.isFinite(reserved) ||
      !Number.isFinite(spent) ||
      spent < 0 ||
      spent > reserved
    ) {
      throw new Error(`Invalid campaign reservation ${reservation.id}`);
    }
    const refund = Math.round((reserved - spent) * 100) / 100;
    if (refund > 0) {
      await mutateCampaignCredits(tx, reservation.walletContext, refund, {
        id: `${recovery ? "recover" : "settle"}:${reservation.id}`,
        kind: recovery ? "promotion-recovery" : "promotion-settlement",
        metadata: {
          promotionId: data.promotionId,
          reserved,
          spent,
        },
      });
    }
    tx.update(ref, {
      status: recovery ? "recovered" : "settled",
      settledAt: FieldValue.serverTimestamp(),
      refunded: refund,
      expiresAt: FieldValue.delete(),
    });
  });
}

/**
 * Crash recovery for reservations left active past a function's maximum
 * runtime. Successfully recorded sends remain spent; only unused credit is
 * returned.
 */
export const recoverExpiredCampaignReservations = functions.pubsub
  .schedule("every 15 minutes")
  .onRun(async () => {
    const expired = await db
      .collection("campaignWalletReservations")
      .where("expiresAt", "<=", Timestamp.now())
      .limit(100)
      .get();
    for (const document of expired.docs) {
      const data = document.data();
      if (data.status !== "active") continue;
      try {
        await settleCampaignReservation(
          {
            id: document.id,
            amount: Number(data.amount ?? 0),
            walletContext: campaignWalletContextFromCharge(
              data.storeId,
              data.walletStoreId,
              data.shared === true,
            ),
          },
          true,
        );
      } catch (error) {
        console.error("Failed to recover campaign reservation", {
          reservationId: document.id,
          error,
        });
      }
    }
    return null;
  });

/**
 * Server-authorized debit used by the new app's one-off message flows.
 * Existing, non-enrolled stores are supported too, allowing the new app to
 * stop making client-side financial writes without changing old releases.
 */
export const debitCampaignCredits = functions.https.onCall(
  async (data, callableContext) => {
    if (!callableContext.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in is required.",
      );
    }
    const storeId = requireStoreId(data?.storeId ?? callableContext.auth.uid);
    await assertCallableStoreAccess(callableContext, storeId);
    const debitAmount = amount(data?.amount);
    const id = operationId(data?.operationId);
    const reason = String(data?.reason ?? "message")
      .trim()
      .slice(0, 80);
    const walletContext = await resolveCampaignWallet(storeId);

    const result = await db.runTransaction((tx) =>
      mutateCampaignCredits(tx, walletContext, -debitAmount, {
        id: `client:${id}`,
        kind: "client-message",
        initiatedBy: callableContext.auth?.uid,
        metadata: { reason },
      }),
    );
    return {
      success: true,
      balance: result.balance,
      deduped: result.deduped,
      shared: walletContext.shared,
    };
  },
);

/**
 * Moves store-specific sales proceeds into campaign credits. The debit always
 * remains on the selected store; only the campaign-credit side may be shared.
 */
export const transferSalesToCampaignCredits = functions.https.onCall(
  async (data, callableContext) => {
    if (!callableContext.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in is required.",
      );
    }
    const storeId = requireStoreId(data?.storeId ?? callableContext.auth.uid);
    await assertCallableStoreAccess(callableContext, storeId);
    const transferAmount = amount(data?.amount);
    const id = operationId(data?.operationId);
    const walletContext = await resolveCampaignWallet(storeId);
    const salesWalletRef = campaignWalletRef(storeId);

    const result = await db.runTransaction(async (tx) => {
      const salesWallet = await tx.get(salesWalletRef);
      const currentSales = Number(
        salesWallet.data()?.salesVirtualBalance ??
          salesWallet.data()?.cashAdvanceBalance ??
          0,
      );

      const mutation = await mutateCampaignCredits(
        tx,
        walletContext,
        transferAmount,
        {
          id: `transfer:${id}`,
          kind: "sales-transfer",
          initiatedBy: callableContext.auth?.uid,
          metadata: { sourceStoreId: storeId },
        },
      );
      if (mutation.deduped) return mutation;
      if (!Number.isFinite(currentSales) || currentSales < transferAmount) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "INSUFFICIENT_SALES_BALANCE",
        );
      }
      tx.update(salesWalletRef, {
        salesVirtualBalance:
          Math.round((currentSales - transferAmount) * 100) / 100,
        salesBalanceUpdatedAt: FieldValue.serverTimestamp(),
      });
      return mutation;
    });

    return {
      success: true,
      balance: result.balance,
      deduped: result.deduped,
      shared: walletContext.shared,
    };
  },
);

/**
 * Keeps the balance-only projection current when a released app writes the
 * canonical legacy wallet directly. The transaction rereads the latest wallet
 * value, so out-of-order trigger delivery cannot roll the projection backward.
 */
export const syncCampaignCreditProjection = functions.firestore
  .document("users/{walletStoreId}/wallet/current")
  .onWrite(async (change, triggerContext) => {
    const before = Number(change.before.data()?.virtualBalance ?? 0);
    const after = Number(change.after.data()?.virtualBalance ?? 0);
    if (before === after || !change.after.exists) return;

    let walletContext: CampaignWalletContext;
    try {
      walletContext = await resolveCampaignWallet(
        triggerContext.params.walletStoreId,
      );
    } catch (error) {
      console.error("Campaign credit projection metadata is invalid", error);
      return;
    }
    if (
      !walletContext.shared ||
      walletContext.walletStoreId !== walletContext.storeId
    ) {
      return;
    }

    await db.runTransaction(async (tx) => {
      const walletRef = campaignWalletRef(walletContext.walletStoreId);
      const balanceRef = campaignBalanceRef(walletContext.walletStoreId);
      const [wallet, projection] = await Promise.all([
        tx.get(walletRef),
        tx.get(balanceRef),
      ]);
      const current = Number(wallet.data()?.virtualBalance ?? 0);
      const projected = Number(projection.data()?.balance ?? 0);
      if (!Number.isFinite(current) || current === projected) return;

      tx.set(
        balanceRef,
        {
          walletStoreId: walletContext.walletStoreId,
          balance: current,
          shared: true,
          sourceStoreId: walletContext.storeId,
          projectionSource: "legacy-wallet-write",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      const eventId = String(triggerContext.eventId ?? "")
        .replace(/[^A-Za-z0-9_-]/g, "_")
        .slice(0, 150);
      if (eventId) {
        tx.set(
          campaignOperationRef(
            walletContext.walletStoreId,
            `legacy-sync:${eventId}`,
          ),
          {
            operationId: `legacy-sync:${eventId}`,
            kind: "legacy-wallet-sync",
            storeId: walletContext.storeId,
            walletStoreId: walletContext.walletStoreId,
            shared: true,
            delta: Math.round((current - projected) * 100) / 100,
            balanceBefore: projected,
            balanceAfter: current,
            createdAt: FieldValue.serverTimestamp(),
          },
          { merge: false },
        );
      }
    });
  });
