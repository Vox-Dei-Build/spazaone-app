import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db } from "../../config/main";
import { stableDocumentId } from "./domain";
import {
  PAYMENT_OPERATIONS_NOTIFICATION_TYPE,
  PAYMENT_OPERATIONS_WORKSPACE_URL,
  settlementOperationsNotificationCopy,
  settlementOperationsNotificationId,
} from "./settlementOperationsNotifications";

export const SETTLEMENT_ADMIN_REQUEST_TYPE = "settlement_verification";
export const SETTLEMENT_VERIFICATION_AUTHORIZATION_TTL_MS = 24 * 60 * 60 * 1000;
export const SETTLEMENT_VERIFICATION_AUTHORIZATION_ATTEMPTS = 2;

export type SettlementAdminRequestStatus =
  | "authorization_required"
  | "authorized"
  | "pending_review"
  | "approved"
  | "changes_required"
  | "rejected"
  | "revoked";

const SETTLEMENT_ADMIN_REQUEST_STATUSES: SettlementAdminRequestStatus[] = [
  "authorization_required",
  "authorized",
  "pending_review",
  "approved",
  "changes_required",
  "rejected",
  "revoked",
];

export type SettlementAuthorizationRequestDecision = {
  nextStatus: SettlementAdminRequestStatus;
  createOrRefresh: boolean;
  deduped: boolean;
};

export function automaticSettlementAuthorizationDecision(input: {
  requestStatus: unknown;
  authorizationState: unknown;
  validationAttemptState: unknown;
  validationLifetimeAttemptCount: unknown;
}): { allowed: boolean; reason: string } {
  const lifetimeAttempts = Number(input.validationLifetimeAttemptCount ?? 0);
  if (!Number.isSafeInteger(lifetimeAttempts) || lifetimeAttempts < 0) {
    return { allowed: false, reason: "invalid_attempt_history" };
  }
  if (
    String(input.requestStatus ?? "") === "revoked" ||
    String(input.authorizationState ?? "") === "revoked"
  ) {
    return { allowed: false, reason: "authorization_revoked" };
  }
  if (
    !["", "authorization_required", "authorized"].includes(
      String(input.requestStatus ?? ""),
    )
  ) {
    return { allowed: false, reason: "request_requires_review" };
  }
  if (
    ["processing", "provider_outcome_unknown"].includes(
      String(input.validationAttemptState ?? ""),
    )
  ) {
    return { allowed: false, reason: "provider_attempt_requires_review" };
  }
  if (lifetimeAttempts > 0) {
    return { allowed: false, reason: "provider_attempt_requires_review" };
  }
  return { allowed: true, reason: "automatic_initial_authorization" };
}

export function settlementAuthorizationOpenDecision(input: {
  automaticRequested: boolean;
  activeAuthorization: boolean;
  existingAutomaticAuthorization: boolean;
  automaticEligible: boolean;
  existingStatus: unknown;
  sameVisibleDestination: boolean;
  authorizationInvalid?: boolean;
}): SettlementAuthorizationRequestDecision & {
  automaticallyAuthorized: boolean;
} {
  if (input.automaticRequested && input.activeAuthorization) {
    return {
      nextStatus: "authorized",
      createOrRefresh: false,
      deduped: true,
      automaticallyAuthorized: input.existingAutomaticAuthorization,
    };
  }
  if (input.automaticRequested && input.automaticEligible) {
    return {
      nextStatus: "authorized",
      createOrRefresh: true,
      deduped: false,
      automaticallyAuthorized: true,
    };
  }
  if (
    input.automaticRequested &&
    input.sameVisibleDestination &&
    ["pending_review", "approved"].includes(String(input.existingStatus ?? ""))
  ) {
    return {
      nextStatus: input.existingStatus as SettlementAdminRequestStatus,
      createOrRefresh: false,
      deduped: true,
      automaticallyAuthorized: false,
    };
  }
  return {
    ...settlementAuthorizationRequestDecision({
      existingStatus: input.existingStatus,
      sameVisibleDestination: input.sameVisibleDestination,
      authorizationInvalid:
        input.authorizationInvalid === true || input.automaticRequested,
    }),
    automaticallyAuthorized: false,
  };
}

/**
 * A request has one deterministic document per merchant. Repeated taps keep
 * the original queue age, while an explicit retry after a final decision
 * opens a fresh authorization review in that same document.
 */
export function settlementAuthorizationRequestDecision(input: {
  existingStatus: unknown;
  sameVisibleDestination: boolean;
  authorizationInvalid?: boolean;
}): SettlementAuthorizationRequestDecision {
  const status = String(input.existingStatus ?? "");
  if (
    !SETTLEMENT_ADMIN_REQUEST_STATUSES.includes(
      status as SettlementAdminRequestStatus,
    )
  ) {
    return {
      nextStatus: "authorization_required",
      createOrRefresh: true,
      deduped: false,
    };
  }
  if (status === "authorization_required" && input.sameVisibleDestination) {
    return {
      nextStatus: "authorization_required",
      createOrRefresh: false,
      deduped: true,
    };
  }
  if (
    ["authorized", "pending_review"].includes(status) &&
    input.sameVisibleDestination &&
    !input.authorizationInvalid
  ) {
    return {
      nextStatus: status as SettlementAdminRequestStatus,
      createOrRefresh: false,
      deduped: true,
    };
  }
  return {
    nextStatus: "authorization_required",
    createOrRefresh: true,
    deduped: false,
  };
}

export function settlementAdminRequestId(merchantId: string): string {
  return stableDocumentId("settlement_verification", [merchantId]);
}

export function settlementAdminRequestRef(merchantId: string) {
  return db.doc(
    `paymentAdministrationRequests/${settlementAdminRequestId(merchantId)}`,
  );
}

export function maskBankAccount(value: unknown): string {
  const account = String(value ?? "").replace(/\D/g, "");
  return account.length >= 4 ? `•••• ${account.slice(-4)}` : "";
}

function safeText(value: unknown, maximumLength: number): string {
  return String(value ?? "")
    .trim()
    .slice(0, maximumLength);
}

export async function upsertSettlementAuthorizationRequest(input: {
  merchantId: string;
  bankingDetailsId: string;
  bankingDetailsUpdatedAtMs: number;
  storeName: unknown;
  bankName: unknown;
  accountNumber: unknown;
  maskedAccountHolder: unknown;
  reasonCode: string;
  authorizationInvalid?: boolean;
  automaticInitialAuthorization?: {
    requestedBy: string;
  };
}): Promise<{
  requestId: string;
  status: SettlementAdminRequestStatus;
  deduped: boolean;
  automaticallyAuthorized: boolean;
}> {
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(input.bankingDetailsId)) {
    throw new Error("SETTLEMENT_BANKING_DETAILS_ID_INVALID");
  }
  if (
    !Number.isSafeInteger(input.bankingDetailsUpdatedAtMs) ||
    input.bankingDetailsUpdatedAtMs < 1
  ) {
    throw new Error("SETTLEMENT_BANKING_DETAILS_VERSION_INVALID");
  }
  const requestId = settlementAdminRequestId(input.merchantId);
  const ref = settlementAdminRequestRef(input.merchantId);
  const profileRef = db.doc(`merchantPaymentProfiles/${input.merchantId}`);
  const visible = {
    storeName: safeText(input.storeName, 100) || "Spaza One merchant",
    bankName: safeText(input.bankName, 100),
    maskedAccount: maskBankAccount(input.accountNumber),
    maskedAccountHolder: safeText(input.maskedAccountHolder, 100),
  };
  let result: SettlementAuthorizationRequestDecision = {
    nextStatus: "authorization_required",
    createOrRefresh: true,
    deduped: false,
  };
  let automaticallyAuthorized = false;
  await db.runTransaction(async (tx) => {
    const [existing, profile] = await Promise.all([
      tx.get(ref),
      tx.get(profileRef),
    ]);
    const current = existing.data() ?? {};
    const profileData = profile.data() ?? {};
    const sameVisibleDestination =
      current.storeName === visible.storeName &&
      current.bankName === visible.bankName &&
      current.maskedAccount === visible.maskedAccount &&
      current.maskedAccountHolder === visible.maskedAccountHolder &&
      current.bankingDetailsId === input.bankingDetailsId &&
      current.bankingDetailsUpdatedAtMs === input.bankingDetailsUpdatedAtMs;
    const authorization = (profileData.settlementVerificationAuthorization ??
      {}) as Record<string, unknown>;
    const nowMs = Date.now();
    const activeAutomaticAuthorization =
      input.automaticInitialAuthorization !== undefined &&
      current.status === "authorized" &&
      sameVisibleDestination &&
      authorization.state === "authorized" &&
      Number(authorization.expiresAtMs ?? 0) >= nowMs &&
      Number(authorization.remainingAttempts ?? 0) > 0 &&
      authorization.bankingDetailsId === input.bankingDetailsId &&
      Number(authorization.bankingDetailsUpdatedAtMs ?? 0) ===
        input.bankingDetailsUpdatedAtMs;
    const automaticDecision = input.automaticInitialAuthorization
      ? automaticSettlementAuthorizationDecision({
          requestStatus: current.status,
          authorizationState: authorization.state,
          validationAttemptState: profileData.validationAttemptState,
          validationLifetimeAttemptCount:
            profileData.validationLifetimeAttemptCount,
        })
      : { allowed: false, reason: "not_requested" };
    const openDecision = settlementAuthorizationOpenDecision({
      automaticRequested: input.automaticInitialAuthorization !== undefined,
      activeAuthorization: activeAutomaticAuthorization,
      existingAutomaticAuthorization:
        authorization.authorizationMode === "automatic_initial",
      automaticEligible: automaticDecision.allowed,
      existingStatus: current.status,
      sameVisibleDestination,
      authorizationInvalid: input.authorizationInvalid,
    });
    result = openDecision;
    automaticallyAuthorized = openDecision.automaticallyAuthorized;
    if (!result.createOrRefresh) return;
    const now = FieldValue.serverTimestamp();
    const currentSequence = Number(current.authorizationRequestSequence ?? 0);
    const authorizationRequestSequence =
      (Number.isSafeInteger(currentSequence) && currentSequence >= 0
        ? currentSequence
        : 0) + 1;
    const notificationId = settlementOperationsNotificationId({
      requestId,
      bankingDetailsId: input.bankingDetailsId,
      bankingDetailsUpdatedAtMs: input.bankingDetailsUpdatedAtMs,
      sequence: authorizationRequestSequence,
    });
    const expiresAtMs = automaticallyAuthorized
      ? nowMs + SETTLEMENT_VERIFICATION_AUTHORIZATION_TTL_MS
      : 0;
    tx.set(
      ref,
      {
        requestId,
        type: SETTLEMENT_ADMIN_REQUEST_TYPE,
        status: result.nextStatus,
        merchantId: input.merchantId,
        bankingDetailsId: input.bankingDetailsId,
        bankingDetailsUpdatedAtMs: input.bankingDetailsUpdatedAtMs,
        ...visible,
        requestReasonCode: safeText(input.reasonCode, 80),
        authorizationRequestSequence,
        authorizationExpiresAtMs: automaticallyAuthorized
          ? expiresAtMs
          : FieldValue.delete(),
        authorizationMode: automaticallyAuthorized
          ? "automatic_initial"
          : FieldValue.delete(),
        requestedAt: now,
        updatedAt: now,
        schemaVersion: 1,
      },
      { merge: true },
    );
    if (automaticallyAuthorized && input.automaticInitialAuthorization) {
      const operationId = stableDocumentId("auto", [
        requestId,
        input.bankingDetailsId,
        String(input.bankingDetailsUpdatedAtMs),
        String(authorizationRequestSequence),
      ]);
      const auditId = stableDocumentId("audit", [
        "settlement_verification_auto_authorized",
        operationId,
      ]);
      tx.set(
        profileRef,
        {
          merchantId: input.merchantId,
          settlementVerificationAuthorization: {
            state: "authorized",
            expiresAtMs,
            remainingAttempts: SETTLEMENT_VERIFICATION_AUTHORIZATION_ATTEMPTS,
            authorizedBy: "system:initial_guardrails",
            requestedBy: input.automaticInitialAuthorization.requestedBy,
            authorizedAt: now,
            authorizationMode: "automatic_initial",
            operationId,
            bankingDetailsId: input.bankingDetailsId,
            bankingDetailsUpdatedAtMs: input.bankingDetailsUpdatedAtMs,
          },
          schemaVersion: 2,
          updatedAt: now,
          updatedBy: input.automaticInitialAuthorization.requestedBy,
        },
        { merge: true },
      );
      tx.create(db.doc(`paymentAdministrationAudit/${auditId}`), {
        auditId,
        action: "settlement_verification_auto_authorized",
        merchantId: input.merchantId,
        actorUid: input.automaticInitialAuthorization.requestedBy,
        operationId,
        authorized: true,
        authorizationMode: "automatic_initial",
        expiresAtMs,
        maximumAttempts: SETTLEMENT_VERIFICATION_AUTHORIZATION_ATTEMPTS,
        reason: "initial_attempt_guardrails_passed",
        createdAt: now,
        schemaVersion: 2,
      });
    } else {
      const notificationCopy = settlementOperationsNotificationCopy();
      tx.create(db.doc(`paymentOperationsNotifications/${notificationId}`), {
        notificationId,
        requestId,
        type: PAYMENT_OPERATIONS_NOTIFICATION_TYPE,
        title: notificationCopy.title,
        body: notificationCopy.body,
        route: PAYMENT_OPERATIONS_WORKSPACE_URL,
        source: "settlementAuthorizationRequest",
        pushDeliveryState: "pending",
        createdAt: now,
        updatedAt: now,
        schemaVersion: 1,
      });
    }
  });
  return {
    requestId,
    status: result.nextStatus,
    deduped: result.deduped,
    automaticallyAuthorized,
  };
}

function timestampMillis(value: unknown): number | null {
  return value instanceof Timestamp ? value.toMillis() : null;
}

/**
 * Only this projection is allowed to cross the admin API boundary. Internal
 * merchant IDs, user IDs, account fingerprints and provider IDs remain server
 * side and must never be added here.
 */
export function settlementAdminRequestProjection(
  requestId: string,
  input: Record<string, unknown>,
): Record<string, unknown> {
  const status = String(input.status ?? "");
  if (
    input.type !== SETTLEMENT_ADMIN_REQUEST_TYPE ||
    !SETTLEMENT_ADMIN_REQUEST_STATUSES.includes(
      status as SettlementAdminRequestStatus,
    )
  ) {
    throw new Error("SETTLEMENT_ADMIN_REQUEST_INVALID");
  }
  const bankingDetailsId = String(input.bankingDetailsId ?? "").trim();
  const bankingDetailsUpdatedAtMs = Number(
    input.bankingDetailsUpdatedAtMs ?? 0,
  );
  const requiresMerchantResubmission =
    !/^[A-Za-z0-9_-]{1,200}$/.test(bankingDetailsId) ||
    !Number.isSafeInteger(bankingDetailsUpdatedAtMs) ||
    bankingDetailsUpdatedAtMs < 1;
  return {
    requestId,
    type: SETTLEMENT_ADMIN_REQUEST_TYPE,
    status,
    requiresMerchantResubmission,
    storeName: safeText(input.storeName, 100),
    bankName: safeText(input.bankName, 100),
    maskedAccount: safeText(input.maskedAccount, 30),
    maskedAccountHolder: safeText(input.maskedAccountHolder, 100),
    requestedAtMs: timestampMillis(input.requestedAt),
    updatedAtMs: timestampMillis(input.updatedAt),
  };
}

/**
 * Sensitive detail projection for one deliberately opened request. Callers
 * must enforce the recent-auth admin gate before reading the banking record.
 * Identity-document values and provider identifiers are never returned.
 */
export function settlementAdminRequestDetailProjection(input: {
  requestId: string;
  request: Record<string, unknown>;
  banking: Record<string, unknown>;
  bankingDetailsId: string;
  bankingDetailsUpdatedAtMs: number;
}): Record<string, unknown> {
  const summary = settlementAdminRequestProjection(
    input.requestId,
    input.request,
  );
  if (
    String(input.request.bankingDetailsId ?? "") !== input.bankingDetailsId ||
    Number(input.request.bankingDetailsUpdatedAtMs ?? 0) !==
      input.bankingDetailsUpdatedAtMs
  ) {
    throw new Error("SETTLEMENT_BANKING_DETAILS_VERSION_CHANGED");
  }
  const account = String(input.banking.accountNumber ?? "").replace(/\s/g, "");
  const holder = safeText(input.banking.accountHolderName, 100);
  const accountType = safeText(input.banking.accountType, 40);
  const branchCode = String(input.banking.branchCode ?? "").replace(/\s/g, "");
  if (
    !/^\d{5,20}$/.test(account) ||
    !holder ||
    !accountType ||
    !/^\d{6}$/.test(branchCode)
  ) {
    throw new Error("SETTLEMENT_BANKING_DETAILS_INVALID");
  }
  return {
    ...summary,
    account,
    holder,
    accountType,
    branchCode,
  };
}
