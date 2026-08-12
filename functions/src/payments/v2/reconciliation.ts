import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import {
  assertMoneySnapshot,
  isPaymentStatus,
  MoneySnapshot,
  PaymentStatus,
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

export const reconcilePaymentsV2Daily = functions
  .runWith({ timeoutSeconds: 540, memory: "1GB" })
  .pubsub.schedule("30 2 * * *")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    const runRef = db.collection("financialReconciliationRuns").doc();
    const cutoff = Timestamp.fromMillis(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const intents = await db
      .collection("paymentIntents")
      .where("updatedAt", ">=", cutoff)
      .orderBy("updatedAt", "asc")
      .limit(500)
      .get();
    const results = [];
    for (const doc of intents.docs) {
      const value = doc.data();
      const issues = [
        ...reconcileIntentData(value),
        ...(await reconcileIntentRelations(doc.id, value)),
      ];
      results.push({ intentId: doc.id, issues });
    }
    const mismatches = results.filter((result) => result.issues.length > 0);
    await runRef.set({
      runId: runRef.id,
      windowStart: cutoff,
      checkedCount: intents.size,
      mismatchCount: mismatches.length,
      status: mismatches.length ? "mismatch" : "balanced",
      mismatchSamples: mismatches.slice(0, 100),
      reconciliationContract: {
        providerEvent: true,
        providerCharge: true,
        immutableFeeSnapshot: true,
        settlement: true,
        refundTotals: true,
        businessProjection: true,
      },
      truncated: mismatches.length > 100,
      schemaVersion: 2,
      createdAt: FieldValue.serverTimestamp(),
    });
    if (mismatches.length) {
      console.error("[payments-v2] reconciliation mismatch", {
        runId: runRef.id,
        checkedCount: intents.size,
        mismatchCount: mismatches.length,
      });
    }
    return null;
  });
