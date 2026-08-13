import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import {
  assertMoneySnapshot,
  isPaymentStatus,
  MoneySnapshot,
  PaymentStatus,
  stableDocumentId,
} from "./domain";

export type ReconciliationIssue = {
  code: string;
  expected?: number;
  actual?: number;
};

export function reconcileIntentData(
  value: Record<string, unknown>,
): ReconciliationIssue[] {
  const issues: ReconciliationIssue[] = [];
  const status = String(value.status ?? "") as PaymentStatus;
  if (!isPaymentStatus(status)) issues.push({ code: "STATUS_INVALID" });
  const expected = Number(value.expectedAmountMinor);
  if (!Number.isSafeInteger(expected) || expected <= 0) {
    issues.push({ code: "EXPECTED_AMOUNT_INVALID" });
  }
  const money =
    value.money && typeof value.money === "object"
      ? (value.money as Record<string, unknown>)
      : {};
  try {
    assertMoneySnapshot(money as MoneySnapshot);
  } catch {
    issues.push({ code: "MONEY_SNAPSHOT_INVALID" });
  }
  const gross = Number(money.grossAmountMinor);
  if (Number.isSafeInteger(expected) && gross !== expected) {
    issues.push({
      code: "MONEY_GROSS_MISMATCH",
      expected,
      actual: gross,
    });
  }
  const platformShare = Number(money.platformGrossShareMinor);
  const merchantShare = Number(money.merchantGrossShareMinor);
  if (Number.isSafeInteger(gross) && platformShare + merchantShare !== gross) {
    issues.push({
      code: "SPLIT_TOTAL_MISMATCH",
      expected: gross,
      actual: platformShare + merchantShare,
    });
  }
  const providerAmount = Number(value.providerAmountMinor);
  if (
    ["paid", "refund_pending", "refunded", "disputed"].includes(status) &&
    providerAmount !== expected
  ) {
    issues.push({
      code: "PROVIDER_AMOUNT_MISMATCH",
      expected,
      actual: providerAmount,
    });
  }
  if (
    ["paid", "refund_pending", "refunded", "disputed"].includes(status) &&
    !String(value.providerReference ?? "").trim()
  ) {
    issues.push({ code: "PROVIDER_REFERENCE_MISSING" });
  }
  if (status === "refunded" && value.refundProviderConfirmed !== true) {
    issues.push({ code: "REFUND_NOT_PROVIDER_CONFIRMED" });
  }
  return issues;
}

export async function reconcileIntentRelations(
  intentId: string,
  value: Record<string, any>,
): Promise<ReconciliationIssue[]> {
  const issues: ReconciliationIssue[] = [];
  const status = String(value.status ?? "");
  if (!["paid", "refund_pending", "refunded", "disputed"].includes(status)) {
    return issues;
  }
  const purpose = String(value.purpose ?? "");
  const merchantId = String(value.merchantId ?? "");
  const bindingId = String(value.businessBinding?.id ?? "");
  const [events, settlements, refunds] = await Promise.all([
    db
      .collection("paymentEvents")
      .where("intentId", "==", intentId)
      .limit(10)
      .get(),
    db
      .collection("settlements")
      .where("intentId", "==", intentId)
      .limit(2)
      .get(),
    db
      .collection("refundCases")
      .where("intentId", "==", intentId)
      .limit(100)
      .get(),
  ]);
  if (
    !events.docs.some((doc) =>
      [
        "applied",
        "applied_refund_pending",
        "quarantined_refund_pending",
      ].includes(String(doc.get("processingState") ?? "")),
    )
  ) {
    issues.push({ code: "APPLIED_PROVIDER_EVENT_MISSING" });
  }
  const expectsSettlement =
    purpose !== "campaign_credit" &&
    !(status === "refund_pending" && settlements.empty);
  if (expectsSettlement && settlements.size !== 1) {
    issues.push({
      code: "SETTLEMENT_COUNT_MISMATCH",
      expected: 1,
      actual: settlements.size,
    });
  }
  if (settlements.size === 1) {
    const settlement = settlements.docs[0].data();
    const actualMoney = value.actualMoney ?? value.money ?? {};
    for (const [field, expectedField] of [
      ["grossAmountMinor", "grossAmountMinor"],
      ["platformFeeMinor", "platformFeeMinor"],
      ["providerFeeMinor", "providerFeeMinor"],
      ["merchantNetProceedsMinor", "merchantNetProceedsMinor"],
    ] as const) {
      const expected = Number(
        actualMoney[expectedField] ?? value[expectedField],
      );
      const actual = Number(settlement[field]);
      if (!Number.isSafeInteger(expected) || expected !== actual) {
        issues.push({
          code: `SETTLEMENT_${field.toUpperCase()}_MISMATCH`,
          expected,
          actual,
        });
      }
    }
  }
  const requested = refunds.docs
    .filter((doc) => doc.get("providerConfirmed") !== true)
    .reduce((sum, doc) => sum + Number(doc.get("refundAmountMinor") ?? 0), 0);
  const confirmed = refunds.docs
    .filter((doc) => doc.get("providerConfirmed") === true)
    .reduce((sum, doc) => sum + Number(doc.get("refundAmountMinor") ?? 0), 0);
  if (requested !== Number(value.requestedRefundMinor ?? 0)) {
    issues.push({
      code: "REQUESTED_REFUND_TOTAL_MISMATCH",
      expected: Number(value.requestedRefundMinor ?? 0),
      actual: requested,
    });
  }
  if (confirmed !== Number(value.confirmedRefundMinor ?? 0)) {
    issues.push({
      code: "CONFIRMED_REFUND_TOTAL_MISMATCH",
      expected: Number(value.confirmedRefundMinor ?? 0),
      actual: confirmed,
    });
  }
  if (status !== "paid") return issues;
  let businessExists = false;
  if (purpose === "campaign_credit") {
    businessExists = (await db.doc(`campaignCreditPurchases/${intentId}`).get())
      .exists;
  } else if (purpose === "merchant_order") {
    businessExists = (
      await db.doc(`users/${merchantId}/sales/${bindingId}`).get()
    ).exists;
    const reservationId = String(value.inventoryReservationId ?? "");
    const reservation = reservationId
      ? await db.doc(`inventoryReservations/${reservationId}`).get()
      : null;
    if (
      !reservation?.exists ||
      !["committed", "consumed"].includes(
        String(reservation.get("status") ?? ""),
      )
    ) {
      issues.push({ code: "PAID_INVENTORY_RESERVATION_INVALID" });
    }
  } else if (purpose === "supplier_order") {
    businessExists = (await db.doc(`commerceOrders/${bindingId}`).get()).exists;
    if (!(await db.doc(`supplierFulfilments/${intentId}`).get()).exists) {
      issues.push({ code: "SUPPLIER_FULFILMENT_MISSING" });
    }
  } else if (
    ["account_settlement", "repayment_installment"].includes(purpose)
  ) {
    const customerId = String(value.customerId ?? "");
    businessExists = (
      await db
        .doc(
          `users/${merchantId}/customers/${customerId}/transactions/paystack_${intentId}`,
        )
        .get()
    ).exists;
  }
  if (!businessExists) issues.push({ code: "BUSINESS_PROJECTION_MISSING" });
  return issues;
}

export type ReconciliationRunResult = {
  runId: string;
  checkedCount: number;
  mismatchCount: number;
  status: "balanced" | "mismatch";
  truncated: boolean;
};

export function reconciliationOutcome(input: {
  mismatchCount: number;
  windowTruncated: boolean;
}): { mismatchCount: number; status: "balanced" | "mismatch" } {
  const mismatchCount = Number(input.mismatchCount);
  if (!Number.isSafeInteger(mismatchCount) || mismatchCount < 0) {
    throw new Error("RECONCILIATION_COUNT_INVALID");
  }
  return {
    mismatchCount: mismatchCount + (input.windowTruncated ? 1 : 0),
    status:
      mismatchCount > 0 || input.windowTruncated ? "mismatch" : "balanced",
  };
}

/** Shared runner used by both the scheduler and audited operations command. */
export async function runPaymentsV2Reconciliation(input: {
  windowDays?: number;
  source: "scheduled" | "on_demand";
  actorUid?: string;
  operationId?: string;
  reason?: string;
}): Promise<ReconciliationRunResult> {
  const windowDays = Number(input.windowDays ?? 7);
  if (!Number.isSafeInteger(windowDays) || windowDays < 1 || windowDays > 30) {
    throw new Error("RECONCILIATION_WINDOW_INVALID");
  }
  const deterministicId = input.operationId
    ? stableDocumentId("recon", [input.operationId])
    : "";
  const runRef = deterministicId
    ? db.doc(`financialReconciliationRuns/${deterministicId}`)
    : db.collection("financialReconciliationRuns").doc();
  const prior = await runRef.get();
  if (prior.exists) {
    const value = prior.data() ?? {};
    return {
      runId: runRef.id,
      checkedCount: Number(value.checkedCount ?? 0),
      mismatchCount: Number(value.mismatchCount ?? 0),
      status: value.status === "balanced" ? "balanced" : "mismatch",
      truncated: value.truncated === true,
    };
  }
  const cutoff = Timestamp.fromMillis(
    Date.now() - windowDays * 24 * 60 * 60 * 1000,
  );
  const intents = await db
    .collection("paymentIntents")
    .where("updatedAt", ">=", cutoff)
    .orderBy("updatedAt", "asc")
    .limit(501)
    .get();
  const windowTruncated = intents.size > 500;
  const results = [];
  for (const doc of intents.docs.slice(0, 500)) {
    const value = doc.data();
    const issues = [
      ...reconcileIntentData(value),
      ...(await reconcileIntentRelations(doc.id, value)),
    ];
    results.push({ intentId: doc.id, issues });
  }
  const mismatches = results.filter((result) => result.issues.length > 0);
  const outcome = reconciliationOutcome({
    mismatchCount: mismatches.length,
    windowTruncated,
  });
  const mismatchSamples = [
    ...mismatches,
    ...(windowTruncated
      ? [
          {
            intentId: "__reconciliation_window__",
            issues: [{ code: "RECONCILIATION_WINDOW_TRUNCATED" }],
          },
        ]
      : []),
  ];
  const truncated = windowTruncated || mismatchSamples.length > 100;
  await runRef.set({
    runId: runRef.id,
    windowStart: cutoff,
    checkedCount: results.length,
    mismatchCount: outcome.mismatchCount,
    status: outcome.status,
    mismatchSamples: mismatchSamples.slice(0, 100),
    reconciliationContract: {
      providerEvent: true,
      providerCharge: true,
      immutableFeeSnapshot: true,
      settlement: true,
      refundTotals: true,
      businessProjection: true,
      completeWindow: !windowTruncated,
    },
    truncated,
    source: input.source,
    actorUid: input.actorUid ?? null,
    operationId: input.operationId ?? null,
    reason: input.reason ?? null,
    schemaVersion: 2,
    createdAt: FieldValue.serverTimestamp(),
  });
  if (outcome.status === "mismatch") {
    console.error("[payments-v2] reconciliation mismatch", {
      runId: runRef.id,
      checkedCount: results.length,
      mismatchCount: outcome.mismatchCount,
      windowTruncated,
    });
  }
  return {
    runId: runRef.id,
    checkedCount: results.length,
    mismatchCount: outcome.mismatchCount,
    status: outcome.status,
    truncated,
  };
}

export const reconcilePaymentsV2OnDemand = functions
  .runWith({ timeoutSeconds: 540, memory: "1GB" })
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
    const operationId = String(data?.operationId ?? "").trim();
    const reason = String(data?.reason ?? "")
      .trim()
      .slice(0, 500);
    if (!/^[A-Za-z0-9:_-]{1,120}$/.test(operationId) || !reason) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid operationId and audit reason are required.",
      );
    }
    try {
      return await runPaymentsV2Reconciliation({
        windowDays: data?.windowDays,
        source: "on_demand",
        actorUid: context.auth.uid,
        operationId,
        reason,
      });
    } catch (error) {
      if (error instanceof functions.https.HttpsError) throw error;
      throw new functions.https.HttpsError(
        "failed-precondition",
        error instanceof Error ? error.message : "Reconciliation failed.",
      );
    }
  });

export const reconcilePaymentsV2Daily = functions
  .runWith({ timeoutSeconds: 540, memory: "1GB" })
  .pubsub.schedule("30 2 * * *")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    await runPaymentsV2Reconciliation({ source: "scheduled", windowDays: 7 });
    return null;
  });
