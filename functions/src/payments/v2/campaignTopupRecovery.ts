import axios from "axios";
import { createHash } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import { paystackPaymentSecret } from "../../config/environment";
import { requireStoreId } from "../../stores/storeAccess";
import { applyVerifiedCampaignTopupV2 } from "./campaignTopup";
import { providerEventDocumentId } from "./financialCore";
import { requirePaymentAdmin } from "./paymentAdminAuth";

const RECOVERY_ACTION = "verify_and_apply_campaign_topup";
const PROCESSING_LEASE_MS = 60_000;
type UnknownRecord = Record<string, unknown>;

type RecoveryInput = {
  intentId: unknown;
  operationId: unknown;
  reason: unknown;
  actorUid: string;
};

type RecoveryResult = {
  operationId: string;
  intentId: string;
  eventId: string;
  deduped: boolean;
};

type RecoveryDependencies = {
  verifyTransaction?: (input: {
    reference: string;
    merchantId: string;
  }) => Promise<UnknownRecord>;
  nowMs?: () => number;
};

type ClaimedRecovery = {
  completed: false;
  merchantId: string;
  reference: string;
};

type CompletedRecovery = {
  completed: true;
  result: RecoveryResult;
};

function requireIntentId(value: unknown): string {
  const intentId = String(value ?? "").trim();
  if (!/^pi_[a-f0-9]{64}$/.test(intentId)) {
    throw new Error("INTENT_ID_INVALID");
  }
  return intentId;
}

function requireOperationId(value: unknown): string {
  const operationId = String(value ?? "").trim();
  if (!/^[A-Za-z0-9:_-]{1,120}$/.test(operationId)) {
    throw new Error("OPERATION_ID_INVALID");
  }
  return operationId;
}

function requireActorUid(value: unknown): string {
  const actorUid = String(value ?? "").trim();
  if (!/^[A-Za-z0-9:_-]{1,200}$/.test(actorUid)) {
    throw new Error("ACTOR_UID_INVALID");
  }
  return actorUid;
}

function requireReason(value: unknown): string {
  const reason = String(value ?? "").trim();
  if (!reason || reason.length > 500) {
    throw new Error("RECOVERY_REASON_INVALID");
  }
  return reason;
}

function reasonDigest(reason: string): string {
  return createHash("sha256").update(reason).digest("hex");
}

function asRecord(value: unknown): UnknownRecord {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? (value as UnknownRecord)
    : {};
}

function safeFailureCode(error: unknown): string {
  const code = error instanceof Error ? error.message : "";
  const allowed = new Set([
    "PAYSTACK_PROVIDER_DISABLED",
    "PAYSTACK_SECRET_MISSING",
    "PAYSTACK_TEST_KEY_REQUIRED",
    "PAYSTACK_LIVE_KEY_REQUIRED",
    "PROVIDER_VERIFY_FAILED",
    "PROVIDER_TRANSACTION_NOT_SUCCESSFUL",
    "PROVIDER_CURRENCY_MISMATCH",
    "PROVIDER_TRANSACTION_ID_INVALID",
    "CAMPAIGN_TOPUP_BINDING_MISMATCH",
    "CAMPAIGN_TOPUP_CREDIT_MISMATCH",
    "CAMPAIGN_TOPUP_STATUS_INVALID",
    "CAMPAIGN_TOPUP_IDEMPOTENCY_COLLISION",
    "TOPUP_CHANNEL_MISMATCH",
    "PROVIDER_AMOUNT_MISMATCH",
    "PROVIDER_FEE_INVALID",
    "PROVIDER_EVENT_COLLISION",
  ]);
  return allowed.has(code) ? code : "CAMPAIGN_TOPUP_RECOVERY_FAILED";
}

function canonicalTransaction(transaction: UnknownRecord): UnknownRecord {
  const metadata = asRecord(transaction.metadata);
  return {
    id: transaction.id,
    status: String(transaction.status ?? ""),
    reference: String(transaction.reference ?? ""),
    amount: Number(transaction.amount),
    fees: Number(transaction.fees ?? 0),
    channel: String(transaction.channel ?? ""),
    currency: String(transaction.currency ?? "").toUpperCase(),
    paid_at: String(transaction.paid_at ?? ""),
    metadata: {
      purpose: String(metadata.purpose ?? ""),
      intentId: String(metadata.intentId ?? ""),
      merchantId: String(metadata.merchantId ?? ""),
      walletStoreId: String(metadata.walletStoreId ?? ""),
      creditAmountMinor: Number(metadata.creditAmountMinor),
      selectedChannel: String(metadata.selectedChannel ?? ""),
      initiatedBy: String(metadata.initiatedBy ?? ""),
    },
  };
}

async function verifyPaystackTransaction(input: {
  reference: string;
  merchantId: string;
}): Promise<UnknownRecord> {
  const secret = paystackPaymentSecret({
    merchantId: input.merchantId,
    purpose: "campaign_credit",
  });
  const response = await axios.get(
    `https://api.paystack.co/transaction/verify/${encodeURIComponent(
      input.reference,
    )}`,
    {
      headers: { Authorization: `Bearer ${secret}` },
      timeout: 15_000,
    },
  );
  const payload = asRecord(response.data);
  const transaction = asRecord(payload.data);
  if (payload.status !== true) {
    throw new Error("PROVIDER_VERIFY_FAILED");
  }
  if (
    transaction.status !== "success" ||
    String(transaction.reference ?? "") !== input.reference
  ) {
    throw new Error("PROVIDER_TRANSACTION_NOT_SUCCESSFUL");
  }
  return transaction;
}

function requireRecoveryIntent(data: UnknownRecord): {
  merchantId: string;
  reference: string;
} {
  const businessBinding = asRecord(data.businessBinding);
  if (
    data.purpose !== "campaign_credit" ||
    businessBinding.type !== "campaign_wallet" ||
    data.provider !== "paystack" ||
    !["initialized", "pending", "paid"].includes(String(data.status ?? ""))
  ) {
    throw new Error("RECOVERY_INTENT_NOT_ELIGIBLE");
  }
  const merchantId = requireStoreId(data.merchantId);
  const reference = String(data.providerReference ?? "").trim();
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(reference)) {
    throw new Error("RECOVERY_REFERENCE_INVALID");
  }
  return { merchantId, reference };
}

async function claimRecovery(input: {
  intentId: string;
  operationId: string;
  actorUid: string;
  reason: string;
  nowMs: number;
}): Promise<ClaimedRecovery | CompletedRecovery> {
  const operationRef = db.doc(`paymentRecoveryOperations/${input.operationId}`);
  const intentRef = db.doc(`paymentIntents/${input.intentId}`);
  return db.runTransaction(async (tx) => {
    const [operation, intent] = await Promise.all([
      tx.get(operationRef),
      tx.get(intentRef),
    ]);
    if (!intent.exists) throw new Error("INTENT_NOT_FOUND");
    const binding = requireRecoveryIntent(intent.data() ?? {});
    const digest = reasonDigest(input.reason);
    if (operation.exists) {
      const previous = operation.data() ?? {};
      if (
        previous.action !== RECOVERY_ACTION ||
        previous.intentId !== input.intentId ||
        previous.actorUid !== input.actorUid ||
        previous.reasonDigest !== digest
      ) {
        throw new Error("RECOVERY_OPERATION_COLLISION");
      }
      if (previous.status === "complete") {
        return {
          completed: true,
          result: {
            operationId: input.operationId,
            intentId: input.intentId,
            eventId: String(previous.eventId ?? ""),
            deduped: true,
          },
        };
      }
      if (
        previous.status === "processing" &&
        Number(previous.leaseUntilMs ?? 0) > input.nowMs
      ) {
        throw new Error("RECOVERY_OPERATION_IN_PROGRESS");
      }
      tx.update(operationRef, {
        status: "processing",
        attempts: FieldValue.increment(1),
        leaseUntilMs: input.nowMs + PROCESSING_LEASE_MS,
        failureCode: null,
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      tx.create(operationRef, {
        operationId: input.operationId,
        action: RECOVERY_ACTION,
        intentId: input.intentId,
        actorUid: input.actorUid,
        reason: input.reason,
        reasonDigest: digest,
        status: "processing",
        attempts: 1,
        leaseUntilMs: input.nowMs + PROCESSING_LEASE_MS,
        schemaVersion: 2,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    return { completed: false, ...binding };
  });
}

function assertVerifiedTransaction(input: {
  transaction: UnknownRecord;
  reference: string;
}): void {
  if (
    input.transaction.status !== "success" ||
    String(input.transaction.reference ?? "") !== input.reference
  ) {
    throw new Error("PROVIDER_TRANSACTION_NOT_SUCCESSFUL");
  }
  if (String(input.transaction.currency ?? "").toUpperCase() !== "ZAR") {
    throw new Error("PROVIDER_CURRENCY_MISMATCH");
  }
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(String(input.transaction.id ?? ""))) {
    throw new Error("PROVIDER_TRANSACTION_ID_INVALID");
  }
}

export async function recoverCampaignTopupV2(
  untrustedInput: RecoveryInput,
  dependencies: RecoveryDependencies = {},
): Promise<RecoveryResult> {
  const intentId = requireIntentId(untrustedInput.intentId);
  const operationId = requireOperationId(untrustedInput.operationId);
  const actorUid = requireActorUid(untrustedInput.actorUid);
  const reason = requireReason(untrustedInput.reason);
  const nowMs = (dependencies.nowMs ?? Date.now)();
  const operationRef = db.doc(`paymentRecoveryOperations/${operationId}`);
  const claim = await claimRecovery({
    intentId,
    operationId,
    actorUid,
    reason,
    nowMs,
  });
  if (claim.completed) return claim.result;

  try {
    const verified = await (
      dependencies.verifyTransaction ?? verifyPaystackTransaction
    )({ reference: claim.reference, merchantId: claim.merchantId });
    assertVerifiedTransaction({
      transaction: verified,
      reference: claim.reference,
    });
    const transaction = canonicalTransaction(verified);
    const rawBody = Buffer.from(JSON.stringify(transaction));
    const providerEventId = `recovery-charge-${String(transaction.id)}`;
    const eventId = providerEventDocumentId({
      provider: "paystack",
      providerEventId,
      eventType: "charge.success",
      reference: claim.reference,
      rawBody,
      intentId,
      ingestionSource: "admin_provider_verify",
    });
    const applied = await applyVerifiedCampaignTopupV2(transaction, rawBody, {
      providerEventId,
      ingestionSource: "admin_provider_verify",
    });
    await operationRef.update({
      status: "complete",
      leaseUntilMs: 0,
      eventId,
      applicationDeduped: applied.deduped,
      failureCode: null,
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { operationId, intentId, eventId, deduped: applied.deduped };
  } catch (error) {
    await operationRef
      .update({
        status: "failed",
        leaseUntilMs: 0,
        failureCode: safeFailureCode(error),
        failedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      })
      .catch(() => undefined);
    throw error;
  }
}

function callableError(error: unknown): never {
  const code = error instanceof Error ? error.message : "";
  if (
    [
      "INTENT_ID_INVALID",
      "OPERATION_ID_INVALID",
      "RECOVERY_REASON_INVALID",
    ].includes(code)
  ) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Provide a valid intent, operation ID and audit reason.",
    );
  }
  if (code === "INTENT_NOT_FOUND") {
    throw new functions.https.HttpsError("not-found", "Payment not found.");
  }
  if (code === "RECOVERY_OPERATION_COLLISION") {
    throw new functions.https.HttpsError(
      "already-exists",
      "That operation ID is already bound to another recovery.",
    );
  }
  if (code === "RECOVERY_OPERATION_IN_PROGRESS") {
    throw new functions.https.HttpsError(
      "aborted",
      "That recovery operation is already in progress.",
    );
  }
  if (
    [
      "RECOVERY_INTENT_NOT_ELIGIBLE",
      "RECOVERY_REFERENCE_INVALID",
      "PROVIDER_TRANSACTION_NOT_SUCCESSFUL",
      "PROVIDER_CURRENCY_MISMATCH",
      "CAMPAIGN_TOPUP_BINDING_MISMATCH",
      "CAMPAIGN_TOPUP_CREDIT_MISMATCH",
      "CAMPAIGN_TOPUP_STATUS_INVALID",
      "CAMPAIGN_TOPUP_IDEMPOTENCY_COLLISION",
      "TOPUP_CHANNEL_MISMATCH",
      "PROVIDER_AMOUNT_MISMATCH",
    ].includes(code)
  ) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "The verified payment could not be safely applied to this intent.",
    );
  }
  throw new functions.https.HttpsError(
    "internal",
    "The payment recovery could not be completed.",
  );
}

export const recoverCampaignTopupV2OnDemand = functions
  .runWith({
    secrets: ["PAYSTACK_SECRET_KEY"],
    enforceAppCheck: true,
    consumeAppCheckToken: true,
  })
  .https.onCall(async (data, context) => {
    const actorUid = requirePaymentAdmin(context);
    try {
      return await recoverCampaignTopupV2({
        intentId: data?.intentId,
        operationId: data?.operationId,
        reason: data?.reason,
        actorUid,
      });
    } catch (error) {
      return callableError(error);
    }
  });
