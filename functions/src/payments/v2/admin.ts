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
import {
  recordAcceptedCustomerPaymentRequest,
  releaseReviewedCustomerPaymentRequest,
} from "./customerPaymentRequests";
import { requirePaymentAdmin } from "./paymentAdminAuth";
import {
  SETTLEMENT_ADMIN_REQUEST_TYPE,
  settlementAdminRequestProjection,
  settlementAdminRequestRef,
} from "./settlementAdminRequests";

const paymentAdminMutationRuntime = functions.runWith({
  enforceAppCheck: true,
  consumeAppCheckToken: true,
});
const paymentAdminReadRuntime = functions.runWith({
  enforceAppCheck: true,
});

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

export type PaymentRequestReviewAction = "confirm_delivery" | "release_failed";

export function requirePaymentRequestReviewAction(
  value: unknown,
): PaymentRequestReviewAction {
  if (value !== "confirm_delivery" && value !== "release_failed") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Choose a valid payment-request review outcome.",
    );
  }
  return value;
}

function requireAuditText(
  value: unknown,
  label: string,
  maximumLength = 500,
): string {
  const parsed = String(value ?? "")
    .trim()
    .slice(0, maximumLength);
  if (!parsed) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `${label} is required.`,
    );
  }
  return parsed;
}

/**
 * Audited support-only correction for Campaign Credits.
 *
 * This is intentionally the only manual top-up replacement. The public app
 * never calls it; Paystack purchases are credited automatically from signed,
 * idempotent provider events.
 */
export const adjustCampaignCreditsV2 = paymentAdminMutationRuntime.https.onCall(
  async (data, context) => {
    const adminUid = requirePaymentAdmin(context);
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

export const setMerchantPaymentState = paymentAdminMutationRuntime.https.onCall(
  async (data, context) => {
    const adminUid = requirePaymentAdmin(context);
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
async function applySettlementVerificationAuthorization(input: {
  adminUid: string;
  merchantId: string;
  operationId: string;
  authorized: boolean;
  reason: string;
}): Promise<{
  authorized: boolean;
  expiresAtMs: number;
  maximumAttempts: number;
  deduped: boolean;
}> {
  const profileRef = db.doc(`merchantPaymentProfiles/${input.merchantId}`);
  const requestRef = settlementAdminRequestRef(input.merchantId);
  const auditId = stableDocumentId("audit", [
    "settlement_verification_authorization",
    input.adminUid,
    input.operationId,
  ]);
  const auditRef = db.doc(`paymentAdministrationAudit/${auditId}`);
  const expiresAtMs = input.authorized
    ? Date.now() + SETTLEMENT_VERIFICATION_AUTHORIZATION_TTL_MS
    : 0;
  let resultingExpiresAtMs = expiresAtMs;
  let deduped = false;

  await db.runTransaction(async (tx) => {
    const [existingAudit, request] = await Promise.all([
      tx.get(auditRef),
      tx.get(requestRef),
    ]);
    if (existingAudit.exists) {
      const previous = existingAudit.data() ?? {};
      if (
        String(previous.merchantId) !== input.merchantId ||
        previous.authorized !== input.authorized ||
        String(previous.reason) !== input.reason
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
    const requestData = request.data() ?? {};
    if (
      !request.exists ||
      requestData.type !== SETTLEMENT_ADMIN_REQUEST_TYPE ||
      requestData.merchantId !== input.merchantId
    ) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "A merchant settlement request is required before authorization.",
      );
    }
    const requestStatus = String(requestData.status ?? "");
    const allowedStatuses = input.authorized
      ? ["authorization_required", "revoked"]
      : ["authorization_required", "authorized"];
    if (!allowedStatuses.includes(requestStatus)) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "This settlement request is not in a state that allows that decision.",
      );
    }
    const bankingDetailsId = String(requestData.bankingDetailsId ?? "").trim();
    const bankingDetailsUpdatedAtMs = Number(
      requestData.bankingDetailsUpdatedAtMs ?? 0,
    );
    if (
      input.authorized &&
      (!/^[A-Za-z0-9_-]{1,200}$/.test(bankingDetailsId) ||
        !Number.isSafeInteger(bankingDetailsUpdatedAtMs) ||
        bankingDetailsUpdatedAtMs < 1)
    ) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "The settlement request is not bound to the current banking details.",
      );
    }

    const now = FieldValue.serverTimestamp();
    tx.set(
      profileRef,
      {
        merchantId: input.merchantId,
        settlementVerificationAuthorization: {
          state: input.authorized ? "authorized" : "revoked",
          expiresAtMs,
          remainingAttempts: input.authorized
            ? SETTLEMENT_VERIFICATION_AUTHORIZATION_ATTEMPTS
            : 0,
          authorizedBy: input.adminUid,
          authorizedAt: now,
          operationId: input.operationId,
          bankingDetailsId: input.authorized ? bankingDetailsId : "",
          bankingDetailsUpdatedAtMs: input.authorized
            ? bankingDetailsUpdatedAtMs
            : 0,
        },
        schemaVersion: 2,
        updatedAt: now,
        updatedBy: input.adminUid,
      },
      { merge: true },
    );
    tx.set(
      requestRef,
      {
        status: input.authorized ? "authorized" : "revoked",
        authorizationExpiresAtMs: expiresAtMs,
        updatedAt: now,
      },
      { merge: true },
    );
    tx.create(auditRef, {
      auditId,
      action: input.authorized
        ? "settlement_verification_authorized"
        : "settlement_verification_revoked",
      merchantId: input.merchantId,
      actorUid: input.adminUid,
      operationId: input.operationId,
      authorized: input.authorized,
      expiresAtMs,
      maximumAttempts: input.authorized
        ? SETTLEMENT_VERIFICATION_AUTHORIZATION_ATTEMPTS
        : 0,
      reason: input.reason,
      createdAt: now,
      schemaVersion: 2,
    });
  });

  return {
    authorized: input.authorized,
    expiresAtMs: resultingExpiresAtMs,
    maximumAttempts: input.authorized
      ? SETTLEMENT_VERIFICATION_AUTHORIZATION_ATTEMPTS
      : 0,
    deduped,
  };
}

function requireAuthorizationInput(data: unknown): {
  operationId: string;
  authorized: boolean;
  reason: string;
} {
  const value =
    data && typeof data === "object" ? (data as Record<string, unknown>) : {};
  const operationId = requireOperationId(value.operationId);
  if (typeof value.authorized !== "boolean") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Choose whether settlement verification is authorized.",
    );
  }
  return {
    operationId,
    authorized: value.authorized,
    reason: requireAuditText(value.reason, "An audit reason"),
  };
}

export const authorizeMerchantSettlementVerificationV2 =
  paymentAdminMutationRuntime.https.onCall(async (data, context) => {
    const adminUid = requirePaymentAdmin(context);
    const merchantId = requireMerchantId(data?.merchantId);
    const authorization = requireAuthorizationInput(data);
    return {
      merchantId,
      ...(await applySettlementVerificationAuthorization({
        adminUid,
        merchantId,
        ...authorization,
      })),
    };
  });

export const authorizeSettlementVerificationRequestV1 =
  paymentAdminMutationRuntime.https.onCall(async (data, context) => {
    const adminUid = requirePaymentAdmin(context);
    const requestId = requireOperationId(data?.requestId);
    const authorization = requireAuthorizationInput(data);
    const request = await db
      .doc(`paymentAdministrationRequests/${requestId}`)
      .get();
    const requestData = request.data() ?? {};
    if (!request.exists || requestData.type !== SETTLEMENT_ADMIN_REQUEST_TYPE) {
      throw new functions.https.HttpsError(
        "not-found",
        "Settlement request not found.",
      );
    }
    const merchantId = requireMerchantId(requestData.merchantId);
    if (settlementAdminRequestRef(merchantId).id !== requestId) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Settlement request identity is invalid.",
      );
    }
    return {
      requestId,
      ...(await applySettlementVerificationAuthorization({
        adminUid,
        merchantId,
        ...authorization,
      })),
    };
  });

export const listSettlementVerificationRequestsV1 =
  paymentAdminReadRuntime.https.onCall(async (_data, context) => {
    requirePaymentAdmin(context, { requireRecentAuth: false });
    const snapshot = await db
      .collection("paymentAdministrationRequests")
      .orderBy("updatedAt", "desc")
      .limit(100)
      .get();
    return {
      requests: snapshot.docs
        .filter((doc) => doc.get("type") === SETTLEMENT_ADMIN_REQUEST_TYPE)
        .map((doc) => settlementAdminRequestProjection(doc.id, doc.data())),
    };
  });

export const setGlobalPaymentConfigurationV2 =
  paymentAdminMutationRuntime.https.onCall(async (data, context) => {
    const adminUid = requirePaymentAdmin(context);
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
    const requestedCustomerPaymentRequestsEnabled =
      typeof data?.customerPaymentRequestsEnabled === "boolean"
        ? data.customerPaymentRequestsEnabled
        : undefined;
    const configRef = db.doc("paymentConfiguration/global");
    let resultingSettlementVerificationSuspended = false;
    let resultingCustomerPaymentRequestsEnabled = false;
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
      const customerPaymentRequestsEnabled =
        requestedCustomerPaymentRequestsEnabled ??
        previous.customerPaymentRequestsEnabled === true;
      resultingCustomerPaymentRequestsEnabled = customerPaymentRequestsEnabled;
      tx.set(
        configRef,
        {
          capabilities,
          emergencySuspended,
          settlementVerificationSuspended,
          customerPaymentRequestsEnabled,
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
        previousCustomerPaymentRequestsEnabled:
          previous.customerPaymentRequestsEnabled === true,
        nextCustomerPaymentRequestsEnabled: customerPaymentRequestsEnabled,
        reason,
        createdAt: now,
      });
    });
    return {
      capabilities,
      emergencySuspended,
      settlementVerificationSuspended: resultingSettlementVerificationSuspended,
      customerPaymentRequestsEnabled: resultingCustomerPaymentRequestsEnabled,
    };
  });

/**
 * Resolves an ambiguous provider-delivery result without a Firestore-console
 * financial edit. The operation is bound to one request, outcome and evidence
 * reference, and can be retried safely after an interrupted support session.
 */
export const resolveCustomerPaymentRequestDeliveryReviewV1 =
  paymentAdminMutationRuntime.https.onCall(async (data, context) => {
    const adminUid = requirePaymentAdmin(context);
    const requestId = requireOperationId(data?.requestId);
    const operationId = requireOperationId(data?.operationId);
    const action = requirePaymentRequestReviewAction(data?.action);
    const evidenceReference = requireAuditText(
      data?.evidenceReference,
      "A non-secret provider evidence reference",
      200,
    );
    const reason = requireAuditText(data?.reason, "An audit reason");
    const channel = data?.channel === "sms" ? "sms" : "whatsapp";
    const providerMessageId =
      action === "confirm_delivery"
        ? requireAuditText(
            data?.providerMessageId,
            "The provider message ID",
            200,
          )
        : "";
    const auditId = stableDocumentId("audit", [
      "payment_request_delivery_review",
      adminUid,
      operationId,
    ]);
    const auditRef = db.doc(`paymentAdministrationAudit/${auditId}`);
    const requestRef = db.doc(`customerPaymentRequests/${requestId}`);
    let completed = false;

    await db.runTransaction(async (tx) => {
      const [audit, request] = await Promise.all([
        tx.get(auditRef),
        tx.get(requestRef),
      ]);
      if (!request.exists) {
        throw new functions.https.HttpsError(
          "not-found",
          "Payment request not found.",
        );
      }
      if (audit.exists) {
        const prior = audit.data() ?? {};
        if (
          prior.requestId !== requestId ||
          prior.reviewAction !== action ||
          prior.channel !== channel ||
          prior.evidenceReference !== evidenceReference ||
          prior.providerMessageId !== providerMessageId ||
          prior.reason !== reason
        ) {
          throw new functions.https.HttpsError(
            "already-exists",
            "That operationId is already bound to another review outcome.",
          );
        }
        completed = prior.state === "completed";
        return;
      }
      if (String(request.get("status") ?? "") !== "needs_review") {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Only a payment request awaiting operations review can be resolved.",
        );
      }
      tx.create(auditRef, {
        auditId,
        action: "payment_request_delivery_review",
        reviewAction: action,
        requestId,
        merchantId: request.get("merchantId"),
        customerId: request.get("customerId"),
        channel,
        evidenceReference,
        providerMessageId,
        reason,
        actorUid: adminUid,
        operationId,
        state: "pending",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        schemaVersion: 1,
      });
    });

    if (!completed) {
      try {
        if (action === "confirm_delivery") {
          await recordAcceptedCustomerPaymentRequest({
            requestId,
            channel,
            providerMessageId,
          });
        } else {
          await releaseReviewedCustomerPaymentRequest(
            requestId,
            `OPERATIONS_CONFIRMED_FAILED:${evidenceReference}`,
          );
        }
        await auditRef.set(
          {
            state: "completed",
            completedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      } catch (error) {
        await auditRef.set(
          {
            state: "failed",
            failureCode:
              error instanceof Error ? error.message.slice(0, 100) : "UNKNOWN",
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        throw error;
      }
    }
    return { requestId, action, auditId, completed: true };
  });
