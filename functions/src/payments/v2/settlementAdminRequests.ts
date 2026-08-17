import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db } from "../../config/main";
import { stableDocumentId } from "./domain";

export const SETTLEMENT_ADMIN_REQUEST_TYPE = "settlement_verification";

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
}): Promise<{
  requestId: string;
  status: SettlementAdminRequestStatus;
  deduped: boolean;
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
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    const current = existing.data() ?? {};
    const sameVisibleDestination =
      current.storeName === visible.storeName &&
      current.bankName === visible.bankName &&
      current.maskedAccount === visible.maskedAccount &&
      current.maskedAccountHolder === visible.maskedAccountHolder &&
      current.bankingDetailsId === input.bankingDetailsId &&
      current.bankingDetailsUpdatedAtMs === input.bankingDetailsUpdatedAtMs;
    result = settlementAuthorizationRequestDecision({
      existingStatus: current.status,
      sameVisibleDestination,
      authorizationInvalid: input.authorizationInvalid === true,
    });
    if (!result.createOrRefresh) return;
    const now = FieldValue.serverTimestamp();
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
        requestedAt: now,
        updatedAt: now,
        schemaVersion: 1,
      },
      { merge: true },
    );
  });
  return { requestId, status: result.nextStatus, deduped: result.deduped };
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
  return {
    requestId,
    type: SETTLEMENT_ADMIN_REQUEST_TYPE,
    status,
    storeName: safeText(input.storeName, 100),
    bankName: safeText(input.bankName, 100),
    maskedAccount: safeText(input.maskedAccount, 30),
    maskedAccountHolder: safeText(input.maskedAccountHolder, 100),
    requestedAtMs: timestampMillis(input.requestedAt),
    updatedAtMs: timestampMillis(input.updatedAt),
  };
}
