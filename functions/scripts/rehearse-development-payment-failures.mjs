#!/usr/bin/env node

import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import process from "node:process";
import { pathToFileURL } from "node:url";
import { promisify } from "node:util";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const execFileAsync = promisify(execFile);
const DEVELOPMENT_PROJECTS = new Set(["spazaone-dev", "spazaone-dev-za"]);
const MERCHANT_ID = "dev-seed-merchant";
const ACCOUNT_CUSTOMER_ID = "dev-seed-customer";

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

export function validateDevelopmentFailureRehearsalOptions(argv) {
  const args = argsMap(argv);
  const projectId = String(args.get("project") ?? "").trim();
  const runId = String(args.get("run-id") ?? "").trim();
  const execute = args.get("execute") === true;
  if (!DEVELOPMENT_PROJECTS.has(projectId)) {
    throw new Error(
      "Failure rehearsal requires an explicit registered dev project.",
    );
  }
  if (execute && !/^[A-Za-z0-9:_-]{12,120}$/.test(runId)) {
    throw new Error("Failure rehearsal execute requires an explicit --run-id.");
  }
  return {
    projectId,
    runId: runId || `payment-failure-dry-${Date.now()}`,
    execute,
  };
}

async function firebaseSecret(projectId, name) {
  let value;
  try {
    const result = await execFileAsync(
      "firebase",
      ["--project", projectId, "functions:secrets:access", name],
      { encoding: "utf8", maxBuffer: 1024 * 1024 },
    );
    value = String(result.stdout ?? "").trim();
  } catch {
    throw new Error("DEVELOPMENT_FAILURE_REHEARSAL_SECRET_UNAVAILABLE");
  }
  if (!value) throw new Error("DEVELOPMENT_FAILURE_REHEARSAL_SECRET_EMPTY");
  return value;
}

async function callExpect(origin, functionName, body, headers, expectedStatus) {
  const response = await fetch(`${origin}/${functionName}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  if (response.status !== expectedStatus) {
    throw new Error(
      `DEVELOPMENT_FAILURE_REHEARSAL_UNEXPECTED_STATUS:${functionName}:${response.status}`,
    );
  }
  return { status: response.status, error: String(payload?.error ?? "") };
}

function digest(runId) {
  return createHash("sha256").update(runId).digest("hex").slice(0, 20);
}

async function run(options) {
  const planned = [
    "invalid_bot_authority",
    "global_kill_switch",
    "unverified_settlement_destination",
    "account_overpayment",
    "invalid_payment_channel",
    "owned_inventory_unavailable",
  ];
  if (!options.execute) {
    console.log(
      JSON.stringify({
        mode: "dry-run",
        projectId: options.projectId,
        runId: options.runId,
        scenarios: planned,
        providerChargePlanned: false,
        synthetic: true,
      }),
    );
    return;
  }
  const app = initializeApp({
    projectId: options.projectId,
    credential: applicationDefault(),
  });
  const db = getFirestore(app);
  const runRef = db.doc(`developmentPaymentFailureRuns/${options.runId}`);
  const existing = await runRef.get();
  if (existing.exists) {
    if (
      existing.get("projectId") !== options.projectId ||
      existing.get("status") !== "verified"
    ) {
      throw new Error("DEVELOPMENT_FAILURE_REHEARSAL_RUN_COLLISION");
    }
    console.log(
      JSON.stringify({
        mode: "execute",
        projectId: options.projectId,
        runId: options.runId,
        verified: true,
        deduped: true,
        scenarios: existing.get("scenarios"),
      }),
    );
    return;
  }
  const origin = `https://us-central1-${options.projectId}.cloudfunctions.net`;
  const token = await firebaseSecret(options.projectId, "PASELLA_BOT_TOKEN");
  const validHeaders = { "X-Pasella-Bot-Token": token };
  const digestValue = digest(options.runId);
  const accountBody = {
    merchantId: MERCHANT_ID,
    customerId: ACCOUNT_CUSTOMER_ID,
    amountMinor: 100,
    email: "payments-test@spazaone.com",
    channel: "eft",
    idempotencyKey: `failure-${digestValue}`,
  };
  const scenarios = {};

  scenarios.invalid_bot_authority = await callExpect(
    origin,
    "createAccountSettlementLinkV2",
    accountBody,
    { "X-Pasella-Bot-Token": "invalid-development-token" },
    401,
  );

  const configRef = db.doc("paymentConfiguration/global");
  const config = await configRef.get();
  const suspendedBefore = config.get("emergencySuspended") === true;
  try {
    await configRef.update({
      emergencySuspended: true,
      developmentFailureRehearsalRunId: options.runId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    scenarios.global_kill_switch = await callExpect(
      origin,
      "createAccountSettlementLinkV2",
      { ...accountBody, idempotencyKey: `kill-${digestValue}` },
      validHeaders,
      409,
    );
  } finally {
    await configRef.update({
      emergencySuspended: suspendedBefore,
      developmentFailureRehearsalRunId: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  const profileRef = db.doc(`merchantPaymentProfiles/${MERCHANT_ID}`);
  const profile = await profileRef.get();
  if (!profile.exists || profile.get("bankVerificationStatus") !== "approved") {
    throw new Error("DEVELOPMENT_FAILURE_REHEARSAL_PROFILE_NOT_APPROVED");
  }
  const profileBefore = profile.data();
  try {
    await profileRef.update({
      bankVerificationStatus: "pending_review",
      developmentFailureRehearsalRunId: options.runId,
      updatedAt: FieldValue.serverTimestamp(),
    });
    scenarios.unverified_settlement_destination = await callExpect(
      origin,
      "createAccountSettlementLinkV2",
      { ...accountBody, idempotencyKey: `bank-${digestValue}` },
      validHeaders,
      409,
    );
  } finally {
    await profileRef.set(profileBefore, { merge: false });
  }

  const customer = await db
    .doc(`users/${MERCHANT_ID}/customers/${ACCOUNT_CUSTOMER_ID}`)
    .get();
  const outstandingMinor = Math.round(
    Math.max(0, -Number(customer.get("balance") ?? 0)) * 100,
  );
  scenarios.account_overpayment = await callExpect(
    origin,
    "createAccountSettlementLinkV2",
    {
      ...accountBody,
      amountMinor: outstandingMinor + 100,
      idempotencyKey: `overpay-${digestValue}`,
    },
    validHeaders,
    409,
  );
  scenarios.invalid_payment_channel = await callExpect(
    origin,
    "createAccountSettlementLinkV2",
    {
      ...accountBody,
      channel: "cash",
      idempotencyKey: `channel-${digestValue}`,
    },
    validHeaders,
    400,
  );

  const customerId = `failure-customer-${digestValue}`;
  const productId = `failure-product-${digestValue}`;
  const customerRef = db.doc(`users/${MERCHANT_ID}/customers/${customerId}`);
  const productRef = db.doc(`users/${MERCHANT_ID}/products/${productId}`);
  const cartRef = db.doc(`users/${MERCHANT_ID}/carts/${customerId}`);
  const now = FieldValue.serverTimestamp();
  await Promise.all([
    customerRef.set({
      name: "Synthetic Unavailable Stock Customer",
      balance: 0,
      synthetic: true,
      developmentFailureRehearsalRunId: options.runId,
      createdAt: now,
      updatedAt: now,
    }),
    productRef.set({
      name: "Synthetic unavailable product",
      sellingPrice: 16,
      quantity: 0,
      synthetic: true,
      developmentFailureRehearsalRunId: options.runId,
      createdAt: now,
      updatedAt: now,
    }),
    cartRef.set({
      customerId,
      merchantId: MERCHANT_ID,
      synthetic: true,
      developmentFailureRehearsalRunId: options.runId,
      updatedAt: now,
    }),
    cartRef.collection("items").doc(productId).set({
      productId,
      quantity: 1,
      synthetic: true,
      developmentFailureRehearsalRunId: options.runId,
      updatedAt: now,
    }),
  ]);
  const unavailable = await callExpect(
    origin,
    "checkoutCart",
    {
      merchantId: MERCHANT_ID,
      customerId,
      paymentType: "Online",
      paymentRail: "paystack_v2",
      idempotencyKey: `stock-${digestValue}`,
    },
    validHeaders,
    409,
  );
  const cancelledSales = await db
    .collection(`users/${MERCHANT_ID}/sales`)
    .where("customerId", "==", customerId)
    .get();
  if (
    cancelledSales.size !== 1 ||
    cancelledSales.docs[0].get("status") !== "cancelled" ||
    cancelledSales.docs[0].get("paymentStatus") !== "cancelled" ||
    String(cancelledSales.docs[0].get("paymentIntentId") ?? "")
  ) {
    throw new Error("DEVELOPMENT_STOCK_FAILURE_OUTCOME_INVALID");
  }
  const reservation = await db
    .collection("inventoryReservations")
    .where("orderId", "==", cancelledSales.docs[0].id)
    .get();
  if (!reservation.empty) {
    throw new Error("DEVELOPMENT_STOCK_FAILURE_RESERVED_INVENTORY");
  }
  scenarios.owned_inventory_unavailable = {
    ...unavailable,
    orderStatus: "cancelled",
    reservationCount: 0,
    providerIntentCreated: false,
  };

  const restoredConfig = await configRef.get();
  const restoredProfile = await profileRef.get();
  if (
    restoredConfig.get("emergencySuspended") !== suspendedBefore ||
    restoredProfile.get("bankVerificationStatus") !== "approved" ||
    restoredProfile.get("paystackSubaccountCode") !==
      profile.get("paystackSubaccountCode")
  ) {
    throw new Error("DEVELOPMENT_FAILURE_REHEARSAL_ROLLBACK_FAILED");
  }
  await runRef.create({
    runId: options.runId,
    projectId: options.projectId,
    merchantId: MERCHANT_ID,
    status: "verified",
    scenarios,
    providerChargeCreated: false,
    synthetic: true,
    schemaVersion: 2,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  console.log(
    JSON.stringify({
      mode: "execute",
      projectId: options.projectId,
      runId: options.runId,
      verified: true,
      deduped: false,
      providerChargeCreated: false,
      scenarios: Object.keys(scenarios),
    }),
  );
}

async function main() {
  await run(validateDevelopmentFailureRehearsalOptions(process.argv.slice(2)));
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  await main();
}
