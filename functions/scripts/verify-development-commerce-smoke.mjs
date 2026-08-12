#!/usr/bin/env node

import process from "node:process";
import { readFile, stat } from "node:fs/promises";
import { isAbsolute } from "node:path";
import { pathToFileURL } from "node:url";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const DEVELOPMENT_PROJECTS = new Set(["spazaone-dev", "spazaone-dev-za"]);
const FLOWS = new Set(["owned_order", "account_settlement"]);

function argsMap(argv) {
  const result = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (!value.startsWith("--")) continue;
    const [key, inline] = value.slice(2).split("=", 2);
    const next = argv[index + 1];
    if (inline != null) result.set(key, inline);
    else if (next && !next.startsWith("--")) {
      result.set(key, next);
      index += 1;
    } else result.set(key, true);
  }
  return result;
}

export function validateCommerceSmokeVerificationOptions(argv) {
  const args = argsMap(argv);
  const projectId = String(args.get("project") ?? "").trim();
  const handoff = String(args.get("handoff") ?? "").trim();
  const timeoutMs = Number(args.get("timeout-ms") ?? 45_000);
  if (!DEVELOPMENT_PROJECTS.has(projectId)) {
    throw new Error(
      "Verification requires an explicit registered dev project.",
    );
  }
  if (!isAbsolute(handoff)) {
    throw new Error("Verification requires an absolute --handoff path.");
  }
  if (
    !Number.isSafeInteger(timeoutMs) ||
    timeoutMs < 1_000 ||
    timeoutMs > 60_000
  ) {
    throw new Error("COMMERCE_SMOKE_VERIFY_TIMEOUT_INVALID");
  }
  return { projectId, handoff, timeoutMs };
}

function moneyIsReconciled(actual, settlement, amountMinor) {
  const keys = [
    "grossAmountMinor",
    "platformFeeMinor",
    "providerFeeMinor",
    "merchantNetProceedsMinor",
  ];
  return (
    actual?.currency === "ZAR" &&
    Number(actual?.grossAmountMinor) === amountMinor &&
    Number(actual?.platformGrossShareMinor) +
      Number(actual?.merchantGrossShareMinor) ===
      amountMinor &&
    Number(actual?.merchantGrossShareMinor) -
      Number(actual?.providerFeeMinor) ===
      Number(actual?.merchantNetProceedsMinor) &&
    keys.every(
      (key) =>
        Number.isSafeInteger(Number(actual?.[key])) &&
        Number(settlement?.[key]) === Number(actual?.[key]),
    )
  );
}

export function validateCommerceSmokeEvidence(input) {
  const {
    handoff,
    run,
    intent,
    event,
    eventCount,
    settlement,
    settlementCount,
    refundCount,
    notification,
    notificationCount,
    sale,
    reservation,
    product,
    ledger,
    paystackLedgerCount,
    customer,
  } = input;
  const failures = [];
  const expect = (condition, code) => {
    if (!condition) failures.push(code);
  };
  const flow = String(handoff.flow ?? "");
  const amountMinor = Number(handoff.amountMinor);
  const expectedPurpose =
    flow === "owned_order" ? "merchant_order" : "account_settlement";
  const appliedEvents = Array.isArray(intent.appliedProviderEventIds)
    ? intent.appliedProviderEventIds.map(String)
    : [];

  expect(FLOWS.has(flow), "FLOW_INVALID");
  expect(run.status === "initialized", "RUN_NOT_INITIALIZED");
  expect(run.synthetic === true, "RUN_NOT_SYNTHETIC");
  expect(run.intentId === handoff.intentId, "RUN_INTENT_MISMATCH");
  expect(intent.status === "paid", "INTENT_NOT_PAID");
  expect(intent.purpose === expectedPurpose, "INTENT_PURPOSE_MISMATCH");
  expect(intent.merchantId === handoff.merchantId, "INTENT_MERCHANT_MISMATCH");
  expect(intent.expectedAmountMinor === amountMinor, "INTENT_AMOUNT_MISMATCH");
  expect(
    intent.providerAmountMinor === amountMinor,
    "PROVIDER_AMOUNT_MISMATCH",
  );
  expect(intent.providerReference === handoff.reference, "REFERENCE_MISMATCH");
  expect(intent.selectedChannel === handoff.channel, "CHANNEL_MISMATCH");
  expect(appliedEvents.length === 1, "APPLIED_EVENT_COUNT_MISMATCH");
  expect(eventCount === 1, "PROVIDER_EVENT_COUNT_MISMATCH");
  expect(event.processingState === "applied", "PROVIDER_EVENT_NOT_APPLIED");
  expect(event.eventType === "charge.success", "PROVIDER_EVENT_TYPE_MISMATCH");
  expect(event.intentId === handoff.intentId, "PROVIDER_EVENT_INTENT_MISMATCH");
  expect(
    event.reference === handoff.reference,
    "PROVIDER_EVENT_REFERENCE_MISMATCH",
  );
  expect(settlementCount === 1, "SETTLEMENT_COUNT_MISMATCH");
  expect(settlement.status === "pending", "SETTLEMENT_STATUS_MISMATCH");
  expect(
    settlement.intentId === handoff.intentId,
    "SETTLEMENT_INTENT_MISMATCH",
  );
  expect(
    settlement.destination?.accountLast4 === "0000",
    "SETTLEMENT_DESTINATION_MISMATCH",
  );
  expect(
    moneyIsReconciled(intent.actualMoney, settlement, amountMinor),
    "MONEY_NOT_RECONCILED",
  );
  expect(refundCount === 0, "UNEXPECTED_REFUND_CASE");
  expect(notificationCount === 1, "NOTIFICATION_OUTBOX_COUNT_MISMATCH");
  expect(
    ["pending", "processing", "retry", "sent", "failed"].includes(
      notification.state,
    ),
    "NOTIFICATION_STATE_INVALID",
  );
  expect(Number(notification.attempts ?? 0) >= 1, "NOTIFICATION_NOT_ATTEMPTED");

  if (flow === "owned_order") {
    expect(
      intent.businessBinding?.type === "owned_order",
      "ORDER_BINDING_TYPE_MISMATCH",
    );
    expect(
      intent.businessBinding?.id === handoff.orderId,
      "ORDER_BINDING_ID_MISMATCH",
    );
    expect(sale.status === "paid", "ORDER_NOT_PAID");
    expect(sale.paymentStatus === "paid", "ORDER_PAYMENT_STATUS_MISMATCH");
    expect(sale.paymentIntentId === handoff.intentId, "ORDER_INTENT_MISMATCH");
    expect(reservation.status === "committed", "RESERVATION_NOT_COMMITTED");
    expect(
      reservation.reservationId === handoff.reservationId,
      "RESERVATION_ID_MISMATCH",
    );
    expect(
      Number(product.quantity) === Number(handoff.productQuantityBefore) - 1,
      "OWNED_STOCK_QUANTITY_MISMATCH",
    );
  } else if (flow === "account_settlement") {
    expect(
      intent.businessBinding?.type === "customer_account",
      "ACCOUNT_BINDING_TYPE_MISMATCH",
    );
    expect(
      intent.businessBinding?.id === handoff.customerId,
      "ACCOUNT_BINDING_ID_MISMATCH",
    );
    expect(paystackLedgerCount === 1, "ACCOUNT_LEDGER_COUNT_MISMATCH");
    expect(ledger.type === "Payment", "ACCOUNT_LEDGER_TYPE_MISMATCH");
    expect(ledger.source === "paystack_v2", "ACCOUNT_LEDGER_SOURCE_MISMATCH");
    expect(
      ledger.amountMinor === amountMinor,
      "ACCOUNT_LEDGER_AMOUNT_MISMATCH",
    );
    expect(
      Number(customer.balance) ===
        Number(handoff.balanceBefore) + amountMinor / 100,
      "CUSTOMER_BALANCE_MISMATCH",
    );
  }
  return failures;
}

async function readEvidence(db, handoff) {
  const intentRef = db.doc(`paymentIntents/${handoff.intentId}`);
  const runRef = db.doc(`developmentCommerceSmokeRuns/${handoff.runId}`);
  const [
    runSnapshot,
    intentSnapshot,
    events,
    settlements,
    refunds,
    notifications,
  ] = await Promise.all([
    runRef.get(),
    intentRef.get(),
    db
      .collection("paymentEvents")
      .where("intentId", "==", handoff.intentId)
      .get(),
    db
      .collection("settlements")
      .where("intentId", "==", handoff.intentId)
      .get(),
    db
      .collection("refundCases")
      .where("intentId", "==", handoff.intentId)
      .get(),
    db
      .collection("commerceNotificationOutbox")
      .where(
        "notice.orderId",
        "==",
        handoff.flow === "owned_order" ? handoff.orderId : handoff.intentId,
      )
      .get(),
  ]);
  const evidence = {
    handoff,
    run: runSnapshot.data() ?? {},
    intent: intentSnapshot.data() ?? {},
    event: events.docs[0]?.data() ?? {},
    eventCount: events.size,
    settlement: settlements.docs[0]?.data() ?? {},
    settlementCount: settlements.size,
    refundCount: refunds.size,
    notification: notifications.docs[0]?.data() ?? {},
    notificationCount: notifications.size,
    sale: {},
    reservation: {},
    product: {},
    ledger: {},
    paystackLedgerCount: 0,
    customer: {},
  };
  if (handoff.flow === "owned_order") {
    const [sale, reservation, product] = await Promise.all([
      db.doc(`users/${handoff.merchantId}/sales/${handoff.orderId}`).get(),
      db.doc(`inventoryReservations/${handoff.reservationId}`).get(),
      db
        .doc(`users/${handoff.merchantId}/products/dev-seed-owned-product`)
        .get(),
    ]);
    evidence.sale = sale.data() ?? {};
    evidence.reservation = reservation.data() ?? {};
    evidence.product = product.data() ?? {};
  } else {
    const customerRef = db.doc(
      `users/${handoff.merchantId}/customers/${handoff.customerId}`,
    );
    const [customer, ledger, paystackLedgers] = await Promise.all([
      customerRef.get(),
      customerRef
        .collection("transactions")
        .doc(`paystack_${handoff.intentId}`)
        .get(),
      customerRef
        .collection("transactions")
        .where("paymentIntentId", "==", handoff.intentId)
        .get(),
    ]);
    evidence.customer = customer.data() ?? {};
    evidence.ledger = ledger.data() ?? {};
    evidence.paystackLedgerCount = paystackLedgers.size;
  }
  return evidence;
}

async function run(options) {
  const file = await stat(options.handoff);
  if ((file.mode & 0o077) !== 0) {
    throw new Error("COMMERCE_SMOKE_HANDOFF_PERMISSIONS_UNSAFE");
  }
  const handoff = JSON.parse(await readFile(options.handoff, "utf8"));
  if (
    handoff.projectId !== options.projectId ||
    !FLOWS.has(String(handoff.flow ?? "")) ||
    !/^[A-Za-z0-9:_-]{12,120}$/.test(String(handoff.runId ?? "")) ||
    !/^pi_[a-f0-9]{64}$/.test(String(handoff.intentId ?? ""))
  ) {
    throw new Error("COMMERCE_SMOKE_HANDOFF_INVALID");
  }
  const app = initializeApp({
    projectId: options.projectId,
    credential: applicationDefault(),
  });
  const db = getFirestore(app);
  const deadline = Date.now() + options.timeoutMs;
  let evidence;
  let failures = ["PAYMENT_EVIDENCE_PENDING"];
  while (Date.now() <= deadline) {
    evidence = await readEvidence(db, handoff);
    failures = validateCommerceSmokeEvidence(evidence);
    if (failures.length === 0) break;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  if (!evidence || failures.length) {
    throw new Error(`COMMERCE_SMOKE_VERIFICATION_FAILED:${failures.join(",")}`);
  }
  await db.doc(`developmentCommerceSmokeRuns/${handoff.runId}`).update({
    status: "verified",
    verifiedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    evidence: {
      intentStatus: evidence.intent.status,
      providerEventCount: evidence.eventCount,
      settlementCount: evidence.settlementCount,
      refundCount: evidence.refundCount,
      notificationCount: evidence.notificationCount,
      reconciled: true,
    },
  });
  console.log(
    JSON.stringify({
      mode: "verify",
      projectId: options.projectId,
      runId: handoff.runId,
      flow: handoff.flow,
      verified: true,
      intentId: handoff.intentId,
      providerEventCount: evidence.eventCount,
      settlementCount: evidence.settlementCount,
      refundCount: evidence.refundCount,
      notificationCount: evidence.notificationCount,
    }),
  );
}

async function main() {
  await run(validateCommerceSmokeVerificationOptions(process.argv.slice(2)));
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  await main();
}
