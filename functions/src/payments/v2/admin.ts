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
const SETTLEMENT_VERIFICATION_AUTHORIZATION_TTL_MS = 24 * 60 * 60 * 1000;
const SETTLEMENT_VERIFICATION_AUTHORIZATION_ATTEMPTS = 2;

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

/**
 * Opens one short, bounded settlement-verification window after an admin has
 * reviewed the merchant. New accounts cannot use Paystack's billable bank
 * validation endpoint merely by creating a store or installing the app.
 */
export const authorizeMerchantSettlementVerificationV2 = functions.https.onCall(
  async (data, context) => {
    const adminUid = requireAdmin(context);
    const merchantId = requireMerchantId(data?.merchantId);
    const operationId = requireOperationId(data?.operationId);
    const authorized = data?.authorized;
    if (typeof authorized !== "boolean") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Choose whether settlement verification is authorized.",
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

    const profileRef = db.doc(`merchantPaymentProfiles/${merchantId}`);
    const auditId = stableDocumentId("audit", [
      "settlement_verification_authorization",
      adminUid,
      operationId,
    ]);
    const auditRef = db.doc(`paymentAdministrationAudit/${auditId}`);
    const expiresAtMs = authorized
      ? Date.now() + SETTLEMENT_VERIFICATION_AUTHORIZATION_TTL_MS
      : 0;
    let resultingExpiresAtMs = expiresAtMs;
    let deduped = false;

    await db.runTransaction(async (tx) => {
      const existingAudit = await tx.get(auditRef);
      if (existingAudit.exists) {
        const previous = existingAudit.data() ?? {};
        if (
          String(previous.merchantId) !== merchantId ||
          previous.authorized !== authorized ||
          String(previous.reason) !== reason
        ) {
          throw new functions.https.HttpsError(
            "already-exists",
            "That operationId is already bound to another authorization.",
          );
        }
        resultingExpiresAtMs = Number(previous.expiresAtMs ?? 0);
        deduped = true;
        return;
      }

      const now = FieldValue.serverTimestamp();
      tx.set(
        profileRef,
        {
          merchantId,
          settlementVerificationAuthorization: {
            state: authorized ? "authorized" : "revoked",
            expiresAtMs,
            remainingAttempts: authorized
              ? SETTLEMENT_VERIFICATION_AUTHORIZATION_ATTEMPTS
              : 0,
            authorizedBy: adminUid,
            authorizedAt: now,
            operationId,
          },
          schemaVersion: 2,
          updatedAt: now,
          updatedBy: adminUid,
        },
        { merge: true },
      );
      tx.create(auditRef, {
        auditId,
        action: authorized
          ? "settlement_verification_authorized"
          : "settlement_verification_revoked",
        merchantId,
        actorUid: adminUid,
        operationId,
        authorized,
        expiresAtMs,
        maximumAttempts: authorized
          ? SETTLEMENT_VERIFICATION_AUTHORIZATION_ATTEMPTS
          : 0,
        reason,
        createdAt: now,
        schemaVersion: 2,
      });
    });

    return {
      merchantId,
      authorized,
      expiresAtMs: resultingExpiresAtMs,
      maximumAttempts: authorized
        ? SETTLEMENT_VERIFICATION_AUTHORIZATION_ATTEMPTS
        : 0,
      deduped,
    };
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
    const requestedSettlementVerificationSuspended =
      typeof data?.settlementVerificationSuspended === "boolean"
        ? data.settlementVerificationSuspended
        : undefined;
    const configRef = db.doc("paymentConfiguration/global");
    let resultingSettlementVerificationSuspended = false;
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
      const settlementVerificationSuspended =
        requestedSettlementVerificationSuspended ??
        previous.settlementVerificationSuspended === true;
      resultingSettlementVerificationSuspended =
        settlementVerificationSuspended;
      tx.set(
        configRef,
        {
          capabilities,
          emergencySuspended,
          settlementVerificationSuspended,
          ...(requestedSettlementVerificationSuspended === false
            ? {
                settlementVerificationSuspendedReason: FieldValue.delete(),
                settlementVerificationSuspendedAt: FieldValue.delete(),
              }
            : {}),
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
        previousSettlementVerificationSuspended:
          previous.settlementVerificationSuspended === true,
        nextSettlementVerificationSuspended: settlementVerificationSuspended,
        reason,
        createdAt: now,
      });
    });
    return {
      capabilities,
      emergencySuspended,
      settlementVerificationSuspended: resultingSettlementVerificationSuspended,
    };
  },
);
