#!/usr/bin/env node

import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import process from "node:process";
import { chmod, writeFile } from "node:fs/promises";
import { isAbsolute } from "node:path";
import { pathToFileURL } from "node:url";
import { promisify } from "node:util";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const execFileAsync = promisify(execFile);
const DEVELOPMENT_PROJECTS = new Set(["spazaone-dev", "spazaone-dev-za"]);
const FLOWS = new Set(["owned_order", "account_settlement"]);
const CHANNELS = new Set(["card", "eft", "capitec_pay", "qr"]);
const MERCHANT_ID = "dev-seed-merchant";
const ACCOUNT_CUSTOMER_ID = "dev-seed-customer";
const PRODUCT_ID = "dev-seed-owned-product";
const BUYER_EMAIL = "payments-test@spazaone.com";

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

export function validateDevelopmentCommerceSmokeOptions(argv) {
  const args = argsMap(argv);
  const projectId = String(args.get("project") ?? "").trim();
  const runId = String(args.get("run-id") ?? "").trim();
  const flow = String(args.get("flow") ?? "").trim();
  const output = String(args.get("output") ?? "").trim();
  const channel = String(args.get("channel") ?? "eft").trim();
  const amountMinor = Number(args.get("amount-minor") ?? 4_000);
  const execute = args.get("execute") === true;
  if (!DEVELOPMENT_PROJECTS.has(projectId)) {
    throw new Error(
      "Commerce smoke requires an explicit registered dev project.",
    );
  }
  if (!FLOWS.has(flow)) throw new Error("COMMERCE_SMOKE_FLOW_INVALID");
  if (!CHANNELS.has(channel)) throw new Error("COMMERCE_SMOKE_CHANNEL_INVALID");
  if (
    !Number.isSafeInteger(amountMinor) ||
    amountMinor < 100 ||
    amountMinor > 100_000
  ) {
    throw new Error("COMMERCE_SMOKE_AMOUNT_INVALID");
  }
  if (execute) {
    if (!/^[A-Za-z0-9:_-]{12,120}$/.test(runId)) {
      throw new Error("Commerce smoke execute requires an explicit --run-id.");
    }
    if (!isAbsolute(output)) {
      throw new Error(
        "Commerce smoke execute requires an absolute --output path.",
      );
    }
  }
  return {
    projectId,
    runId: runId || `commerce-smoke-dry-${Date.now()}`,
    flow,
    output,
    channel,
    amountMinor,
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
    throw new Error("DEVELOPMENT_COMMERCE_SMOKE_SECRET_UNAVAILABLE");
  }
  if (!value) throw new Error("DEVELOPMENT_COMMERCE_SMOKE_SECRET_EMPTY");
  return value;
}

async function responseJson(response, code) {
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const detail = String(payload?.error ?? "").slice(0, 160);
    throw new Error(detail ? `${code}:${detail}` : code);
  }
  return payload;
}

function unwrapCallableResult(payload) {
  if (
    payload == null ||
    typeof payload !== "object" ||
    payload.result == null ||
    typeof payload.result !== "object"
  ) {
    throw new Error("DEVELOPMENT_ENVIRONMENT_CONTRACT_INVALID");
  }
  return payload.result;
}

function runDigest(runId) {
  return createHash("sha256").update(runId).digest("hex").slice(0, 20);
}

async function writeHandoff(options, data) {
  await writeFile(options.output, `${JSON.stringify(data)}\n`, { mode: 0o600 });
  await chmod(options.output, 0o600);
}

async function assertEnvironment(options, origin) {
  const response = await fetch(`${origin}/getEnvironmentInfo`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ data: {} }),
  });
  const environment = unwrapCallableResult(
    await responseJson(
      response,
      "DEVELOPMENT_ENVIRONMENT_CONTRACT_UNAVAILABLE",
    ),
  );
  if (
    environment.environment !== "development" ||
    environment.firebaseProjectId !== options.projectId ||
    environment.providerModes?.paystack !== "test"
  ) {
    throw new Error("DEVELOPMENT_ENVIRONMENT_CONTRACT_MISMATCH");
  }
}

async function existingHandoff(db, options, runSnapshot) {
  if (
    runSnapshot.get("projectId") !== options.projectId ||
    runSnapshot.get("flow") !== options.flow
  ) {
    throw new Error("DEVELOPMENT_COMMERCE_SMOKE_RUN_BINDING_MISMATCH");
  }
  const intentId = String(runSnapshot.get("intentId") ?? "");
  const intent = await db.doc(`paymentIntents/${intentId}`).get();
  const authorizationUrl = String(intent.get("authorizationUrl") ?? "");
  if (!intent.exists || !authorizationUrl) {
    throw new Error("DEVELOPMENT_COMMERCE_SMOKE_RUN_INCOMPLETE");
  }
  return {
    flow: options.flow,
    projectId: options.projectId,
    runId: options.runId,
    merchantId: MERCHANT_ID,
    customerId: String(runSnapshot.get("customerId") ?? ""),
    orderId: String(runSnapshot.get("orderId") ?? ""),
    reservationId: String(runSnapshot.get("reservationId") ?? ""),
    intentId,
    reference: String(intent.get("providerReference") ?? ""),
    authorizationUrl,
    amountMinor: Number(intent.get("expectedAmountMinor")),
    channel: String(intent.get("selectedChannel") ?? ""),
    balanceBefore: Number(runSnapshot.get("balanceBefore") ?? 0),
    productQuantityBefore: Number(
      runSnapshot.get("productQuantityBefore") ?? 0,
    ),
  };
}

async function runOwnedOrder(options, context) {
  const digest = runDigest(options.runId);
  const customerId = `smoke-customer-${digest}`;
  const customerRef = context.db.doc(
    `users/${MERCHANT_ID}/customers/${customerId}`,
  );
  const cartRef = context.db.doc(`users/${MERCHANT_ID}/carts/${customerId}`);
  const itemRef = cartRef.collection("items").doc(PRODUCT_ID);
  const productRef = context.db.doc(
    `users/${MERCHANT_ID}/products/${PRODUCT_ID}`,
  );
  const product = await productRef.get();
  if (!product.exists || product.get("synthetic") !== true) {
    throw new Error("DEVELOPMENT_OWNED_PRODUCT_MISSING");
  }
  const productQuantityBefore = Number(product.get("quantity"));
  if (
    !Number.isSafeInteger(productQuantityBefore) ||
    productQuantityBefore < 1
  ) {
    throw new Error("DEVELOPMENT_OWNED_PRODUCT_UNAVAILABLE");
  }
  const now = FieldValue.serverTimestamp();
  await Promise.all([
    customerRef.set(
      {
        name: "Synthetic Commerce Customer",
        number: "",
        email: BUYER_EMAIL,
        balance: 0,
        synthetic: true,
        developmentCommerceSmokeRunId: options.runId,
        createdAt: now,
        updatedAt: now,
      },
      { merge: true },
    ),
    cartRef.set(
      {
        merchantId: MERCHANT_ID,
        customerId,
        synthetic: true,
        developmentCommerceSmokeRunId: options.runId,
        updatedAt: now,
      },
      { merge: true },
    ),
    itemRef.set({
      productId: PRODUCT_ID,
      quantity: 1,
      synthetic: true,
      developmentCommerceSmokeRunId: options.runId,
      updatedAt: now,
    }),
  ]);
  const checkoutBody = {
    merchantId: MERCHANT_ID,
    customerId,
    paymentType: "Online",
    paymentRail: "paystack_v2",
    idempotencyKey: `commerce-smoke-${digest}`,
    orderChannel: "development_qa",
    fulfillmentType: "pickup",
  };
  const checkout = await responseJson(
    await fetch(`${context.origin}/checkoutCart`, {
      method: "POST",
      headers: context.headers,
      body: JSON.stringify(checkoutBody),
    }),
    "DEVELOPMENT_OWNED_CHECKOUT_FAILED",
  );
  const orderId = String(checkout.saleId ?? "");
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(orderId)) {
    throw new Error("DEVELOPMENT_OWNED_ORDER_INVALID");
  }
  const paymentBody = {
    merchantId: MERCHANT_ID,
    orderId,
    email: BUYER_EMAIL,
    channel: options.channel,
  };
  const first = await responseJson(
    await fetch(`${context.origin}/createOwnedOrderPaymentV2`, {
      method: "POST",
      headers: context.headers,
      body: JSON.stringify(paymentBody),
    }),
    "DEVELOPMENT_OWNED_PAYMENT_INITIALIZATION_FAILED",
  );
  const replay = await responseJson(
    await fetch(`${context.origin}/createOwnedOrderPaymentV2`, {
      method: "POST",
      headers: context.headers,
      body: JSON.stringify(paymentBody),
    }),
    "DEVELOPMENT_OWNED_PAYMENT_REPLAY_FAILED",
  );
  if (
    replay.intentId !== first.intentId ||
    replay.reference !== first.reference ||
    replay.authorizationUrl !== first.authorizationUrl ||
    replay.deduped !== true
  ) {
    throw new Error("DEVELOPMENT_OWNED_INITIALIZATION_NOT_IDEMPOTENT");
  }
  const sale = await context.db
    .doc(`users/${MERCHANT_ID}/sales/${orderId}`)
    .get();
  return {
    customerId,
    orderId,
    reservationId: String(sale.get("inventoryReservationId") ?? ""),
    productQuantityBefore,
    balanceBefore: 0,
    ...first,
  };
}

async function runAccountSettlement(options, context) {
  const customerRef = context.db.doc(
    `users/${MERCHANT_ID}/customers/${ACCOUNT_CUSTOMER_ID}`,
  );
  const [customer, openingCredit] = await Promise.all([
    customerRef.get(),
    customerRef.collection("transactions").doc("development_seed_credit").get(),
  ]);
  const balanceBefore = Number(customer.get("balance"));
  if (
    !customer.exists ||
    customer.get("synthetic") !== true ||
    !openingCredit.exists ||
    openingCredit.get("source") !== "development_seed" ||
    !Number.isFinite(balanceBefore) ||
    balanceBefore >= 0 ||
    options.amountMinor > Math.round(-balanceBefore * 100)
  ) {
    throw new Error("DEVELOPMENT_ACCOUNT_BALANCE_INVALID");
  }
  const digest = runDigest(options.runId);
  const paymentBody = {
    merchantId: MERCHANT_ID,
    customerId: ACCOUNT_CUSTOMER_ID,
    amountMinor: options.amountMinor,
    email: BUYER_EMAIL,
    channel: options.channel,
    idempotencyKey: `commerce-smoke-${digest}`,
  };
  const first = await responseJson(
    await fetch(`${context.origin}/createAccountSettlementLinkV2`, {
      method: "POST",
      headers: context.headers,
      body: JSON.stringify(paymentBody),
    }),
    "DEVELOPMENT_ACCOUNT_PAYMENT_INITIALIZATION_FAILED",
  );
  const replay = await responseJson(
    await fetch(`${context.origin}/createAccountSettlementLinkV2`, {
      method: "POST",
      headers: context.headers,
      body: JSON.stringify(paymentBody),
    }),
    "DEVELOPMENT_ACCOUNT_PAYMENT_REPLAY_FAILED",
  );
  if (
    replay.intentId !== first.intentId ||
    replay.reference !== first.reference ||
    replay.authorizationUrl !== first.authorizationUrl ||
    replay.deduped !== true
  ) {
    throw new Error("DEVELOPMENT_ACCOUNT_INITIALIZATION_NOT_IDEMPOTENT");
  }
  return {
    customerId: ACCOUNT_CUSTOMER_ID,
    orderId: "",
    reservationId: "",
    productQuantityBefore: 0,
    balanceBefore,
    ...first,
  };
}

async function run(options) {
  if (!options.execute) {
    console.log(
      JSON.stringify({
        mode: "dry-run",
        projectId: options.projectId,
        runId: options.runId,
        flow: options.flow,
        channel: options.channel,
        amountMinor:
          options.flow === "account_settlement" ? options.amountMinor : 1_600,
        synthetic: true,
        externalTransactionPlanned: true,
      }),
    );
    return;
  }
  const origin = `https://us-central1-${options.projectId}.cloudfunctions.net`;
  await assertEnvironment(options, origin);
  const app = initializeApp({
    projectId: options.projectId,
    credential: applicationDefault(),
  });
  const db = getFirestore(app);
  const runRef = db.doc(`developmentCommerceSmokeRuns/${options.runId}`);
  const existing = await runRef.get();
  if (existing.exists) {
    const handoff = await existingHandoff(db, options, existing);
    await writeHandoff(options, handoff);
    console.log(
      JSON.stringify({
        mode: "execute",
        projectId: options.projectId,
        runId: options.runId,
        flow: options.flow,
        initialized: true,
        deduped: true,
        intentId: handoff.intentId,
        output: options.output,
      }),
    );
    return;
  }
  const botToken = await firebaseSecret(options.projectId, "PASELLA_BOT_TOKEN");
  const context = {
    db,
    origin,
    headers: {
      "content-type": "application/json",
      "X-Pasella-Bot-Token": botToken,
    },
  };
  const initialized =
    options.flow === "owned_order"
      ? await runOwnedOrder(options, context)
      : await runAccountSettlement(options, context);
  const authorizationUrl = new URL(String(initialized.authorizationUrl ?? ""));
  const intentId = String(initialized.intentId ?? "");
  const reference = String(initialized.reference ?? "");
  if (
    authorizationUrl.protocol !== "https:" ||
    authorizationUrl.hostname !== "checkout.paystack.com" ||
    !/^pi_[a-f0-9]{64}$/.test(intentId) ||
    !reference
  ) {
    throw new Error("DEVELOPMENT_COMMERCE_SMOKE_HANDOFF_INVALID");
  }
  const handoff = {
    flow: options.flow,
    projectId: options.projectId,
    runId: options.runId,
    merchantId: MERCHANT_ID,
    customerId: initialized.customerId,
    orderId: initialized.orderId,
    reservationId: initialized.reservationId,
    intentId,
    reference,
    authorizationUrl: authorizationUrl.toString(),
    amountMinor: Number(initialized.amountMinor),
    channel: options.channel,
    balanceBefore: initialized.balanceBefore,
    productQuantityBefore: initialized.productQuantityBefore,
  };
  await runRef.create({
    ...handoff,
    authorizationUrl: null,
    status: "initialized",
    synthetic: true,
    schemaVersion: 2,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await writeHandoff(options, handoff);
  console.log(
    JSON.stringify({
      mode: "execute",
      projectId: options.projectId,
      runId: options.runId,
      flow: options.flow,
      initialized: true,
      deduped: false,
      intentId,
      output: options.output,
    }),
  );
}

async function main() {
  await run(validateDevelopmentCommerceSmokeOptions(process.argv.slice(2)));
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  await main();
}
