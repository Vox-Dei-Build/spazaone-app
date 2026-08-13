import axios from "axios";
import { createHash, createHmac, randomUUID } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import { paystackSecret } from "../../config/environment";
import { authenticateFirebaseRequest } from "../../security/requestAuth";
import { assertStoreAccess, requireStoreId } from "../../stores/storeAccess";
import { PaymentPurpose, stableDocumentId } from "./domain";

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

function normalizedName(value: unknown): string {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

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
      "Settlement verification needs Spaza One approval before it can start.",
    ],
    BANK_VALIDATION_PREAUTH_EXPIRED: [
      403,
      "The settlement-verification approval expired. Contact support to continue.",
    ],
    BANK_VALIDATION_PREAUTH_CONSUMED: [
      403,
      "The approved settlement-verification attempts were used. Contact support to continue.",
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
    merchantId: input.merchantId,
    status: input.status,
    bankName: String(input.bankName ?? ""),
    resolvedAccountName: String(input.accountName ?? ""),
    maskedAccount: input.accountLast4
      ? `•••• ${String(input.accountLast4)}`
      : "",
    accountFingerprint: input.accountFingerprint,
    deduped: input.deduped,
    autoApproved: input.autoApproved === true,
  };
}

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
      profileRef = db.doc(`merchantPaymentProfiles/${merchantId}`);
      const existing = await profileRef.get();
      const existingData = existing.data() ?? {};
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
        });
      if (!initialAuthorizationDecision.allowed) {
        throw new Error(initialAuthorizationDecision.reason);
      }
      const raw = banking.data() ?? {};
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
      const secret = paystackSecret();
      const banksResponse = await axios.get("https://api.paystack.co/bank", {
        headers: { Authorization: `Bearer ${secret}` },
        params: {
          country: "south africa",
          currency: "ZAR",
          enabled_for_verification: true,
          perPage: 200,
        },
        timeout: 15_000,
      });
      const banks = Array.isArray(banksResponse.data?.data)
        ? banksResponse.data.data
        : [];
      const requestedBranchCode = String(raw.branchCode ?? "").replace(
        /\s/g,
        "",
      );
      const bank = banks.find((candidate: any) => {
        const candidateCode = String(candidate?.code ?? "").replace(/\s/g, "");
        return (
          (requestedBranchCode && candidateCode === requestedBranchCode) ||
          normalizedName(candidate?.name) === normalizedName(requestedBankName)
        );
      });
      const bankCode = String(bank?.code ?? "").trim();
      if (!bankCode || bank?.enabled_for_verification === false) {
        throw new Error("BANK_NOT_SUPPORTED");
      }
      const fingerprint = accountFingerprint(secret, bankCode, account);
      const documentFingerprint = protectedIdentityFingerprint(
        secret,
        identity,
      );
      const attemptFingerprint = sha256([fingerprint, documentFingerprint]);
      const pending = (existingData.pendingSettlement ?? {}) as Record<
        string,
        unknown
      >;
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

export const reviewMerchantSettlementProfileV2 = functions
  .runWith({ secrets: ["PAYSTACK_SECRET_KEY"] })
  .https.onCall(async (data, context) => {
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
    const adminUid = context.auth.uid;
    const merchantId = requireStoreId(data?.merchantId);
    const expectedFingerprint = String(data?.accountFingerprint ?? "").trim();
    if (!/^[a-f0-9]{64}$/.test(expectedFingerprint)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "The reviewed account fingerprint is required.",
      );
    }
    const approved = data?.approved === true;
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
      await setPaystackSubaccountActive(
        secret,
        pendingSubaccountCode,
        approved,
      );
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
    const auditId = stableDocumentId("audit", [
      merchantId,
      adminUid,
      approved ? "approved" : "rejected",
      expectedFingerprint,
      String(Date.now()),
    ]);
    let resultStatus = approved ? "approved" : "rejected";
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
        resultStatus = hasPreviousActive ? "approved" : "rejected";
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
        action: approved
          ? "settlement_profile_approved"
          : "settlement_profile_rejected",
        accountFingerprint: expectedFingerprint,
        restoredPreviousDestination: !approved && hasPreviousActive,
        reason,
        createdAt: now,
      });
    });
    return {
      merchantId,
      bankVerificationStatus: resultStatus,
    };
  });
