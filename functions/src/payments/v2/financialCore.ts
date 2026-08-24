import { createHash } from "crypto";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db } from "../../config/main";
import {
  assertMoneySnapshot,
  assertPaymentTransition,
  isPaymentPurpose,
  isPaymentStatus,
  MoneySnapshot,
  PaymentPurpose,
  PaymentStatus,
  requireMinorUnits,
  requirePositiveMinorUnits,
  stableDocumentId,
} from "./domain";

export type NewPaymentIntent = {
  merchantId: string;
  purpose: PaymentPurpose;
  idempotencyKey: string;
  expectedAmountMinor: number;
  businessBinding: { type: string; id: string };
  money: MoneySnapshot;
  expiresAt?: Timestamp;
  initiatedBy?: string;
};

export type ProviderEventInput = {
  provider: "paystack";
  providerEventId?: string;
  eventType: string;
  reference: string;
  rawBody: Buffer;
  intentId?: string;
  ingestionSource?: "webhook" | "admin_provider_verify";
};

function requireId(value: unknown, field: string): string {
  const id = String(value ?? "").trim();
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(id)) throw new Error(`${field}_INVALID`);
  return id;
}

export function paymentIntentDocumentId(input: {
  merchantId: string;
  purpose: PaymentPurpose;
  idempotencyKey: string;
}): string {
  return stableDocumentId("pi", [
    requireId(input.merchantId, "MERCHANT_ID"),
    input.purpose,
    String(input.idempotencyKey).trim(),
  ]);
}

export function payloadDigest(rawBody: Buffer): string {
  return createHash("sha256").update(rawBody).digest("hex");
}

export function providerEventDocumentId(input: ProviderEventInput): string {
  const providerEventId = String(input.providerEventId ?? "").trim();
  return providerEventId
    ? stableDocumentId("pe", [input.provider, "provider_id", providerEventId])
    : stableDocumentId("pe", [
        input.provider,
        "fallback",
        input.eventType,
        input.reference,
      ]);
}

export async function createPaymentIntentV2(
  input: NewPaymentIntent,
): Promise<{ intentId: string; deduped: boolean }> {
  if (!isPaymentPurpose(input.purpose)) throw new Error("PURPOSE_INVALID");
  const merchantId = requireId(input.merchantId, "MERCHANT_ID");
  const expectedAmountMinor = requirePositiveMinorUnits(
    input.expectedAmountMinor,
    "expected_amount",
  );
  assertMoneySnapshot(input.money);
  if (input.money.grossAmountMinor !== expectedAmountMinor) {
    throw new Error("INTENT_MONEY_MISMATCH");
  }
  const bindingType = requireId(input.businessBinding.type, "BINDING_TYPE");
  const bindingId = requireId(input.businessBinding.id, "BINDING_ID");
  const intentId = paymentIntentDocumentId(input);
  const intentRef = db.doc(`paymentIntents/${intentId}`);
  let deduped = false;
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(intentRef);
    if (existing.exists) {
      const data = existing.data() ?? {};
      if (
        String(data.merchantId) !== merchantId ||
        String(data.purpose) !== input.purpose ||
        Number(data.expectedAmountMinor) !== expectedAmountMinor ||
        String(data.businessBinding?.type ?? "") !== bindingType ||
        String(data.businessBinding?.id ?? "") !== bindingId
      ) {
        throw new Error("IDEMPOTENCY_BINDING_MISMATCH");
      }
      deduped = true;
      return;
    }
    tx.create(intentRef, {
      intentId,
      correlationId: stableDocumentId("corr", [intentId]),
      merchantId,
      purpose: input.purpose,
      status: "created" satisfies PaymentStatus,
      expectedAmountMinor,
      currency: "ZAR",
      businessBinding: { type: bindingType, id: bindingId },
      money: input.money,
      idempotencyDigest: createHash("sha256")
        .update(input.idempotencyKey)
        .digest("hex"),
      initiatedBy: String(input.initiatedBy ?? "").trim() || null,
      appliedProviderEventIds: [],
      schemaVersion: 2,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      ...(input.expiresAt ? { expiresAt: input.expiresAt } : {}),
    });
  });
  return { intentId, deduped };
}

export async function recordProviderEventV2(
  input: ProviderEventInput,
): Promise<{ eventId: string; deduped: boolean }> {
  const reference = requireId(input.reference, "REFERENCE");
  const eventType = String(input.eventType ?? "")
    .trim()
    .slice(0, 120);
  if (!eventType) throw new Error("EVENT_TYPE_INVALID");
  const digest = payloadDigest(input.rawBody);
  const eventId = providerEventDocumentId(input);
  const eventRef = db.doc(`paymentEvents/${eventId}`);
  let deduped = false;
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(eventRef);
    if (existing.exists) {
      const data = existing.data() ?? {};
      const existingIngestionSource = String(data.ingestionSource ?? "");
      const requestedIngestionSource = String(input.ingestionSource ?? "");
      if (
        String(data.payloadDigest ?? "") !== digest ||
        String(data.reference ?? "") !== reference ||
        String(data.eventType ?? "") !== eventType ||
        (existingIngestionSource &&
          existingIngestionSource !== requestedIngestionSource) ||
        (!existingIngestionSource &&
          requestedIngestionSource === "admin_provider_verify")
      ) {
        throw new Error("PROVIDER_EVENT_COLLISION");
      }
      deduped = true;
      return;
    }
    tx.create(eventRef, {
      eventId,
      provider: input.provider,
      providerEventId: String(input.providerEventId ?? "").trim() || null,
      eventType,
      reference,
      payloadDigest: digest,
      payloadSizeBytes: input.rawBody.byteLength,
      intentId: String(input.intentId ?? "").trim() || null,
      ingestionSource: input.ingestionSource ?? null,
      processingState: "received",
      attemptCount: 0,
      schemaVersion: 2,
      receivedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { eventId, deduped };
}

export async function transitionPaymentIntentV2(input: {
  intentId: string;
  nextStatus: PaymentStatus;
  providerEventId?: string;
  providerReference?: string;
  providerAmountMinor?: number;
  providerFeeMinor?: number;
}): Promise<{ deduped: boolean }> {
  const intentId = requireId(input.intentId, "INTENT_ID");
  if (!isPaymentStatus(input.nextStatus)) throw new Error("STATUS_INVALID");
  const intentRef = db.doc(`paymentIntents/${intentId}`);
  let deduped = false;
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(intentRef);
    if (!snapshot.exists) throw new Error("INTENT_NOT_FOUND");
    const data = snapshot.data() ?? {};
    const current = String(data.status ?? "") as PaymentStatus;
    if (!isPaymentStatus(current)) throw new Error("INTENT_STATUS_INVALID");
    const applied = Array.isArray(data.appliedProviderEventIds)
      ? data.appliedProviderEventIds.map(String)
      : [];
    const eventId = String(input.providerEventId ?? "").trim();
    if (eventId && applied.includes(eventId)) {
      deduped = true;
      return;
    }
    assertPaymentTransition(current, input.nextStatus);
    const providerAmount =
      input.providerAmountMinor == null
        ? null
        : requirePositiveMinorUnits(
            input.providerAmountMinor,
            "provider_amount",
          );
    if (
      providerAmount != null &&
      providerAmount !== Number(data.expectedAmountMinor)
    ) {
      throw new Error("PROVIDER_AMOUNT_MISMATCH");
    }
    tx.update(intentRef, {
      status: input.nextStatus,
      previousStatus: current,
      ...(eventId
        ? { appliedProviderEventIds: FieldValue.arrayUnion(eventId) }
        : {}),
      ...(input.providerReference
        ? { providerReference: requireId(input.providerReference, "REFERENCE") }
        : {}),
      ...(providerAmount == null
        ? {}
        : { providerAmountMinor: providerAmount }),
      ...(input.providerFeeMinor == null
        ? {}
        : {
            providerFeeMinor: requireMinorUnits(
              input.providerFeeMinor,
              "provider_fee",
            ),
          }),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { deduped };
}
