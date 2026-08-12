import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import {
  mutateCampaignCredits,
  resolveCampaignWallet,
} from "../../wallet/campaignCredits";
import {
  isPaymentPurpose,
  MERCHANT_PAYMENT_STATUSES,
  MerchantPaymentStatus,
  PaymentPurpose,
  stableDocumentId,
} from "./domain";

function requireAdmin(context: functions.https.CallableContext): string {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign in is required.",
    );
  }
  if (context.auth.token.spazaAdmin !== true) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Spaza One payment administration access is required.",
    );
  }
  return context.auth.uid;
}

function requireMerchantId(value: unknown): string {
  const id = String(value ?? "").trim();
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(id)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid merchantId is required.",
    );
  }
  return id;
}

const MAX_ADMIN_ADJUSTMENT_MINOR = 10_000_000;

export function requireAdminAdjustmentMinor(value: unknown): number {
  const amount = Number(value);
  if (
    !Number.isSafeInteger(amount) ||
    amount === 0 ||
    Math.abs(amount) > MAX_ADMIN_ADJUSTMENT_MINOR
  ) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Enter a valid Campaign Credit adjustment in cents.",
    );
  }
  return amount;
}

function requireOperationId(value: unknown): string {
  const id = String(value ?? "").trim();
  if (!/^[A-Za-z0-9:_-]{1,120}$/.test(id)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid operationId is required.",
    );
  }
  return id;
}

/**
 * Audited support-only correction for Campaign Credits.
 *
 * This is intentionally the only manual top-up replacement. The public app
 * never calls it; Paystack purchases are credited automatically from signed,
 * idempotent provider events.
 */
export const adjustCampaignCreditsV2 = functions.https.onCall(
  async (data, context) => {
    const adminUid = requireAdmin(context);
    const merchantId = requireMerchantId(data?.merchantId);
    const amountMinor = requireAdminAdjustmentMinor(data?.amountMinor);
    const operationId = requireOperationId(data?.operationId);
    const reason = String(data?.reason ?? "")
      .trim()
      .slice(0, 500);
    if (!reason) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "An audit reason is required.",
      );
    }

    const walletContext = await resolveCampaignWallet(merchantId);
    const adjustmentId = stableDocumentId("credit_adjustment", [
      adminUid,
      operationId,
    ]);
    const auditRef = db.doc(`paymentAdministrationAudit/${adjustmentId}`);
    let balance = 0;
    let deduped = false;

    await db.runTransaction(async (tx) => {
      const existing = await tx.get(auditRef);
      if (existing.exists) {
        const previous = existing.data() ?? {};
        if (
          String(previous.merchantId) !== merchantId ||
          Number(previous.amountMinor) !== amountMinor ||
          String(previous.reason) !== reason
        ) {
          throw new functions.https.HttpsError(
            "already-exists",
            "That operationId is already bound to another adjustment.",
          );
        }
        balance = Number(previous.balanceAfter ?? 0);
        deduped = true;
        return;
      }

      const result = await mutateCampaignCredits(
        tx,
        walletContext,
        amountMinor / 100,
        {
          id: `admin:${adjustmentId}`,
          kind: "admin-adjustment",
          initiatedBy: adminUid,
          metadata: { reason, operationId },
        },
      );
      balance = result.balance;
      deduped = result.deduped;
      tx.create(auditRef, {
        adjustmentId,
        action: "campaign_credit_adjustment",
        merchantId,
        walletStoreId: walletContext.walletStoreId,
        adminUid,
        operationId,
        amountMinor,
        balanceAfter: balance,
        reason,
        schemaVersion: 2,
        createdAt: FieldValue.serverTimestamp(),
      });
    });

    return { adjustmentId, merchantId, amountMinor, balance, deduped };
  },
);

export const setMerchantPaymentState = functions.https.onCall(
  async (data, context) => {
    const adminUid = requireAdmin(context);
    const merchantId = requireMerchantId(data?.merchantId);
    const status = String(data?.status ?? "") as MerchantPaymentStatus;
    if (!MERCHANT_PAYMENT_STATUSES.includes(status)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid merchant payment status is required.",
      );
    }
    const reason = String(data?.reason ?? "")
      .trim()
      .slice(0, 500);
    if (!reason) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "An audit reason is required.",
      );
    }
    const requestedCapabilities = Array.isArray(data?.capabilities)
      ? data.capabilities.filter(isPaymentPurpose)
      : [];
    const capabilities = Object.fromEntries(
      requestedCapabilities.map((purpose: PaymentPurpose) => [purpose, true]),
    );
    const profileRef = db.doc(`merchantPaymentProfiles/${merchantId}`);
    const auditId = stableDocumentId("audit", [
      merchantId,
      adminUid,
      status,
      reason,
      String(Date.now()),
    ]);
    const auditRef = profileRef.collection("audit").doc(auditId);
    await db.runTransaction(async (tx) => {
      const current = await tx.get(profileRef);
      const currentData = current.data() ?? {};
      const previousStatus = String(currentData.status ?? "not_started");
      const settlementCapabilities = new Set<PaymentPurpose>([
        "merchant_order",
        "supplier_order",
        "account_settlement",
        "repayment_installment",
      ]);
      if (
        status === "enabled" &&
        requestedCapabilities.some((purpose: PaymentPurpose) =>
          settlementCapabilities.has(purpose),
        ) &&
        (currentData.bankVerificationStatus !== "approved" ||
          !/^ACCT_[A-Za-z0-9]+$/.test(
            String(currentData.paystackSubaccountCode ?? ""),
          ))
      ) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Approve the verified Paystack settlement account before enabling collections.",
        );
      }
      tx.set(
        profileRef,
        {
          merchantId,
          status,
          capabilities,
          schemaVersion: 2,
          updatedAt: FieldValue.serverTimestamp(),
          updatedBy: adminUid,
        },
        { merge: true },
      );
      tx.create(auditRef, {
        auditId,
        merchantId,
        actorUid: adminUid,
        previousStatus,
        nextStatus: status,
        capabilities,
        reason,
        createdAt: FieldValue.serverTimestamp(),
      });
    });
    return { merchantId, status, capabilities };
  },
);

export const setGlobalPaymentConfigurationV2 = functions.https.onCall(
  async (data, context) => {
    const adminUid = requireAdmin(context);
    const reason = String(data?.reason ?? "")
      .trim()
      .slice(0, 500);
    if (!reason) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "An audit reason is required.",
      );
    }
    const requestedCapabilities = Array.isArray(data?.capabilities)
      ? data.capabilities.filter(isPaymentPurpose)
      : [];
    const capabilities = Object.fromEntries(
      requestedCapabilities.map((purpose: PaymentPurpose) => [purpose, true]),
    );
    const emergencySuspended = data?.emergencySuspended === true;
    const configRef = db.doc("paymentConfiguration/global");
    const auditId = stableDocumentId("audit", [
      "global",
      adminUid,
      emergencySuspended ? "suspended" : "configured",
      reason,
      String(Date.now()),
    ]);
    await db.runTransaction(async (tx) => {
      const current = await tx.get(configRef);
      const previous = current.data() ?? {};
      const now = FieldValue.serverTimestamp();
      tx.set(
        configRef,
        {
          capabilities,
          emergencySuspended,
          schemaVersion: 2,
          updatedAt: now,
          updatedBy: adminUid,
        },
        { merge: true },
      );
      tx.create(configRef.collection("audit").doc(auditId), {
        auditId,
        actorUid: adminUid,
        action: emergencySuspended
          ? "global_emergency_suspend"
          : "global_capabilities_configured",
        previousCapabilities: previous.capabilities ?? {},
        nextCapabilities: capabilities,
        previousEmergencySuspended: previous.emergencySuspended === true,
        nextEmergencySuspended: emergencySuspended,
        reason,
        createdAt: now,
      });
    });
    return { capabilities, emergencySuspended };
  },
);
