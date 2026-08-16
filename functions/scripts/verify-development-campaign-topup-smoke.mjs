#!/usr/bin/env node

import process from "node:process";
import { readFile, stat } from "node:fs/promises";
import { isAbsolute } from "node:path";
import { pathToFileURL } from "node:url";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

const DEVELOPMENT_PROJECTS = new Set(["spazaone-dev", "spazaone-dev-za"]);
const MERCHANT_ID = "dev-seed-merchant";

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

export function validateCampaignSmokeVerificationOptions(argv) {
  const args = argsMap(argv);
  const projectId = String(args.get("project") ?? "").trim();
  const handoff = String(args.get("handoff") ?? "").trim();
  const timeoutMs = Number(args.get("timeout-ms") ?? 45_000);
  if (!DEVELOPMENT_PROJECTS.has(projectId)) {
    throw new Error("Verification requires an explicit registered dev project.");
  }
  if (!isAbsolute(handoff)) {
    throw new Error("Verification requires an absolute --handoff path.");
  }
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1_000 || timeoutMs > 60_000) {
    throw new Error("CAMPAIGN_SMOKE_VERIFY_TIMEOUT_INVALID");
  }
  return { projectId, handoff, timeoutMs };
}

export function validateCampaignTopupEvidence(input) {
  const {
    intent,
    event,
    purchase,
    operation,
    transaction,
    wallet,
    eventCount,
    operatorExists,
    authUserExists,
    handoff,
  } = input;
  const expectedCreditMinor = Number(handoff.quote?.creditAmountMinor);
  const expectedGrossMinor = Number(handoff.quote?.totalChargeMinor);
  const expectedFeeMinor = Number(handoff.quote?.providerFeeMinor);
  const actualProviderFeeMinor = Number(purchase.actualProviderFeeMinor);
  const intentId = String(handoff.intentId ?? "");
  const reference = String(handoff.reference ?? "");
  const appliedEvents = Array.isArray(intent.appliedProviderEventIds)
    ? intent.appliedProviderEventIds.map(String)
    : [];
  const failures = [];
  const expect = (condition, code) => {
    if (!condition) failures.push(code);
  };

  expect(intent.status === "paid", "INTENT_NOT_PAID");
  expect(intent.purpose === "campaign_credit", "INTENT_PURPOSE_MISMATCH");
  expect(intent.merchantId === MERCHANT_ID, "INTENT_MERCHANT_MISMATCH");
  expect(intent.expectedAmountMinor === expectedGrossMinor, "INTENT_GROSS_MISMATCH");
  expect(intent.campaignCreditAmountMinor === expectedCreditMinor, "INTENT_CREDIT_MISMATCH");
  expect(intent.money?.providerFeeMinor === expectedFeeMinor, "INTENT_FEE_MISMATCH");
  expect(intent.providerReference === reference, "INTENT_REFERENCE_MISMATCH");
  expect(appliedEvents.length === 1, "INTENT_EVENT_COUNT_MISMATCH");
  expect(eventCount === 1, "PROVIDER_EVENT_COUNT_MISMATCH");
  expect(event.processingState === "applied", "PROVIDER_EVENT_NOT_APPLIED");
  expect(event.eventType === "charge.success", "PROVIDER_EVENT_TYPE_MISMATCH");
  expect(event.intentId === intentId, "PROVIDER_EVENT_INTENT_MISMATCH");
  expect(event.reference === reference, "PROVIDER_EVENT_REFERENCE_MISMATCH");
  expect(purchase.intentId === intentId, "PURCHASE_INTENT_MISMATCH");
  expect(purchase.creditAmountMinor === expectedCreditMinor, "PURCHASE_CREDIT_MISMATCH");
  expect(purchase.grossAmountMinor === expectedGrossMinor, "PURCHASE_GROSS_MISMATCH");
  expect(
    actualProviderFeeMinor === expectedFeeMinor,
    "PROVIDER_FEE_VARIANCE",
  );
  expect(
    expectedGrossMinor - actualProviderFeeMinor === expectedCreditMinor,
    "TOPUP_NET_PROCEEDS_MISMATCH",
  );
  expect(purchase.reference === reference, "PURCHASE_REFERENCE_MISMATCH");
  expect(purchase.source === "paystack_v2", "PURCHASE_SOURCE_MISMATCH");
  expect(operation.kind === "paystack-topup", "OPERATION_KIND_MISMATCH");
  expect(operation.delta === expectedCreditMinor / 100, "OPERATION_DELTA_MISMATCH");
  expect(
    Math.round((Number(operation.balanceAfter) - Number(operation.balanceBefore)) * 100) ===
      expectedCreditMinor,
    "OPERATION_BALANCE_MOVEMENT_MISMATCH",
  );
  expect(wallet.virtualBalance === operation.balanceAfter, "WALLET_BALANCE_MISMATCH");
  expect(transaction.intentId === intentId, "TRANSACTION_INTENT_MISMATCH");
  expect(transaction.reference === reference, "TRANSACTION_REFERENCE_MISMATCH");
  expect(transaction.creditAmountMinor === expectedCreditMinor, "TRANSACTION_CREDIT_MISMATCH");
  expect(transaction.grossAmountMinor === expectedGrossMinor, "TRANSACTION_GROSS_MISMATCH");
  expect(transaction.providerFeeMinor === actualProviderFeeMinor, "TRANSACTION_FEE_MISMATCH");
  expect(transaction.status === "success", "TRANSACTION_STATUS_MISMATCH");
  expect(transaction.source === "paystack_v2", "TRANSACTION_SOURCE_MISMATCH");
  expect(operatorExists === false, "TEMPORARY_OPERATOR_NOT_REMOVED");
  expect(authUserExists === false, "TEMPORARY_AUTH_USER_NOT_REMOVED");

  if (failures.length) throw new Error(failures.join(","));
  return {
    intentId,
    reference,
    expectedCreditMinor,
    expectedGrossMinor,
    expectedFeeMinor,
    actualProviderFeeMinor,
    eventCount,
  };
}

const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

async function authUserExists(auth, uid) {
  try {
    await auth.getUser(uid);
    return true;
  } catch (error) {
    if (error?.code === "auth/user-not-found") return false;
    throw error;
  }
}

async function readEvidence(db, auth, handoff) {
  const intentId = String(handoff.intentId ?? "");
  const reference = String(handoff.reference ?? "");
  if (!/^pi_[a-f0-9]{64}$/.test(intentId) || !/^[A-Za-z0-9_-]{1,200}$/.test(reference)) {
    throw new Error("CAMPAIGN_SMOKE_HANDOFF_INVALID");
  }
  const intentSnapshot = await db.doc(`paymentIntents/${intentId}`).get();
  const intent = intentSnapshot.data() ?? {};
  const eventId = Array.isArray(intent.appliedProviderEventIds)
    ? String(intent.appliedProviderEventIds[0] ?? "")
    : "";
  const initiatedBy = String(intent.initiatedBy ?? "");
  const eventQuery = await db
    .collection("paymentEvents")
    .where("intentId", "==", intentId)
    .get();
  const [event, purchase, operation, transaction, wallet, operator] =
    await Promise.all([
      eventId ? db.doc(`paymentEvents/${eventId}`).get() : null,
      db.doc(`campaignCreditPurchases/${intentId}`).get(),
      db
        .doc(
          `campaignWalletOperations/${MERCHANT_ID}/entries/paystack-v2:${intentId}`,
        )
        .get(),
      db.doc(`users/${MERCHANT_ID}/topUpTransactions/${reference}`).get(),
      db.doc(`users/${MERCHANT_ID}/wallet/current`).get(),
      initiatedBy
        ? db.doc(`stores/${MERCHANT_ID}/operators/${initiatedBy}`).get()
        : null,
    ]);
  return {
    intent,
    event: event?.data() ?? {},
    purchase: purchase.data() ?? {},
    operation: operation.data() ?? {},
    transaction: transaction.data() ?? {},
    wallet: wallet.data() ?? {},
    eventCount: eventQuery.size,
    operatorExists: operator?.exists ?? false,
    authUserExists: initiatedBy ? await authUserExists(auth, initiatedBy) : false,
    handoff,
  };
}

async function main() {
  const options = validateCampaignSmokeVerificationOptions(process.argv.slice(2));
  const file = await stat(options.handoff);
  if ((file.mode & 0o077) !== 0) throw new Error("CAMPAIGN_SMOKE_HANDOFF_PERMISSIONS_INVALID");
  const handoff = JSON.parse(await readFile(options.handoff, "utf8"));
  const app = initializeApp({
    projectId: options.projectId,
    credential: applicationDefault(),
  });
  const db = getFirestore(app);
  const auth = getAuth(app);
  const deadline = Date.now() + options.timeoutMs;
  let lastError = new Error("CAMPAIGN_SMOKE_EVIDENCE_NOT_READY");
  while (Date.now() <= deadline) {
    try {
      const verified = validateCampaignTopupEvidence(
        await readEvidence(db, auth, handoff),
      );
      console.log(
        JSON.stringify({
          mode: "verify",
          projectId: options.projectId,
          verified: true,
          ...verified,
        }),
      );
      return;
    } catch (error) {
      lastError = error;
      await delay(1_500);
    }
  }
  throw lastError;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
