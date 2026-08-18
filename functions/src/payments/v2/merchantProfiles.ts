import axios from "axios";
import { createHash, createHmac, randomUUID } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import {
  paystackReadOnlySecret,
  paystackSecret,
} from "../../config/environment";
import { authenticateFirebaseRequest } from "../../security/requestAuth";
import { assertStoreAccess, requireStoreId } from "../../stores/storeAccess";
import { PaymentPurpose, stableDocumentId } from "./domain";
import { requirePaymentAdmin } from "./paymentAdminAuth";
import {
  SETTLEMENT_ADMIN_REQUEST_TYPE,
  settlementAdminRequestRef,
  upsertSettlementAuthorizationRequest,
} from "./settlementAdminRequests";
import {
  deliverSettlementReviewNotification,
  settlementReviewNotificationCopy,
} from "./settlementNotifications";

const SETTLEMENT_CAPABILITIES: PaymentPurpose[] = [
  "merchant_order",
  "supplier_order",
  "account_settlement",
];
const VALIDATION_LEASE_MS = 45_000;
const MAX_VALIDATIONS_PER_MERCHANT_DAY = 2;
const MAX_VALIDATIONS_PER_MERCHANT_LIFETIME = 6;
const MAX_VALIDATIONS_PER_PLATFORM_DAY = 10;
const VALIDATION_PROVIDER_COST_MINOR = 300;
const VALIDATION_BUDGET_WARNING_ATTEMPTS = 7;

const FORBIDDEN_CARD_FIELDS = [
  "card",
  "cardNumber",
  "card_number",
  "pan",
  "bin",
  "cvv",
  "cvc",
  "expiry",
  "expiryMonth",
  "expiryYear",
  "authorizationCode",
  "authorization_code",
] as const;

type AccountType = "personal" | "business";
type DocumentType =
  | "identityNumber"
  | "passportNumber"
  | "businessRegistrationNumber";

type VerificationFlags = {
  verified: boolean;
  accountOpen: boolean;
  accountAcceptsCredits: boolean;
  accountHolderMatch: boolean;
  accountOpenForMoreThanThreeMonths: boolean;
};

export function assertBankAccountOnlyVerificationPayload(
  payload: unknown,
): void {
  const value =
    payload && typeof payload === "object"
      ? (payload as Record<string, unknown>)
      : {};
  const includesCardField = FORBIDDEN_CARD_FIELDS.some((field) => {
    const candidate = value[field];
    return candidate !== undefined && candidate !== null && candidate !== "";
  });
  const instrument = String(
    value.instrumentType ??
      value.paymentInstrument ??
      value.verificationType ??
      "",
  )
    .trim()
    .toLowerCase();
  if (includesCardField || instrument.includes("card")) {
    throw new Error("BANK_CARD_INPUT_REJECTED");
  }
}

export function settlementVerificationBudgetDecision(input: {
  merchantDayAttempts: number;
  merchantLifetimeAttempts: number;
  platformDayAttempts: number;
  suspended: boolean;
}): { allowed: boolean; reason: string; suspendAfterAttempt: boolean } {
  const counters = [
    input.merchantDayAttempts,
    input.merchantLifetimeAttempts,
    input.platformDayAttempts,
  ];
  if (
    counters.some((counter) => !Number.isSafeInteger(counter) || counter < 0)
  ) {
    throw new Error("BANK_VALIDATION_BUDGET_INVALID");
  }
  if (input.suspended) {
    return {
      allowed: false,
      reason: "BANK_VALIDATION_SUSPENDED",
      suspendAfterAttempt: false,
    };
  }
  if (input.merchantDayAttempts >= MAX_VALIDATIONS_PER_MERCHANT_DAY) {
    return {
      allowed: false,
      reason: "BANK_VALIDATION_DAILY_LIMIT",
      suspendAfterAttempt: false,
    };
  }
  if (input.merchantLifetimeAttempts >= MAX_VALIDATIONS_PER_MERCHANT_LIFETIME) {
    return {
      allowed: false,
      reason: "BANK_VALIDATION_LIFETIME_LIMIT",
      suspendAfterAttempt: false,
    };
  }
  if (input.platformDayAttempts >= MAX_VALIDATIONS_PER_PLATFORM_DAY) {
    return {
      allowed: false,
      reason: "BANK_VALIDATION_PLATFORM_LIMIT",
      suspendAfterAttempt: false,
    };
  }
  return {
    allowed: true,
    reason: "allowed",
    suspendAfterAttempt:
      input.platformDayAttempts + 1 >= MAX_VALIDATIONS_PER_PLATFORM_DAY,
  };
}

export function settlementVerificationAuthorizationDecision(input: {
  state: unknown;
  expiresAtMs: unknown;
  remainingAttempts: unknown;
  nowMs: number;
  bankingDetailsId?: unknown;
  bankingDetailsUpdatedAtMs?: unknown;
  expectedBankingDetailsId?: string;
  expectedBankingDetailsUpdatedAtMs?: number;
}): { allowed: boolean; reason: string } {
  const expiresAtMs = Number(input.expiresAtMs ?? 0);
  const remainingAttempts = Number(input.remainingAttempts ?? 0);
  if (String(input.state ?? "") !== "authorized") {
    return { allowed: false, reason: "BANK_VALIDATION_PREAUTH_REQUIRED" };
  }
  if (!Number.isSafeInteger(expiresAtMs) || expiresAtMs < input.nowMs) {
    return { allowed: false, reason: "BANK_VALIDATION_PREAUTH_EXPIRED" };
  }
  if (!Number.isSafeInteger(remainingAttempts) || remainingAttempts < 1) {
    return { allowed: false, reason: "BANK_VALIDATION_PREAUTH_CONSUMED" };
  }
  if (
    input.expectedBankingDetailsId !== undefined &&
    (String(input.bankingDetailsId ?? "") !== input.expectedBankingDetailsId ||
      Number(input.bankingDetailsUpdatedAtMs ?? 0) !==
        input.expectedBankingDetailsUpdatedAtMs)
  ) {
    return {
      allowed: false,
      reason: "BANK_VALIDATION_PREAUTH_DESTINATION_CHANGED",
    };
  }
  return { allowed: true, reason: "allowed" };
}

export function settlementVerificationDecision(flags: VerificationFlags): {
  eligible: boolean;
  autoApprove: boolean;
} {
  const eligible =
    flags.verified &&
    flags.accountOpen &&
    flags.accountAcceptsCredits &&
    flags.accountHolderMatch;
  return {
    eligible,
    // Provider evidence is necessary but never sufficient to grant settlement
    // authority. A Spaza One admin must approve every new destination.
    autoApprove: false,
  };
}

const ZA_BANK_NAME_ALIASES: Readonly<Record<string, string>> = {
  fnb: "firstnationalbank",
  firstnational: "firstnationalbank",
  firstnationalbank: "firstnationalbank",
};

type PaystackSettlementBank = {
  name?: unknown;
  code?: unknown;
  enabled_for_verification?: unknown;
  supported_types?: unknown;
};

export type SupportedSettlementBank = {
  name: string;
  branchCode: string;
  supportedAccountTypes: AccountType[];
};

export function supportedSettlementBanks(
  input: unknown,
): SupportedSettlementBank[] {
  if (!Array.isArray(input)) return [];
  const byBranchCode = new Map<string, SupportedSettlementBank>();
  for (const raw of input as PaystackSettlementBank[]) {
    const name = String(raw?.name ?? "")
      .trim()
      .slice(0, 100);
    const branchCode = String(raw?.code ?? "").replace(/\s/g, "");
    const supportedAccountTypes = Array.isArray(raw?.supported_types)
      ? raw.supported_types
          .map((value) => String(value).trim())
          .filter(
            (value): value is AccountType =>
              value === "personal" || value === "business",
          )
      : [];
    if (
      !name ||
      !/^\d{6}$/.test(branchCode) ||
      supportedAccountTypes.length === 0 ||
      raw?.enabled_for_verification === false
    ) {
      continue;
    }
    byBranchCode.set(branchCode, {
      name,
      branchCode,
      supportedAccountTypes: [...new Set(supportedAccountTypes)],
    });
  }
  return [...byBranchCode.values()].sort((left, right) =>
    left.name.localeCompare(right.name, "en-ZA"),
  );
}

async function fetchSupportedSettlementBanks(
  secret: string,
): Promise<SupportedSettlementBank[]> {
  const response = await axios.get("https://api.paystack.co/bank", {
    headers: { Authorization: `Bearer ${secret}` },
    params: {
      country: "south africa",
      currency: "ZAR",
      enabled_for_verification: true,
      perPage: 100,
    },
    timeout: 15_000,
  });
  return supportedSettlementBanks(response.data?.data);
}

export function normalizedBankName(value: unknown): string {
  const normalized = String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
  return ZA_BANK_NAME_ALIASES[normalized] ?? normalized;
}

/**
 * Returns only the safe bank-name/universal-branch-code projection used by
 * the merchant form. The provider secret and all other provider metadata stay
 * server-side.
 */
export const listSupportedSettlementBanksV1 = functions
  .runWith({
    secrets: ["PAYSTACK_SECRET_KEY"],
    enforceAppCheck: true,
  })
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in is required.",
      );
    }
    try {
      const banks = await fetchSupportedSettlementBanks(
        paystackReadOnlySecret(),
      );
      if (banks.length > 0) return { banks };
    } catch (error) {
      functions.logger.error("Supported bank catalogue fetch failed", {
        error:
          error instanceof Error
            ? error.message.slice(0, 120)
            : "unknown_error",
      });
    }
    throw new functions.https.HttpsError(
      "unavailable",
      "Supported banks are temporarily unavailable.",
    );
  });

function accountNumber(value: unknown): string {
  const account = String(value ?? "").replace(/\s+/g, "");
  if (!/^\d{5,20}$/.test(account)) throw new Error("BANK_ACCOUNT_INVALID");
  return account;
}

export function settlementVerificationIdentity(input: {
  accountType: unknown;
  documentType: unknown;
  documentNumber: unknown;
}): {
  accountType: AccountType;
  documentType: DocumentType;
  documentNumber: string;
} {
  const accountType = String(input.accountType ?? "").trim() as AccountType;
  const documentType = String(input.documentType ?? "").trim() as DocumentType;
  const documentNumber = String(input.documentNumber ?? "").trim();
  if (!(["personal", "business"] as string[]).includes(accountType)) {
    throw new Error("BANK_ACCOUNT_TYPE_INVALID");
  }
  const allowedDocumentTypes: DocumentType[] =
    accountType === "business"
      ? ["businessRegistrationNumber"]
      : ["identityNumber", "passportNumber"];
  if (!allowedDocumentTypes.includes(documentType)) {
    throw new Error("BANK_DOCUMENT_TYPE_INVALID");
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9/ -]{3,38}[A-Za-z0-9]$/.test(documentNumber)) {
    throw new Error("BANK_DOCUMENT_NUMBER_INVALID");
  }
  return { accountType, documentType, documentNumber };
}

export type SettlementProfileAction =
  | "dedupe_active"
  | "dedupe_pending"
  | "pending_review";

export function settlementProfileAction(input: {
  sameActiveDestination: boolean;
  samePendingDestination: boolean;
  hadActiveAccount: boolean;
  validationAutoApprove: boolean;
}): SettlementProfileAction {
  if (input.sameActiveDestination) return "dedupe_active";
  if (input.samePendingDestination) return "dedupe_pending";
  return "pending_review";
}

const FINAL_PAYMENT_INTENT_STATUSES = new Set([
  "cancelled",
  "expired",
  "failed",
  "paid",
  "refunded",
]);

export function settlementDestinationRetirementDecision(input: {
  settlementStatuses: string[];
  paymentIntentStatuses: string[];
  settlementWindowComplete: boolean;
  paymentIntentWindowComplete: boolean;
}): { safe: boolean; reason: string } {
  if (!input.settlementWindowComplete || !input.paymentIntentWindowComplete) {
    return { safe: false, reason: "history_truncated" };
  }
  if (
    input.settlementStatuses.some((status) =>
      ["pending", "processing", "submitted"].includes(status),
    )
  ) {
    return { safe: false, reason: "pending_settlement" };
  }
  if (
    input.paymentIntentStatuses.some(
      (status) => !FINAL_PAYMENT_INTENT_STATUSES.has(status),
    )
  ) {
    return { safe: false, reason: "in_flight_payment" };
  }
  return { safe: true, reason: "clear" };
}

function sha256(parts: string[]): string {
  return createHash("sha256").update(parts.join("\u001f")).digest("hex");
}

function accountFingerprint(
  secret: string,
  bankCode: string,
  account: string,
): string {
  if (!secret) throw new Error("PAYSTACK_SECRET_UNAVAILABLE");
  return createHmac("sha256", secret)
    .update("paystack-za-account\u001f")
    .update(bankCode)
    .update("\u001f")
    .update(account)
    .digest("hex");
}

export function protectedIdentityFingerprint(
  secret: string,
  identity: {
    documentType: DocumentType;
    documentNumber: string;
  },
): string {
  if (!secret) throw new Error("PAYSTACK_SECRET_UNAVAILABLE");
  return createHmac("sha256", secret)
    .update("paystack-za-identity\u001f")
    .update(identity.documentType)
    .update("\u001f")
    .update(identity.documentNumber.replace(/[ /-]/g, "").toUpperCase())
    .digest("hex");
}

export function maskedAccountHolderName(value: unknown): string {
  const parts = String(value ?? "")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  return parts
    .map((part) =>
      part.length <= 2
        ? `${part[0] ?? ""}•`
        : `${part[0]}${"•".repeat(Math.min(8, part.length - 1))}`,
    )
    .join(" ")
    .slice(0, 100);
}

function publicError(error: unknown): { status: number; message: string } {
  if (error instanceof functions.https.HttpsError) {
    const status =
      error.code === "unauthenticated"
        ? 401
        : error.code === "permission-denied"
          ? 403
          : 400;
    return { status, message: error.message };
  }
  const code = error instanceof Error ? error.message : "";
  const known: Record<string, [number, string]> = {
    BANK_ACCOUNT_INVALID: [400, "Enter a valid bank account number."],
    BANK_ACCOUNT_TYPE_INVALID: [400, "Choose personal or business account."],
    BANK_ACCOUNT_TYPE_NOT_SUPPORTED: [
      409,
      "That bank does not support the selected account type for verification.",
    ],
    BANK_DOCUMENT_TYPE_INVALID: [
      400,
      "Choose an identity document that matches the account type.",
    ],
    BANK_DOCUMENT_NUMBER_INVALID: [
      400,
      "Enter a valid identity or registration number.",
    ],
    BANK_NOT_SUPPORTED: [
      409,
      "That bank is not currently enabled for Paystack verification.",
    ],
    BANK_ACCOUNT_NOT_VALIDATED: [
      409,
      "Paystack could not validate this account for settlements.",
    ],
    BANK_VALIDATION_RATE_LIMITED: [
      429,
      "Too many verification attempts. Try again later or contact support.",
    ],
    BANK_VALIDATION_DAILY_LIMIT: [
      429,
      "The daily bank-verification limit was reached. Contact support if the details must be corrected today.",
    ],
    BANK_VALIDATION_LIFETIME_LIMIT: [
      429,
      "Bank verification needs a support review before another attempt.",
    ],
    BANK_VALIDATION_PLATFORM_LIMIT: [
      503,
      "Bank verification is temporarily paused for a security review.",
    ],
    BANK_VALIDATION_SUSPENDED: [
      503,
      "Bank verification is temporarily paused for a security review.",
    ],
    BANK_VALIDATION_PREAUTH_REQUIRED: [
      403,
      "Your settlement-verification request was sent to Spaza One for approval.",
    ],
    BANK_VALIDATION_PREAUTH_EXPIRED: [
      403,
      "Your settlement-verification approval expired. A new approval request was sent to Spaza One.",
    ],
    BANK_VALIDATION_PREAUTH_CONSUMED: [
      403,
      "The approved settlement-verification attempts were used. A new approval request was sent to Spaza One.",
    ],
    BANK_VALIDATION_PREAUTH_DESTINATION_CHANGED: [
      403,
      "Your bank details changed after approval. A new settlement-verification request was sent to Spaza One.",
    ],
    BANK_CARD_INPUT_REJECTED: [
      400,
      "Use bank account details for settlements. Card details are not accepted here.",
    ],
    BANK_VALIDATION_ALREADY_PROCESSING: [
      409,
      "This account verification is already processing.",
    ],
    BANK_VALIDATION_OUTCOME_UNKNOWN: [
      409,
      "Paystack may still be processing this account. Contact support before retrying.",
    ],
    PAYSTACK_SUBACCOUNT_INVALID: [
      502,
      "Paystack did not confirm the settlement profile.",
    ],
  };
  const mapped = known[code];
  return mapped
    ? { status: mapped[0], message: mapped[1] }
    : {
        status: 500,
        message: "Settlement verification is temporarily unavailable.",
      };
}

function paystackSafeProviderCode(error: unknown): string {
  if (axios.isAxiosError(error)) {
    const status = Number(error.response?.status);
    return Number.isFinite(status)
      ? `PAYSTACK_HTTP_${status}`
      : `PAYSTACK_${String(error.code ?? "UNAVAILABLE").slice(0, 40)}`;
  }
  return error instanceof Error
    ? String(error.message || "PAYSTACK_UNAVAILABLE").slice(0, 80)
    : "PAYSTACK_UNAVAILABLE";
}

async function setPaystackSubaccountActive(
  secret: string,
  subaccountCode: string,
  active: boolean,
): Promise<void> {
  const response = await axios.put(
    `https://api.paystack.co/subaccount/${encodeURIComponent(subaccountCode)}`,
    { active },
    {
      headers: { Authorization: `Bearer ${secret}` },
      timeout: 20_000,
    },
  );
  if (
    response.data?.status !== true ||
    response.data?.data?.active !== active
  ) {
    throw new Error("PAYSTACK_SUBACCOUNT_UPDATE_INVALID");
  }
}

function activeSubaccount(data: Record<string, unknown>): boolean {
  return (
    data.bankVerificationStatus === "approved" &&
    /^ACCT_[A-Za-z0-9]+$/.test(String(data.paystackSubaccountCode ?? ""))
  );
}

function profileSummary(input: {
  merchantId: string;
  status: string;
  bankName: unknown;
  accountName: unknown;
  accountLast4: unknown;
  accountFingerprint: string;
  deduped: boolean;
  autoApproved?: boolean;
}): Record<string, unknown> {
  return {
    status: input.status,
    bankName: String(input.bankName ?? ""),
    resolvedAccountName: String(input.accountName ?? ""),
    maskedAccount: input.accountLast4
      ? `•••• ${String(input.accountLast4)}`
      : "",
    deduped: input.deduped,
    autoApproved: input.autoApproved === true,
  };
}

/**
 * Creates the merchant-visible beginning of the verification journey without
 * spending a billable provider validation attempt or collecting identity
 * evidence. The deterministic request document makes retries idempotent.
 */
export const requestMerchantSettlementVerificationV1 = functions
  .runWith({ enforceAppCheck: true })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in is required.",
      );
    }
    const merchantId = requireStoreId(data?.merchantId);
    await assertStoreAccess(context.auth.uid, merchantId, ["owner", "admin"]);
    const bankingDetailsId = String(data?.bankingDetailsId ?? "").trim();
    if (!/^[A-Za-z0-9_-]{1,200}$/.test(bankingDetailsId)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Choose saved banking details.",
      );
    }
    const [banking, merchant] = await Promise.all([
      db.doc(`users/${merchantId}/bankingDetails/${bankingDetailsId}`).get(),
      db.doc(`users/${merchantId}`).get(),
    ]);
    if (!banking.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Banking details not found.",
      );
    }
    const raw = banking.data() ?? {};
    const bankName = String(raw.bankName ?? "").trim();
    const branchCode = String(raw.branchCode ?? "").replace(/\s/g, "");
    if (!bankName) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Enter the bank name.",
      );
    }
    if (!/^\d{6}$/.test(branchCode)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Enter a valid six-digit branch code.",
      );
    }
    let account = "";
    try {
      account = accountNumber(raw.accountNumber);
    } catch (_) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Enter a valid bank account number.",
      );
    }
    const accountHolder = String(raw.accountHolderName ?? "").trim();
    if (!accountHolder) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Enter the bank account holder name.",
      );
    }
    const storeName = String(
      merchant.data()?.shopName ??
        merchant.data()?.businessName ??
        merchant.data()?.name ??
        "Spaza One merchant",
    );
    const request = await upsertSettlementAuthorizationRequest({
      merchantId,
      bankingDetailsId,
      bankingDetailsUpdatedAtMs: banking.updateTime?.toMillis() ?? 0,
      storeName,
      bankName,
      accountNumber: account,
      maskedAccountHolder: maskedAccountHolderName(accountHolder),
      reasonCode: "MERCHANT_REQUESTED",
    });
    return {
      status: request.status,
      deduped: request.deduped,
    };
  });

export const prepareMerchantSettlementProfileV2 = functions
  .runWith({ secrets: ["PAYSTACK_SECRET_KEY"] })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    let profileRef: FirebaseFirestore.DocumentReference | undefined;
    let claimId = "";
    let claimAcquired = false;
    let providerStage: "none" | "validating" | "creating_subaccount" = "none";
    try {
      const uid = await authenticateFirebaseRequest(req, res, {
        requireAppCheck: true,
      });
      if (!uid) return;
      assertBankAccountOnlyVerificationPayload(req.body);
      const merchantId = requireStoreId(req.body?.merchantId);
      await assertStoreAccess(uid, merchantId, ["owner", "admin"]);
      const bankingDetailsId = String(req.body?.bankingDetailsId ?? "").trim();
      if (!/^[A-Za-z0-9_-]{1,200}$/.test(bankingDetailsId)) {
        res.status(400).json({ error: "Choose saved banking details." });
        return;
      }
      const identity = settlementVerificationIdentity({
        accountType: req.body?.accountType,
        documentType: req.body?.documentType,
        documentNumber: req.body?.documentNumber,
      });
      const [banking, merchant] = await Promise.all([
        db.doc(`users/${merchantId}/bankingDetails/${bankingDetailsId}`).get(),
        db.doc(`users/${merchantId}`).get(),
      ]);
      if (!banking.exists) {
        res.status(404).json({ error: "Banking details not found." });
        return;
      }
      const raw = banking.data() ?? {};
      const bankingDetailsUpdatedAtMs = banking.updateTime?.toMillis() ?? 0;
      const account = accountNumber(raw.accountNumber);
      const requestedBankName = String(raw.bankName ?? "").trim();
      const submittedAccountName = String(raw.accountHolderName ?? "").trim();
      if (!submittedAccountName) throw new Error("BANK_ACCOUNT_NOT_VALIDATED");
      const businessName = String(
        merchant.data()?.shopName ??
          merchant.data()?.businessName ??
          merchant.data()?.name ??
          submittedAccountName ??
          "Spaza One merchant",
      )
        .trim()
        .slice(0, 100);
      profileRef = db.doc(`merchantPaymentProfiles/${merchantId}`);
      const existing = await profileRef.get();
      const existingData = existing.data() ?? {};
      const secret = paystackSecret();
      const documentFingerprint = protectedIdentityFingerprint(
        secret,
        identity,
      );
      const pending = (existingData.pendingSettlement ?? {}) as Record<
        string,
        unknown
      >;
      const storedBankCode = String(
        pending.accountFingerprint
          ? (pending.bankCode ?? "")
          : (existingData.bankCode ?? ""),
      ).trim();
      if (storedBankCode) {
        const storedFingerprint = accountFingerprint(
          secret,
          storedBankCode,
          account,
        );
        const earlyDedupeAction = settlementProfileAction({
          sameActiveDestination:
            existingData.accountFingerprint === storedFingerprint &&
            existingData.identityFingerprint === documentFingerprint &&
            activeSubaccount(existingData),
          samePendingDestination:
            pending.accountFingerprint === storedFingerprint &&
            pending.identityFingerprint === documentFingerprint &&
            /^ACCT_[A-Za-z0-9]+$/.test(
              String(pending.paystackSubaccountCode ?? ""),
            ),
          hadActiveAccount: activeSubaccount(existingData),
          validationAutoApprove: false,
        });
        if (earlyDedupeAction === "dedupe_active") {
          res.status(200).json(
            profileSummary({
              merchantId,
              status: String(existingData.status ?? "enabled"),
              bankName: existingData.bankName,
              accountName: existingData.resolvedAccountName,
              accountLast4: existingData.accountLast4,
              accountFingerprint: storedFingerprint,
              deduped: true,
              autoApproved: existingData.bankAutoApproved === true,
            }),
          );
          return;
        }
        if (earlyDedupeAction === "dedupe_pending") {
          await settlementAdminRequestRef(merchantId).set(
            {
              status: "pending_review",
              accountFingerprint: storedFingerprint,
            },
            { merge: true },
          );
          res.status(200).json(
            profileSummary({
              merchantId,
              status: "pending_review",
              bankName: pending.bankName,
              accountName: pending.resolvedAccountName,
              accountLast4: pending.accountLast4,
              accountFingerprint: storedFingerprint,
              deduped: true,
            }),
          );
          return;
        }
      }

      const initialAuthorization =
        (existingData.settlementVerificationAuthorization ?? {}) as Record<
          string,
          unknown
        >;
      const initialAuthorizationDecision =
        settlementVerificationAuthorizationDecision({
          state: initialAuthorization.state,
          expiresAtMs: initialAuthorization.expiresAtMs,
          remainingAttempts: initialAuthorization.remainingAttempts,
          nowMs: Date.now(),
          bankingDetailsId: initialAuthorization.bankingDetailsId,
          bankingDetailsUpdatedAtMs:
            initialAuthorization.bankingDetailsUpdatedAtMs,
          expectedBankingDetailsId: bankingDetailsId,
          expectedBankingDetailsUpdatedAtMs: bankingDetailsUpdatedAtMs,
        });
      if (!initialAuthorizationDecision.allowed) {
        await upsertSettlementAuthorizationRequest({
          merchantId,
          bankingDetailsId,
          bankingDetailsUpdatedAtMs,
          storeName: businessName,
          bankName: requestedBankName,
          accountNumber: account,
          maskedAccountHolder: maskedAccountHolderName(submittedAccountName),
          reasonCode: initialAuthorizationDecision.reason,
          authorizationInvalid: true,
        });
        throw new Error(initialAuthorizationDecision.reason);
      }

      const banks = await fetchSupportedSettlementBanks(secret);
      const requestedBranchCode = String(raw.branchCode ?? "").replace(
        /\s/g,
        "",
      );
      const bank = banks.find((candidate) => {
        const candidateCode = candidate.branchCode;
        return (
          (requestedBranchCode && candidateCode === requestedBranchCode) ||
          normalizedBankName(candidate.name) ===
            normalizedBankName(requestedBankName)
        );
      });
      const bankCode = String(bank?.branchCode ?? "").trim();
      if (!bankCode) {
        throw new Error("BANK_NOT_SUPPORTED");
      }
      if (!bank?.supportedAccountTypes.includes(identity.accountType)) {
        throw new Error("BANK_ACCOUNT_TYPE_NOT_SUPPORTED");
      }
      const fingerprint = accountFingerprint(secret, bankCode, account);
      const attemptFingerprint = sha256([fingerprint, documentFingerprint]);
      const sameActiveDestination =
        existingData.accountFingerprint === fingerprint &&
        existingData.identityFingerprint === documentFingerprint &&
        activeSubaccount(existingData);
      const samePendingDestination =
        pending.accountFingerprint === fingerprint &&
        pending.identityFingerprint === documentFingerprint &&
        /^ACCT_[A-Za-z0-9]+$/.test(
          String(pending.paystackSubaccountCode ?? ""),
        );
      const dedupeAction = settlementProfileAction({
        sameActiveDestination,
        samePendingDestination,
        hadActiveAccount: activeSubaccount(existingData),
        validationAutoApprove: false,
      });
      if (dedupeAction === "dedupe_active") {
        res.status(200).json(
          profileSummary({
            merchantId,
            status: String(existingData.status ?? "enabled"),
            bankName: existingData.bankName,
            accountName: existingData.resolvedAccountName,
            accountLast4: existingData.accountLast4,
            accountFingerprint: fingerprint,
            deduped: true,
            autoApproved: existingData.bankAutoApproved === true,
          }),
        );
        return;
      }
      if (dedupeAction === "dedupe_pending") {
        await settlementAdminRequestRef(merchantId).set(
          {
            status: "pending_review",
            accountFingerprint: fingerprint,
          },
          { merge: true },
        );
        res.status(200).json(
          profileSummary({
            merchantId,
            status: "pending_review",
            bankName: pending.bankName,
            accountName: pending.resolvedAccountName,
            accountLast4: pending.accountLast4,
            accountFingerprint: fingerprint,
            deduped: true,
          }),
        );
        return;
      }

      claimId = randomUUID();
      const nowMs = Date.now();
      const windowKey = new Date(nowMs).toISOString().slice(0, 10);
      const budgetRef = db.doc(
        `paymentSecurityBudgets/settlement_bank_validation_${windowKey}`,
      );
      const globalConfigRef = db.doc("paymentConfiguration/global");
      await db.runTransaction(async (tx) => {
        const [current, budget, globalConfig] = await Promise.all([
          tx.get(profileRef!),
          tx.get(budgetRef),
          tx.get(globalConfigRef),
        ]);
        const value = current.data() ?? {};
        const budgetData = budget.data() ?? {};
        const globalData = globalConfig.data() ?? {};
        if (
          value.validationAttemptFingerprint === attemptFingerprint &&
          value.validationAttemptState === "provider_outcome_unknown"
        ) {
          throw new Error("BANK_VALIDATION_OUTCOME_UNKNOWN");
        }
        if (
          value.validationAttemptState === "processing" &&
          Number(value.validationAttemptLeaseUntilMs ?? 0) > nowMs
        ) {
          throw new Error("BANK_VALIDATION_ALREADY_PROCESSING");
        }
        const authorization = (value.settlementVerificationAuthorization ??
          {}) as Record<string, unknown>;
        const authorizationDecision =
          settlementVerificationAuthorizationDecision({
            state: authorization.state,
            expiresAtMs: authorization.expiresAtMs,
            remainingAttempts: authorization.remainingAttempts,
            nowMs,
            bankingDetailsId: authorization.bankingDetailsId,
            bankingDetailsUpdatedAtMs: authorization.bankingDetailsUpdatedAtMs,
            expectedBankingDetailsId: bankingDetailsId,
            expectedBankingDetailsUpdatedAtMs: bankingDetailsUpdatedAtMs,
          });
        if (!authorizationDecision.allowed) {
          throw new Error(authorizationDecision.reason);
        }
        const merchantDayAttempts =
          value.validationAttemptWindow === windowKey
            ? Number(value.validationAttemptCount ?? 0) + 1
            : 1;
        const merchantLifetimeAttempts =
          Number(value.validationLifetimeAttemptCount ?? 0) + 1;
        const platformDayAttempts = Number(budgetData.attemptCount ?? 0) + 1;
        const budgetDecision = settlementVerificationBudgetDecision({
          merchantDayAttempts: merchantDayAttempts - 1,
          merchantLifetimeAttempts: merchantLifetimeAttempts - 1,
          platformDayAttempts: platformDayAttempts - 1,
          suspended: globalData.settlementVerificationSuspended === true,
        });
        if (!budgetDecision.allowed) {
          throw new Error(budgetDecision.reason);
        }
        const now = FieldValue.serverTimestamp();
        const remainingAuthorizedAttempts =
          Number(authorization.remainingAttempts) - 1;
        tx.set(
          profileRef!,
          {
            merchantId,
            validationAttemptClaimId: claimId,
            validationAttemptFingerprint: attemptFingerprint,
            validationAttemptState: "processing",
            validationAttemptLeaseUntilMs: nowMs + VALIDATION_LEASE_MS,
            validationAttemptWindow: windowKey,
            validationAttemptCount: merchantDayAttempts,
            validationLifetimeAttemptCount: merchantLifetimeAttempts,
            settlementVerificationAuthorization: {
              ...authorization,
              state:
                remainingAuthorizedAttempts > 0 ? "authorized" : "consumed",
              remainingAttempts: remainingAuthorizedAttempts,
              lastUsedAt: now,
              lastUsedBy: uid,
            },
            updatedAt: now,
          },
          { merge: true },
        );
        tx.set(
          budgetRef,
          {
            budgetId: `settlement_bank_validation_${windowKey}`,
            provider: "paystack",
            operation: "za_bank_account_validation",
            day: windowKey,
            attemptCount: platformDayAttempts,
            maximumExposureMinor:
              platformDayAttempts * VALIDATION_PROVIDER_COST_MINOR,
            currency: "ZAR",
            updatedAt: now,
            schemaVersion: 2,
            ...(budget.exists ? {} : { createdAt: now }),
          },
          { merge: true },
        );
        if (platformDayAttempts >= VALIDATION_BUDGET_WARNING_ATTEMPTS) {
          tx.set(
            db.doc(
              `operationsAlerts/settlement_verification_budget_${windowKey}`,
            ),
            {
              alertId: `settlement_verification_budget_${windowKey}`,
              type: "settlement_verification_budget",
              severity: budgetDecision.suspendAfterAttempt
                ? "critical"
                : "warning",
              owner: "security_operations",
              status: "open",
              attemptCount: platformDayAttempts,
              maximumExposureMinor:
                platformDayAttempts * VALIDATION_PROVIDER_COST_MINOR,
              currency: "ZAR",
              updatedAt: now,
              ...(budget.exists ? {} : { createdAt: now }),
              schemaVersion: 2,
            },
            { merge: true },
          );
        }
        if (budgetDecision.suspendAfterAttempt) {
          tx.set(
            globalConfigRef,
            {
              settlementVerificationSuspended: true,
              settlementVerificationSuspendedReason:
                "daily_security_budget_exhausted",
              settlementVerificationSuspendedAt: now,
              updatedAt: now,
            },
            { merge: true },
          );
        }
      });
      claimAcquired = true;

      providerStage = "validating";
      const validateResponse = await axios.post(
        "https://api.paystack.co/bank/validate",
        {
          bank_code: bankCode,
          country_code: "ZA",
          account_number: account,
          account_name: submittedAccountName,
          account_type: identity.accountType,
          document_type: identity.documentType,
          document_number: identity.documentNumber,
        },
        {
          headers: { Authorization: `Bearer ${secret}` },
          timeout: 20_000,
        },
      );
      const validated = validateResponse.data?.data ?? {};
      if (validateResponse.data?.status === true) {
        await budgetRef.set(
          {
            providerAcceptedCount: FieldValue.increment(1),
            estimatedProviderCostMinor: FieldValue.increment(
              VALIDATION_PROVIDER_COST_MINOR,
            ),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
      const flags: VerificationFlags = {
        verified: validated.verified === true,
        accountOpen: validated.accountOpen === true,
        accountAcceptsCredits: validated.accountAcceptsCredits === true,
        accountHolderMatch: validated.accountHolderMatch === true,
        accountOpenForMoreThanThreeMonths:
          validated.accountOpenForMoreThanThreeMonths === true,
      };
      const decision = settlementVerificationDecision(flags);
      if (validateResponse.data?.status !== true || !decision.eligible) {
        throw new Error("BANK_ACCOUNT_NOT_VALIDATED");
      }

      providerStage = "creating_subaccount";
      const subaccountResponse = await axios.post(
        "https://api.paystack.co/subaccount",
        {
          business_name: businessName,
          settlement_bank: bankCode,
          account_number: account,
          percentage_charge: 1.5,
          description: `Spaza One settlement for ${merchantId}`,
          metadata: JSON.stringify({
            merchantId,
            accountFingerprint: fingerprint,
            schemaVersion: 2,
          }),
        },
        {
          headers: { Authorization: `Bearer ${secret}` },
          timeout: 20_000,
        },
      );
      const subaccount = subaccountResponse.data?.data ?? {};
      const subaccountCode = String(subaccount.subaccount_code ?? "").trim();
      if (
        subaccountResponse.data?.status !== true ||
        !/^ACCT_[A-Za-z0-9]+$/.test(subaccountCode)
      ) {
        throw new Error("PAYSTACK_SUBACCOUNT_INVALID");
      }

      const hadActiveAccount = activeSubaccount(existingData);
      await setPaystackSubaccountActive(secret, subaccountCode, false);
      const settlement = {
        bankName: String(bank.name ?? requestedBankName),
        bankCode,
        resolvedAccountName: maskedAccountHolderName(submittedAccountName),
        accountLast4: account.slice(-4),
        accountFingerprint: fingerprint,
        identityFingerprint: documentFingerprint,
        accountType: identity.accountType,
        documentType: identity.documentType,
        paystackSubaccountCode: subaccountCode,
        paystackSubaccountId: String(subaccount.id ?? ""),
        paystackSubaccountVerified: subaccount.is_verified === true,
        verificationFlags: flags,
      };
      const auditId = stableDocumentId("audit", [
        merchantId,
        uid,
        fingerprint,
        claimId,
      ]);
      await db.runTransaction(async (tx) => {
        const current = await tx.get(profileRef!);
        const previous = current.data() ?? {};
        if (previous.validationAttemptClaimId !== claimId) {
          throw new functions.https.HttpsError(
            "aborted",
            "The verification attempt was superseded.",
          );
        }
        const now = FieldValue.serverTimestamp();
        const capabilities =
          (previous.capabilities as Record<string, boolean> | undefined) ?? {};
        const update: Record<string, unknown> = {
          merchantId,
          status: "pending_review",
          capabilities,
          submittedBy: uid,
          submittedAt: now,
          validationAttemptState: "completed",
          validationAttemptLeaseUntilMs: 0,
          schemaVersion: 2,
          updatedAt: now,
        };
        update.pendingSettlement = {
          ...settlement,
          replacesAccountFingerprint: previous.accountFingerprint ?? null,
          submittedAt: now,
        };
        if (!hadActiveAccount) {
          update.bankVerificationStatus = "pending_review";
        }
        tx.set(profileRef!, update, { merge: true });
        tx.set(
          settlementAdminRequestRef(merchantId),
          {
            status: "pending_review",
            accountFingerprint: fingerprint,
            updatedAt: now,
          },
          { merge: true },
        );
        tx.create(profileRef!.collection("audit").doc(auditId), {
          auditId,
          merchantId,
          actorUid: uid,
          action: "settlement_profile_submitted",
          previousAccountFingerprint: previous.accountFingerprint ?? null,
          accountFingerprint: fingerprint,
          bankName: settlement.bankName,
          accountLast4: settlement.accountLast4,
          verificationFlags: flags,
          createdAt: now,
        });
      });
      res.status(200).json(
        profileSummary({
          merchantId,
          status: "pending_review",
          bankName: settlement.bankName,
          accountName: settlement.resolvedAccountName,
          accountLast4: settlement.accountLast4,
          accountFingerprint: fingerprint,
          deduped: false,
          autoApproved: false,
        }),
      );
    } catch (error) {
      const code = error instanceof Error ? error.message : "unknown";
      let responseError = error;
      if (profileRef && claimId && claimAcquired) {
        const providerOutcomeUnknown = providerStage === "creating_subaccount";
        await profileRef
          .set(
            {
              validationAttemptState: providerOutcomeUnknown
                ? "provider_outcome_unknown"
                : "failed",
              validationAttemptFailureCode: code.slice(0, 120),
              validationAttemptLeaseUntilMs: 0,
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          )
          .catch(() => undefined);
        if (providerOutcomeUnknown && code !== "PAYSTACK_SUBACCOUNT_INVALID") {
          responseError = new Error("BANK_VALIDATION_OUTCOME_UNKNOWN");
        }
      }
      console.error("[payments-v2] settlement profile preparation failed", {
        code:
          responseError instanceof Error ? responseError.message : "unknown",
        stage: providerStage,
      });
      const response = publicError(responseError);
      res.status(response.status).json({ error: response.message });
    }
  });

type SettlementReviewOutcome = "approve" | "changes_required" | "reject";

export function settlementReviewOutcome(input: {
  outcome?: unknown;
  approved?: unknown;
}): SettlementReviewOutcome | null {
  if (
    input.outcome === "approve" ||
    input.outcome === "changes_required" ||
    input.outcome === "reject"
  ) {
    return input.outcome;
  }
  return typeof input.approved === "boolean"
    ? input.approved
      ? "approve"
      : "reject"
    : null;
}

async function applySettlementProfileReview(input: {
  adminUid: string;
  merchantId: string;
  expectedFingerprint: string;
  outcome: SettlementReviewOutcome;
  reason: string;
  operationId: string;
}): Promise<{
  merchantId: string;
  bankVerificationStatus: string;
  deduped: boolean;
}> {
  const adminUid = input.adminUid;
  const merchantId = requireStoreId(input.merchantId);
  const expectedFingerprint = input.expectedFingerprint;
  if (!/^[a-f0-9]{64}$/.test(expectedFingerprint)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "The reviewed account fingerprint is required.",
    );
  }
  const approved = input.outcome === "approve";
  const reason = String(input.reason).trim().slice(0, 500);
  if (!reason) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "An audit reason is required.",
    );
  }
  const operationId = String(input.operationId).trim();
  if (!/^[A-Za-z0-9:_-]{1,120}$/.test(operationId)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid operationId is required.",
    );
  }
  const profileRef = db.doc(`merchantPaymentProfiles/${merchantId}`);
  const requestRef = settlementAdminRequestRef(merchantId);
  const auditId = stableDocumentId("audit", [
    "settlement_profile_review",
    adminUid,
    operationId,
  ]);
  const administrationAuditRef = db.doc(
    `paymentAdministrationAudit/${auditId}`,
  );
  const notificationId = stableDocumentId("payment_verification_notification", [
    auditId,
  ]);
  const priorAudit = await administrationAuditRef.get();
  if (priorAudit.exists) {
    const prior = priorAudit.data() ?? {};
    const priorOutcome = String(
      prior.outcome ?? (prior.approved === true ? "approve" : "reject"),
    );
    if (
      prior.merchantId !== merchantId ||
      priorOutcome !== input.outcome ||
      prior.accountFingerprint !== expectedFingerprint ||
      prior.reason !== reason
    ) {
      throw new functions.https.HttpsError(
        "already-exists",
        "That operationId is already bound to another settlement review.",
      );
    }
    return {
      merchantId,
      bankVerificationStatus: String(
        prior.bankVerificationStatus ?? (approved ? "approved" : input.outcome),
      ),
      deduped: true,
    };
  }
  const reviewClaimId = randomUUID();
  let claimedProfile: Record<string, unknown> = {};
  await db.runTransaction(async (tx) => {
    const profile = await tx.get(profileRef);
    const current = profile.data() ?? {};
    const pending = (current.pendingSettlement ?? {}) as Record<
      string,
      unknown
    >;
    if (!profile.exists || current.status !== "pending_review") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "This settlement profile is not awaiting review.",
      );
    }
    if (pending.accountFingerprint !== expectedFingerprint) {
      throw new functions.https.HttpsError(
        "aborted",
        "The banking destination changed during review.",
      );
    }
    if (
      current.bankReviewState === "processing" &&
      Number(current.bankReviewLeaseUntilMs ?? 0) > Date.now()
    ) {
      throw new functions.https.HttpsError(
        "aborted",
        "This settlement review is already processing.",
      );
    }
    claimedProfile = current;
    tx.update(profileRef, {
      bankReviewState: "processing",
      bankReviewClaimId: reviewClaimId,
      bankReviewLeaseUntilMs: Date.now() + 60_000,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  const pending = (claimedProfile.pendingSettlement ?? {}) as Record<
    string,
    unknown
  >;
  const pendingSubaccountCode = String(pending.paystackSubaccountCode ?? "");
  const currentSubaccountCode = String(
    claimedProfile.paystackSubaccountCode ?? "",
  );
  if (!/^ACCT_[A-Za-z0-9]+$/.test(pendingSubaccountCode)) {
    await profileRef.set(
      {
        bankReviewState: "invalid_pending_destination",
        bankReviewLeaseUntilMs: 0,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    throw new functions.https.HttpsError(
      "failed-precondition",
      "The pending Paystack settlement destination is invalid.",
    );
  }
  if (approved && /^ACCT_[A-Za-z0-9]+$/.test(currentSubaccountCode)) {
    const [settlements, paymentIntents] = await Promise.all([
      db
        .collection("settlements")
        .where("subaccountCode", "==", currentSubaccountCode)
        .limit(1001)
        .get(),
      db
        .collection("paymentIntents")
        .where("paystackSubaccountCode", "==", currentSubaccountCode)
        .limit(1001)
        .get(),
    ]);
    const retirement = settlementDestinationRetirementDecision({
      settlementStatuses: settlements.docs.map((doc) =>
        String(doc.get("status") ?? ""),
      ),
      paymentIntentStatuses: paymentIntents.docs.map((doc) =>
        String(doc.get("status") ?? ""),
      ),
      settlementWindowComplete: settlements.size <= 1000,
      paymentIntentWindowComplete: paymentIntents.size <= 1000,
    });
    if (retirement.reason === "history_truncated") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Settlement history is too large for a safe destination change. Run reconciliation first.",
      );
    }
    if (!retirement.safe) {
      await profileRef.set(
        {
          bankReviewState:
            retirement.reason === "in_flight_payment"
              ? "blocked_in_flight_payment"
              : "blocked_pending_settlement",
          bankReviewLeaseUntilMs: 0,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      throw new functions.https.HttpsError(
        "failed-precondition",
        retirement.reason === "in_flight_payment"
          ? "The old destination still has an in-flight payment. Expire or reconcile it before approval."
          : "The old destination still has a pending settlement. Reconcile it before approval.",
      );
    }
  }
  const secret = paystackSecret();
  try {
    if (
      approved &&
      /^ACCT_[A-Za-z0-9]+$/.test(currentSubaccountCode) &&
      currentSubaccountCode !== pendingSubaccountCode
    ) {
      await setPaystackSubaccountActive(secret, currentSubaccountCode, false);
    }
    await setPaystackSubaccountActive(secret, pendingSubaccountCode, approved);
  } catch (error) {
    await profileRef.set(
      {
        bankReviewState: "provider_outcome_unknown",
        bankReviewLeaseUntilMs: 0,
        bankReviewFailureCode: paystackSafeProviderCode(error),
        status: "pending_review",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    throw new functions.https.HttpsError(
      "unavailable",
      "Paystack did not confirm the destination change. Operations must reconcile it before retrying.",
    );
  }
  let resultStatus = approved ? "approved" : input.outcome;
  await db.runTransaction(async (tx) => {
    const [profile, administrationAudit] = await Promise.all([
      tx.get(profileRef),
      tx.get(administrationAuditRef),
    ]);
    if (administrationAudit.exists) {
      throw new functions.https.HttpsError(
        "aborted",
        "This settlement review completed in another session. Refresh the queue.",
      );
    }
    const current = profile.data() ?? {};
    const pending = (current.pendingSettlement ?? {}) as Record<
      string,
      unknown
    >;
    if (!profile.exists || current.status !== "pending_review") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "This settlement profile is not awaiting review.",
      );
    }
    if (pending.accountFingerprint !== expectedFingerprint) {
      throw new functions.https.HttpsError(
        "aborted",
        "The banking destination changed during review.",
      );
    }
    if (current.bankReviewClaimId !== reviewClaimId) {
      throw new functions.https.HttpsError(
        "aborted",
        "The settlement review was superseded.",
      );
    }
    const now = FieldValue.serverTimestamp();
    const hasPreviousActive = activeSubaccount(current);
    if (approved) {
      const capabilities = {
        ...((current.capabilities as Record<string, boolean> | undefined) ??
          {}),
        ...Object.fromEntries(
          SETTLEMENT_CAPABILITIES.map((purpose) => [purpose, true]),
        ),
      };
      tx.update(profileRef, {
        ...pending,
        status: "enabled",
        capabilities,
        bankVerificationStatus: "approved",
        bankAutoApproved: false,
        bankReviewedBy: adminUid,
        bankReviewedAt: now,
        bankReviewReason: reason,
        bankReviewState: "completed",
        bankReviewLeaseUntilMs: 0,
        pendingSettlement: FieldValue.delete(),
        updatedAt: now,
      });
    } else {
      resultStatus = hasPreviousActive ? "approved" : input.outcome;
      tx.update(profileRef, {
        status: hasPreviousActive ? "enabled" : "not_started",
        bankVerificationStatus: resultStatus,
        bankReviewedBy: adminUid,
        bankReviewedAt: now,
        bankReviewReason: reason,
        bankReviewState: "completed",
        bankReviewLeaseUntilMs: 0,
        pendingSettlement: FieldValue.delete(),
        updatedAt: now,
      });
    }
    tx.create(profileRef.collection("audit").doc(auditId), {
      auditId,
      merchantId,
      actorUid: adminUid,
      action:
        input.outcome === "approve"
          ? "settlement_profile_approved"
          : input.outcome === "changes_required"
            ? "settlement_profile_changes_required"
            : "settlement_profile_rejected",
      accountFingerprint: expectedFingerprint,
      restoredPreviousDestination: !approved && hasPreviousActive,
      reason,
      createdAt: now,
    });
    tx.set(
      requestRef,
      {
        status: input.outcome === "approve" ? "approved" : input.outcome,
        updatedAt: now,
      },
      { merge: true },
    );
    tx.create(administrationAuditRef, {
      auditId,
      action:
        input.outcome === "approve"
          ? "settlement_profile_approved"
          : input.outcome === "changes_required"
            ? "settlement_profile_changes_required"
            : "settlement_profile_rejected",
      merchantId,
      actorUid: adminUid,
      operationId,
      approved,
      outcome: input.outcome,
      accountFingerprint: expectedFingerprint,
      bankVerificationStatus: resultStatus,
      reason,
      createdAt: now,
      schemaVersion: 2,
    });
    const notificationCopy = settlementReviewNotificationCopy(input.outcome);
    tx.set(
      db.doc(`users/${merchantId}/notifications/${notificationId}`),
      {
        notificationId,
        type: "PAYMENT_VERIFICATION",
        outcome: input.outcome,
        title: notificationCopy.title,
        body: notificationCopy.body,
        route: "/walletPage?destination=online_payments",
        read: false,
        idempotencyKey: notificationId,
        source: "settlementReview",
        pushDeliveryState: "pending",
        createdAt: now,
        schemaVersion: 1,
      },
      { merge: true },
    );
  });
  await deliverSettlementReviewNotification({
    merchantId,
    notificationId,
    outcome: input.outcome,
  }).catch((error) => {
    console.error("[payments-v2] settlement review notification queued", {
      notificationId,
      code: error instanceof Error ? error.name : "unknown",
    });
  });
  return {
    merchantId,
    bankVerificationStatus: resultStatus,
    deduped: false,
  };
}

function requireSettlementReviewInput(data: unknown): {
  outcome: SettlementReviewOutcome;
  reason: string;
  operationId: string;
} {
  const value =
    data && typeof data === "object" ? (data as Record<string, unknown>) : {};
  const outcome = settlementReviewOutcome(value);
  if (!outcome) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Choose a valid settlement review outcome.",
    );
  }
  const reason = String(value.reason ?? "")
    .trim()
    .slice(0, 500);
  const operationId = String(value.operationId ?? "").trim();
  return { outcome, reason, operationId };
}

export const reviewMerchantSettlementProfileV2 = functions
  .runWith({
    secrets: ["PAYSTACK_SECRET_KEY"],
    enforceAppCheck: true,
    consumeAppCheckToken: true,
  })
  .https.onCall(async (data, context) => {
    const adminUid = requirePaymentAdmin(context);
    const input = requireSettlementReviewInput(data);
    return applySettlementProfileReview({
      adminUid,
      merchantId: requireStoreId(data?.merchantId),
      expectedFingerprint: String(data?.accountFingerprint ?? "").trim(),
      ...input,
    });
  });

export const reviewSettlementVerificationRequestV1 = functions
  .runWith({
    secrets: ["PAYSTACK_SECRET_KEY"],
    enforceAppCheck: true,
    consumeAppCheckToken: true,
  })
  .https.onCall(async (data, context) => {
    const adminUid = requirePaymentAdmin(context);
    const input = requireSettlementReviewInput(data);
    const requestId = String(data?.requestId ?? "").trim();
    if (!/^[A-Za-z0-9:_-]{1,120}$/.test(requestId)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid requestId is required.",
      );
    }
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
    const merchantId = requireStoreId(requestData.merchantId);
    if (settlementAdminRequestRef(merchantId).id !== requestId) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Settlement request identity is invalid.",
      );
    }
    const expectedFingerprint = String(
      requestData.accountFingerprint ?? "",
    ).trim();
    const result = await applySettlementProfileReview({
      adminUid,
      merchantId,
      expectedFingerprint,
      ...input,
    });
    return {
      requestId,
      bankVerificationStatus: result.bankVerificationStatus,
      outcome: input.outcome,
      deduped: result.deduped,
    };
  });
