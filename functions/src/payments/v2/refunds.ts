import axios from "axios";
import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import {
  paystackCanaryIntentBindingValid,
  paystackPaymentSecret,
  paystackProviderMode,
} from "../../config/environment";
import {
  campaignBalanceRef,
  campaignOperationRef,
  campaignWalletRef,
} from "../../wallet/campaignCredits";
import {
  isPaymentStatus,
  PaymentStatus,
  requirePositiveMinorUnits,
  stableDocumentId,
} from "./domain";
import {
  providerEventDocumentId,
  recordProviderEventV2,
} from "./financialCore";

function requireId(value: unknown, field: string): string {
  const id = String(value ?? "").trim();
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(id)) throw new Error(`${field}_INVALID`);
  return id;
}

function paymentSecretForIntent(
  intent: FirebaseFirestore.DocumentSnapshot,
): string {
  const paymentContext = {
    merchantId: requireId(intent.get("merchantId"), "MERCHANT_ID"),
    purpose: String(intent.get("purpose") ?? ""),
  };
  if (
    paystackProviderMode() === "disabled" &&
    !paystackCanaryIntentBindingValid({
      metadataMerchantId: paymentContext.merchantId,
      metadataPurpose: paymentContext.purpose,
      intentMerchantId: intent.get("merchantId"),
      intentPurpose: intent.get("purpose"),
      intentProviderMode: intent.get("providerMode"),
      intentActivationScope: intent.get("activationScope"),
    })
  ) {
    throw new Error("PAYSTACK_PROVIDER_DISABLED");
  }
  return paystackPaymentSecret(paymentContext);
}

function positiveQuantity(value: unknown): number {
  const result = Number(value);
  if (!Number.isSafeInteger(result) || result <= 0) {
    throw new Error("REFUND_INVENTORY_QUANTITY_INVALID");
  }
  return result;
}

export function refundCaseDocumentId(input: {
  intentId: string;
  idempotencyKey: string;
}): string {
  return stableDocumentId("rf", [
    requireId(input.intentId, "INTENT_ID"),
    String(input.idempotencyKey ?? "").trim(),
  ]);
}

type RefundCaseInput = {
  intentId: string;
  idempotencyKey: string;
  refundAmountMinor: number;
  reason: string;
  owner: string;
  commerceOrderId?: string;
};

/** Opens a refund case inside the caller's business-state transaction. */
export async function openRefundCaseInTransactionV2(
  tx: FirebaseFirestore.Transaction,
  input: RefundCaseInput,
): Promise<{ refundCaseId: string; deduped: boolean }> {
  const intentId = requireId(input.intentId, "INTENT_ID");
  const amount = requirePositiveMinorUnits(
    input.refundAmountMinor,
    "refund_amount",
  );
  const reason = String(input.reason ?? "")
    .trim()
    .slice(0, 500);
  const owner = String(input.owner ?? "")
    .trim()
    .slice(0, 120);
  if (!reason) throw new Error("REFUND_REASON_INVALID");
  if (!owner) throw new Error("REFUND_OWNER_INVALID");
  const refundCaseId = refundCaseDocumentId(input);
  const intentRef = db.doc(`paymentIntents/${intentId}`);
  const caseRef = db.doc(`refundCases/${refundCaseId}`);
  const [intent, existingCase] = await Promise.all([
    tx.get(intentRef),
    tx.get(caseRef),
  ]);
  if (!intent.exists) throw new Error("INTENT_NOT_FOUND");
  const intentData = intent.data() ?? {};
  if (existingCase.exists) {
    const data = existingCase.data() ?? {};
    if (
      String(data.intentId ?? "") !== intentId ||
      Number(data.refundAmountMinor) !== amount
    ) {
      throw new Error("REFUND_IDEMPOTENCY_MISMATCH");
    }
    return { refundCaseId, deduped: true };
  }
  const status = String(intentData.status ?? "") as PaymentStatus;
  if (
    !isPaymentStatus(status) ||
    !["paid", "refund_pending"].includes(status)
  ) {
    throw new Error("INTENT_NOT_REFUNDABLE");
  }
  const expected = requirePositiveMinorUnits(
    intentData.expectedAmountMinor,
    "expected_amount",
  );
  const confirmed = Number(intentData.confirmedRefundMinor ?? 0);
  const requested = Number(intentData.requestedRefundMinor ?? 0);
  if (
    !Number.isSafeInteger(confirmed) ||
    !Number.isSafeInteger(requested) ||
    confirmed < 0 ||
    requested < 0 ||
    confirmed + requested + amount > expected
  ) {
    throw new Error("REFUND_AMOUNT_EXCEEDS_REMAINING");
  }
  const now = FieldValue.serverTimestamp();
  tx.create(caseRef, {
    refundCaseId,
    intentId,
    commerceOrderId: input.commerceOrderId
      ? requireId(input.commerceOrderId, "ORDER_ID")
      : null,
    refundAmountMinor: amount,
    currency: "ZAR",
    status: "requested",
    provider: "paystack",
    providerConfirmed: false,
    reason,
    owner,
    attemptCount: 0,
    schemaVersion: 2,
    createdAt: now,
    updatedAt: now,
  });
  tx.update(intentRef, {
    status: "refund_pending",
    requestedRefundMinor: FieldValue.increment(amount),
    refundProviderConfirmed: false,
    updatedAt: now,
  });
  return { refundCaseId, deduped: false };
}

/**
 * Opens an immutable refund case. It deliberately does not mark money as
 * returned; the intent remains refund_pending until provider confirmation.
 */
export async function requestRefundCaseV2(
  input: RefundCaseInput,
): Promise<{ refundCaseId: string; deduped: boolean }> {
  return db.runTransaction((tx) => openRefundCaseInTransactionV2(tx, input));
}

/**
 * Quarantines a verified charge that cannot be bound safely to its intent.
 * The expected amount stays immutable; the exact provider charge is returned
 * and the mismatch remains visible to reconciliation.
 */
export async function quarantineVerifiedChargeV2(input: {
  transaction: Record<string, any>;
  rawBody: Buffer;
  reason: string;
}): Promise<{ refundCaseId: string; intentId: string; deduped: boolean }> {
  const metadata = input.transaction.metadata ?? {};
  const intentId = requireId(metadata.intentId, "INTENT_ID");
  const reference = requireId(input.transaction.reference, "REFERENCE");
  const amount = requirePositiveMinorUnits(input.transaction.amount, "amount");
  const providerId = String(input.transaction.id ?? "").trim();
  const eventInput = {
    provider: "paystack" as const,
    ...(providerId ? { providerEventId: `charge-${providerId}` } : {}),
    eventType: "charge.success",
    reference,
    rawBody: input.rawBody,
    intentId,
  };
  const recorded = await recordProviderEventV2(eventInput);
  const eventRef = db.doc(
    `paymentEvents/${providerEventDocumentId(eventInput)}`,
  );
  const intentRef = db.doc(`paymentIntents/${intentId}`);
  const refundCaseId = refundCaseDocumentId({
    intentId,
    idempotencyKey: `verified-charge-mismatch:${reference}`,
  });
  const caseRef = db.doc(`refundCases/${refundCaseId}`);
  let deduped = recorded.deduped;
  await db.runTransaction(async (tx) => {
    const [intent, event, existingCase] = await Promise.all([
      tx.get(intentRef),
      tx.get(eventRef),
      tx.get(caseRef),
    ]);
    if (!intent.exists || !event.exists) throw new Error("INTENT_NOT_FOUND");
    const intentData = intent.data() ?? {};
    if (String(intentData.providerReference ?? "") !== reference) {
      // The provider's independently verified reference remains the refund
      // target, while the mismatch is retained as audit evidence.
      if (!String(intentData.providerReference ?? "")) {
        throw new Error("INTENT_PROVIDER_REFERENCE_MISSING");
      }
    }
    if (existingCase.exists) {
      if (
        existingCase.get("intentId") !== intentId ||
        Number(existingCase.get("refundAmountMinor")) !== amount ||
        existingCase.get("providerReference") !== reference
      ) {
        throw new Error("REFUND_IDEMPOTENCY_MISMATCH");
      }
      deduped = true;
      return;
    }
    const now = FieldValue.serverTimestamp();
    tx.create(caseRef, {
      refundCaseId,
      intentId,
      refundAmountMinor: amount,
      currency: String(input.transaction.currency ?? "ZAR").toUpperCase(),
      status: "requested",
      provider: "paystack",
      providerReference: reference,
      providerConfirmed: false,
      exceptionCharge: true,
      reason: String(input.reason ?? "provider_verification_mismatch").slice(
        0,
        500,
      ),
      owner: "operations",
      attemptCount: 0,
      schemaVersion: 2,
      createdAt: now,
      updatedAt: now,
    });
    tx.update(intentRef, {
      status: "refund_pending",
      previousStatus: String(intentData.status ?? "initialized"),
      providerAmountMinor: amount,
      requestedRefundMinor: FieldValue.increment(amount),
      refundProviderConfirmed: false,
      mismatchCode: String(
        input.reason ?? "provider_verification_mismatch",
      ).slice(0, 120),
      appliedProviderEventIds: FieldValue.arrayUnion(eventRef.id),
      updatedAt: now,
    });
    tx.update(eventRef, {
      processingState: "quarantined_refund_pending",
      attemptCount: FieldValue.increment(1),
      processedAt: now,
      updatedAt: now,
    });
  });
  await executePaystackRefundV2(refundCaseId).catch(() => undefined);
  return { refundCaseId, intentId, deduped };
}

/**
 * Submits a requested refund without guessing after a timeout. Before every
 * POST it searches Paystack for a prior request bearing this immutable case
 * ID, so a function retry cannot create the same refund twice.
 */
export async function executePaystackRefundV2(
  refundCaseIdValue: unknown,
): Promise<{ deduped: boolean; providerRefundId: string; status: string }> {
  const refundCaseId = requireId(refundCaseIdValue, "REFUND_CASE_ID");
  const caseRef = db.doc(`refundCases/${refundCaseId}`);
  const claimId = stableDocumentId("claim", [refundCaseId, String(Date.now())]);
  const claimed = await db.runTransaction(async (tx) => {
    const refundCase = await tx.get(caseRef);
    if (!refundCase.exists) throw new Error("REFUND_CASE_NOT_FOUND");
    const data = refundCase.data() ?? {};
    const providerRefundId = String(data.providerRefundId ?? "").trim();
    if (providerRefundId) {
      return {
        deduped: true,
        providerRefundId,
        status: String(data.providerStatus ?? data.status ?? "pending"),
        data,
      };
    }
    if (
      data.submissionState === "processing" &&
      Number(data.submissionLeaseUntilMs ?? 0) > Date.now()
    ) {
      throw new Error("REFUND_SUBMISSION_IN_PROGRESS");
    }
    tx.update(caseRef, {
      submissionState: "processing",
      submissionClaimId: claimId,
      submissionLeaseUntilMs: Date.now() + 45_000,
      attemptCount: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { deduped: false, providerRefundId: "", status: "requested", data };
  });
  if (claimed.deduped) {
    return {
      deduped: true,
      providerRefundId: claimed.providerRefundId,
      status: claimed.status,
    };
  }
  const intentId = requireId(claimed.data.intentId, "INTENT_ID");
  const intent = await db.doc(`paymentIntents/${intentId}`).get();
  if (!intent.exists) throw new Error("INTENT_NOT_FOUND");
  const reference = requireId(
    claimed.data.providerReference ?? intent.get("providerReference"),
    "REFERENCE",
  );
  const amount = requirePositiveMinorUnits(
    claimed.data.refundAmountMinor,
    "refund_amount",
  );
  const marker = `Spaza One refund ${refundCaseId}`;
  const secret = paymentSecretForIntent(intent);
  try {
    const existing = await axios.get("https://api.paystack.co/refund", {
      headers: { Authorization: `Bearer ${secret}` },
      params: { transaction: reference, perPage: 100 },
      timeout: 15_000,
    });
    const refunds = Array.isArray(existing.data?.data)
      ? existing.data.data
      : [];
    let provider = refunds.find(
      (item: any) =>
        Number(item?.amount) === amount &&
        String(item?.merchant_note ?? "").includes(refundCaseId),
    );
    if (!provider) {
      const response = await axios.post(
        "https://api.paystack.co/refund",
        {
          transaction: reference,
          amount,
          currency: "ZAR",
          customer_note: "Your Spaza One payment is being returned.",
          merchant_note: marker,
        },
        {
          headers: { Authorization: `Bearer ${secret}` },
          timeout: 15_000,
        },
      );
      if (response.data?.status !== true)
        throw new Error("REFUND_SUBMIT_FAILED");
      provider = response.data?.data ?? {};
    }
    const providerRefundId = requireId(provider?.id, "PROVIDER_REFUND_ID");
    const providerStatus = String(provider?.status ?? "pending").toLowerCase();
    await db.runTransaction(async (tx) => {
      const current = await tx.get(caseRef);
      const data = current.data() ?? {};
      if (data.providerRefundId && data.providerRefundId !== providerRefundId) {
        throw new Error("REFUND_PROVIDER_IDENTITY_MISMATCH");
      }
      if (data.submissionClaimId !== claimId && !data.providerRefundId) {
        throw new Error("REFUND_SUBMISSION_CLAIM_LOST");
      }
      tx.update(caseRef, {
        status: "submitted",
        providerRefundId,
        providerReference: reference,
        providerStatus,
        submissionState: "completed",
        submissionLeaseUntilMs: 0,
        submittedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    return { deduped: false, providerRefundId, status: providerStatus };
  } catch (error) {
    await caseRef.set(
      {
        submissionState: "retry",
        submissionLeaseUntilMs: 0,
        submissionErrorCode:
          error instanceof Error ? error.message.slice(0, 120) : "unknown",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    throw error;
  }
}

/** Re-queries Paystack rather than trusting refund webhook fields. */
export async function reconcilePaystackRefundV2(
  refundCaseIdValue: unknown,
): Promise<{ status: string; confirmed: boolean }> {
  const refundCaseId = requireId(refundCaseIdValue, "REFUND_CASE_ID");
  const caseRef = db.doc(`refundCases/${refundCaseId}`);
  const refundCase = await caseRef.get();
  if (!refundCase.exists) throw new Error("REFUND_CASE_NOT_FOUND");
  const data = refundCase.data() ?? {};
  const intentId = requireId(data.intentId, "INTENT_ID");
  const intent = await db.doc(`paymentIntents/${intentId}`).get();
  if (!intent.exists) throw new Error("INTENT_NOT_FOUND");
  const providerRefundId = requireId(
    data.providerRefundId,
    "PROVIDER_REFUND_ID",
  );
  const response = await axios.get(
    `https://api.paystack.co/refund/${encodeURIComponent(providerRefundId)}`,
    {
      headers: {
        Authorization: `Bearer ${paymentSecretForIntent(intent)}`,
      },
      timeout: 15_000,
    },
  );
  if (response.data?.status !== true) throw new Error("REFUND_FETCH_FAILED");
  const provider = response.data?.data ?? {};
  const providerStatus = String(provider.status ?? "").toLowerCase();
  if (providerStatus === "processed") {
    await confirmProviderRefundV2({
      refundCaseId,
      providerRefundId,
      providerReference: requireId(
        data.providerReference,
        "PROVIDER_REFERENCE",
      ),
      providerStatus,
      providerAmountMinor: requirePositiveMinorUnits(
        provider.amount,
        "provider_amount",
      ),
    });
    return { status: providerStatus, confirmed: true };
  }
  await caseRef.set(
    {
      providerStatus,
      status: providerStatus === "failed" ? "provider_failed" : "submitted",
      owner: "operations",
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { status: providerStatus, confirmed: false };
}

export async function handlePaystackRefundEventV2(
  event: Record<string, any>,
): Promise<{ matched: number }> {
  const data = event.data ?? {};
  const reference = requireId(
    data.transaction_reference ?? data.transaction?.reference,
    "PROVIDER_REFERENCE",
  );
  const cases = await db
    .collection("refundCases")
    .where("providerReference", "==", reference)
    .limit(20)
    .get();
  await Promise.all(cases.docs.map((doc) => reconcilePaystackRefundV2(doc.id)));
  return { matched: cases.size };
}

export const retryPaystackRefundsV2 = functions
  .runWith({ secrets: ["PAYSTACK_SECRET_KEY"] })
  .pubsub.schedule("every 5 minutes")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    const requested = await db
      .collection("refundCases")
      .where("status", "==", "requested")
      .limit(20)
      .get();
    await Promise.all(
      requested.docs.map((doc) =>
        executePaystackRefundV2(doc.id).catch(() => undefined),
      ),
    );
    const submitted = await db
      .collection("refundCases")
      .where("status", "==", "submitted")
      .limit(20)
      .get();
    await Promise.all(
      submitted.docs.map((doc) =>
        reconcilePaystackRefundV2(doc.id).catch(() => undefined),
      ),
    );
    return null;
  });

/** Called only after Paystack independently confirms a processed refund. */
export async function confirmProviderRefundV2(input: {
  refundCaseId: string;
  providerRefundId: string;
  providerReference: string;
  providerStatus: string;
  providerAmountMinor: number;
}): Promise<{ deduped: boolean; fullRefund: boolean }> {
  const refundCaseId = requireId(input.refundCaseId, "REFUND_CASE_ID");
  const providerRefundId = requireId(
    input.providerRefundId,
    "PROVIDER_REFUND_ID",
  );
  const providerReference = requireId(
    input.providerReference,
    "PROVIDER_REFERENCE",
  );
  const providerAmount = requirePositiveMinorUnits(
    input.providerAmountMinor,
    "provider_amount",
  );
  if (!["processed", "success"].includes(input.providerStatus.toLowerCase())) {
    throw new Error("REFUND_NOT_PROVIDER_CONFIRMED");
  }
  const caseRef = db.doc(`refundCases/${refundCaseId}`);
  const providerEventRef = db.doc(
    `paymentEvents/${stableDocumentId("pe", [
      "paystack",
      "refund",
      providerRefundId,
    ])}`,
  );
  let deduped = false;
  let fullRefund = false;
  await db.runTransaction(async (tx) => {
    const [refundCase, providerEvent] = await Promise.all([
      tx.get(caseRef),
      tx.get(providerEventRef),
    ]);
    if (!refundCase.exists) throw new Error("REFUND_CASE_NOT_FOUND");
    const caseData = refundCase.data() ?? {};
    const intentId = requireId(caseData.intentId, "INTENT_ID");
    const intentRef = db.doc(`paymentIntents/${intentId}`);
    const intent = await tx.get(intentRef);
    if (!intent.exists) throw new Error("INTENT_NOT_FOUND");
    const expectedCaseAmount = requirePositiveMinorUnits(
      caseData.refundAmountMinor,
      "refund_amount",
    );
    if (providerAmount !== expectedCaseAmount) {
      throw new Error("REFUND_PROVIDER_AMOUNT_MISMATCH");
    }
    if (providerEvent.exists) {
      const eventData = providerEvent.data() ?? {};
      if (
        String(eventData.refundCaseId ?? "") !== refundCaseId ||
        String(eventData.reference ?? "") !== providerReference ||
        Number(eventData.providerAmountMinor) !== providerAmount
      ) {
        throw new Error("REFUND_PROVIDER_EVENT_COLLISION");
      }
    }
    if (caseData.providerConfirmed === true) {
      if (
        String(caseData.providerRefundId ?? "") !== providerRefundId ||
        String(caseData.providerReference ?? "") !== providerReference
      ) {
        throw new Error("REFUND_PROVIDER_IDENTITY_MISMATCH");
      }
      deduped = true;
      const intentData = intent.data() ?? {};
      const refundableTotal =
        caseData.exceptionCharge === true
          ? Number(intentData.providerAmountMinor ?? -1)
          : Number(intentData.expectedAmountMinor ?? -1);
      fullRefund =
        Number(intentData.confirmedRefundMinor ?? 0) === refundableTotal;
      return;
    }
    const intentData = intent.data() ?? {};
    const expected = requirePositiveMinorUnits(
      intentData.expectedAmountMinor,
      "expected_amount",
    );
    const refundableTotal =
      caseData.exceptionCharge === true
        ? requirePositiveMinorUnits(
            intentData.providerAmountMinor,
            "provider_amount",
          )
        : expected;
    const confirmedBefore = Number(intentData.confirmedRefundMinor ?? 0);
    const requestedBefore = Number(intentData.requestedRefundMinor ?? 0);
    if (
      !Number.isSafeInteger(confirmedBefore) ||
      !Number.isSafeInteger(requestedBefore) ||
      confirmedBefore < 0 ||
      requestedBefore < providerAmount ||
      confirmedBefore + providerAmount > refundableTotal
    ) {
      throw new Error("REFUND_TOTAL_INVALID");
    }
    const confirmedAfter = confirmedBefore + providerAmount;
    fullRefund = confirmedAfter === refundableTotal;
    const now = FieldValue.serverTimestamp();
    if (fullRefund && String(intentData.purpose ?? "") === "campaign_credit") {
      const purchaseRef = db.doc(`campaignCreditPurchases/${intentId}`);
      const purchase = await tx.get(purchaseRef);
      if (!purchase.exists)
        throw new Error("CAMPAIGN_CREDIT_PURCHASE_NOT_FOUND");
      const purchaseData = purchase.data() ?? {};
      const creditAmountMinor = requirePositiveMinorUnits(
        purchaseData.creditAmountMinor,
        "credit_amount",
      );
      const refundedCreditMinor = Number(purchaseData.refundedCreditMinor ?? 0);
      if (
        !Number.isSafeInteger(refundedCreditMinor) ||
        refundedCreditMinor < 0
      ) {
        throw new Error("CAMPAIGN_CREDIT_REFUND_INVALID");
      }
      if (refundedCreditMinor !== 0) {
        throw new Error("CAMPAIGN_CREDIT_ALREADY_REVERSED");
      }
      const walletStoreId = requireId(
        purchaseData.walletStoreId,
        "WALLET_STORE_ID",
      );
      const merchantId = requireId(purchaseData.merchantId, "MERCHANT_ID");
      const walletRef = campaignWalletRef(walletStoreId);
      const operationRef = campaignOperationRef(
        walletStoreId,
        `refund:${refundCaseId}`,
      );
      const [wallet, existingOperation] = await Promise.all([
        tx.get(walletRef),
        tx.get(operationRef),
      ]);
      if (existingOperation.exists) {
        throw new Error("CAMPAIGN_CREDIT_REFUND_OPERATION_EXISTS");
      }
      const currentBalance = Number(wallet.data()?.virtualBalance ?? 0);
      const currentBalanceMinor = Math.round(currentBalance * 100);
      if (
        !Number.isFinite(currentBalance) ||
        !Number.isSafeInteger(currentBalanceMinor)
      ) {
        throw new Error("CAMPAIGN_CREDIT_BALANCE_INVALID");
      }
      const nextBalanceMinor = currentBalanceMinor - creditAmountMinor;
      const nextBalance = nextBalanceMinor / 100;
      const shared = purchaseData.walletStoreId !== purchaseData.merchantId;
      tx.set(
        walletRef,
        {
          virtualBalance: nextBalance,
          campaignCreditsUpdatedAt: now,
        },
        { merge: true },
      );
      if (shared) {
        tx.set(
          campaignBalanceRef(walletStoreId),
          {
            walletStoreId,
            balance: nextBalance,
            shared: true,
            sourceStoreId: merchantId,
            updatedAt: now,
          },
          { merge: true },
        );
      }
      tx.create(operationRef, {
        operationId: `refund:${refundCaseId}`,
        kind: "paystack-refund",
        source: "paystack_v2",
        storeId: merchantId,
        walletStoreId,
        shared,
        delta: -(creditAmountMinor / 100),
        deltaMinor: -creditAmountMinor,
        balanceBefore: currentBalance,
        balanceAfter: nextBalance,
        intentId,
        refundCaseId,
        providerRefundId,
        createdAt: now,
      });
      tx.update(purchaseRef, {
        refundedCreditMinor: creditAmountMinor,
        refundCaseId,
        providerRefundId,
        refundedAt: now,
        updatedAt: now,
      });
      if (nextBalanceMinor < 0) {
        tx.create(db.doc(`campaignCreditRecoveryCases/${refundCaseId}`), {
          recoveryCaseId: refundCaseId,
          intentId,
          refundCaseId,
          merchantId,
          walletStoreId,
          owner: "operations",
          status: "open",
          reason: "refunded_credits_already_spent",
          shortageMinor: Math.abs(nextBalanceMinor),
          providerRefundId,
          createdAt: now,
          updatedAt: now,
        });
      }
    }
    if (
      fullRefund &&
      String(intentData.purpose ?? "") === "merchant_order" &&
      String(intentData.inventoryReservationId ?? "").trim()
    ) {
      const reservationId = requireId(
        intentData.inventoryReservationId,
        "RESERVATION_ID",
      );
      const reservationRef = db.doc(`inventoryReservations/${reservationId}`);
      const reservation = await tx.get(reservationRef);
      if (!reservation.exists)
        throw new Error("INVENTORY_RESERVATION_NOT_FOUND");
      const reservationData = reservation.data() ?? {};
      const merchantId = requireId(reservationData.merchantId, "MERCHANT_ID");
      const orderId = requireId(reservationData.orderId, "ORDER_ID");
      const status = String(reservationData.status ?? "");
      if (status !== "returned_after_refund") {
        if (!["committed", "consumed"].includes(status)) {
          throw new Error("REFUND_INVENTORY_STATE_INVALID");
        }
        const items = Array.isArray(reservationData.items)
          ? reservationData.items
          : [];
        const productRefs = items.map((item: any) =>
          db.doc(
            `users/${merchantId}/products/${requireId(
              item?.productId,
              "PRODUCT_ID",
            )}`,
          ),
        );
        for (const productRef of productRefs) await tx.get(productRef);
        items.forEach((item: any, index: number) => {
          tx.update(productRefs[index], {
            quantity: FieldValue.increment(positiveQuantity(item?.quantity)),
            updatedAt: now,
          });
        });
        tx.update(reservationRef, {
          status: "returned_after_refund",
          returnedRefundCaseId: refundCaseId,
          returnedAt: now,
          updatedAt: now,
        });
        tx.set(
          db.doc(`users/${merchantId}/sales/${orderId}`),
          {
            status: "refunded",
            paymentStatus: "refunded",
            inventoryReturnedAfterRefund: true,
            refundCaseId,
            refundedAt: now,
            updatedAt: now,
          },
          { merge: true },
        );
      }
    }
    if (
      ["account_settlement", "repayment_installment"].includes(
        String(intentData.purpose ?? ""),
      )
    ) {
      const merchantId = requireId(intentData.merchantId, "MERCHANT_ID");
      const customerId = requireId(intentData.customerId, "CUSTOMER_ID");
      const customerRef = db.doc(`users/${merchantId}/customers/${customerId}`);
      const reversalRef = customerRef
        .collection("transactions")
        .doc(`paystack_refund_${refundCaseId}`);
      const settlementRef = db.doc(
        `settlements/${stableDocumentId("st", [intentId])}`,
      );
      const planId = String(intentData.repaymentPlanId ?? "").trim();
      const planRef = planId
        ? db.doc(`repaymentPlans/${requireId(planId, "PLAN_ID")}`)
        : null;
      const [customer, reversalSnapshot, settlement, plan] = await Promise.all([
        tx.get(customerRef),
        tx.get(reversalRef),
        tx.get(settlementRef),
        planRef ? tx.get(planRef) : Promise.resolve(null),
      ]);
      if (!customer.exists) throw new Error("CUSTOMER_NOT_FOUND");
      if (reversalSnapshot.exists) {
        throw new Error("ACCOUNT_REFUND_LEDGER_ALREADY_EXISTS");
      }
      const reversalData = {
        type: "Credit",
        amount: providerAmount / 100,
        amountMinor: providerAmount,
        date: now,
        status: "REFUNDED",
        remarks: "Online payment refund",
        source: "paystack_refund_v2",
        paymentIntentId: intentId,
        refundCaseId,
        providerRefundId,
        providerReference,
        schemaVersion: 2,
      };
      tx.create(reversalRef, reversalData);
      tx.set(
        customerRef,
        { lastTransaction: reversalData, updatedAt: now },
        { merge: true },
      );
      if (settlement.exists) {
        tx.update(settlementRef, {
          status: "refund_adjustment_pending",
          refundedAmountMinor: FieldValue.increment(providerAmount),
          lastRefundCaseId: refundCaseId,
          updatedAt: now,
        });
      }
      if (planRef && plan?.exists) {
        const paidBefore = Number(plan.get("paidAmountMinor") ?? 0);
        const remainingBefore = Number(plan.get("remainingAmountMinor") ?? 0);
        const total = Number(plan.get("totalAmountMinor") ?? 0);
        const completedBefore = Number(plan.get("completedInstallments") ?? 0);
        if (
          ![paidBefore, remainingBefore, total, completedBefore].every(
            Number.isSafeInteger,
          ) ||
          paidBefore < providerAmount ||
          remainingBefore + providerAmount > total ||
          completedBefore <= 0
        ) {
          throw new Error("REPAYMENT_PLAN_REFUND_INVALID");
        }
        tx.update(planRef, {
          paidAmountMinor: paidBefore - providerAmount,
          remainingAmountMinor: remainingBefore + providerAmount,
          completedInstallments: completedBefore - 1,
          status: "active",
          completedAt: FieldValue.delete(),
          lastRefundCaseId: refundCaseId,
          updatedAt: now,
        });
      }
    }
    if (!providerEvent.exists) {
      tx.create(providerEventRef, {
        eventId: providerEventRef.id,
        provider: "paystack",
        providerEventId: providerRefundId,
        eventType: "refund.processed",
        reference: providerReference,
        refundCaseId,
        intentId,
        providerAmountMinor: providerAmount,
        processingState: "applied",
        attemptCount: 1,
        schemaVersion: 2,
        receivedAt: now,
        updatedAt: now,
      });
    }
    tx.update(caseRef, {
      status: "confirmed",
      providerConfirmed: true,
      providerRefundId,
      providerReference,
      providerStatus: input.providerStatus.toLowerCase(),
      confirmedAt: now,
      updatedAt: now,
    });
    tx.update(intentRef, {
      status: fullRefund ? "refunded" : "refund_pending",
      confirmedRefundMinor: confirmedAfter,
      requestedRefundMinor: requestedBefore - providerAmount,
      refundProviderConfirmed: fullRefund,
      updatedAt: now,
    });
    const commerceOrderId = String(caseData.commerceOrderId ?? "").trim();
    if (commerceOrderId) {
      tx.set(
        db.doc(`commerceOrders/${requireId(commerceOrderId, "ORDER_ID")}`),
        {
          status: fullRefund ? "refunded" : "cancelled",
          paymentStatus: fullRefund ? "refunded" : "refund_pending",
          refund: {
            mode: "paystack",
            providerConfirmed: true,
            providerRefundId,
            providerReference,
            lastConfirmedAmountMinor: providerAmount,
            confirmedTotalMinor: confirmedAfter,
          },
          ...(fullRefund ? { refundedAt: now } : {}),
          updatedAt: now,
        },
        { merge: true },
      );
    }
  });
  return { deduped, fullRefund };
}
