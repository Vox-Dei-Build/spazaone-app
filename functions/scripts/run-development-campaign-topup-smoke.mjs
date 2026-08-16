#!/usr/bin/env node

import process from "node:process";
import { chmod, readFile, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const DEVELOPMENT_PROJECTS = new Set(["spazaone-dev", "spazaone-dev-za"]);
const MERCHANT_ID = "dev-seed-merchant";
export const DEVELOPMENT_PAYSTACK_EMAIL = "payments-test@spazaone.com";
const CHANNELS = new Set(["eft", "capitec_pay", "qr"]);

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

export function validateDevelopmentCampaignSmokeOptions(argv) {
  const args = argsMap(argv);
  const projectId = String(args.get("project") ?? "").trim();
  const runId = String(args.get("run-id") ?? "").trim();
  const output = String(args.get("output") ?? "").trim();
  const execute = args.get("execute") === true;
  const channel = String(args.get("channel") ?? "eft").trim();
  const creditAmountMinor = Number(args.get("credit-minor") ?? 1000);
  if (!DEVELOPMENT_PROJECTS.has(projectId)) {
    throw new Error("Campaign smoke requires an explicit registered dev project.");
  }
  if (!CHANNELS.has(channel)) throw new Error("CAMPAIGN_SMOKE_CHANNEL_INVALID");
  if (
    !Number.isSafeInteger(creditAmountMinor) ||
    creditAmountMinor <= 0 ||
    creditAmountMinor > 100_000
  ) {
    throw new Error("CAMPAIGN_SMOKE_AMOUNT_INVALID");
  }
  if (execute) {
    if (!/^[A-Za-z0-9:_-]{12,120}$/.test(runId)) {
      throw new Error("Campaign smoke execute requires an explicit --run-id.");
    }
    if (!isAbsolute(output)) {
      throw new Error("Campaign smoke execute requires an absolute --output path.");
    }
  }
  return {
    projectId,
    runId: runId || `campaign-smoke-dry-${Date.now()}`,
    output,
    execute,
    channel,
    creditAmountMinor,
  };
}

async function publicApiKey() {
  const scriptDirectory = dirname(fileURLToPath(import.meta.url));
  const configPath = join(
    scriptDirectory,
    "..",
    "..",
    "android",
    "app",
    "src",
    "development",
    "google-services.json",
  );
  const config = JSON.parse(await readFile(configPath, "utf8"));
  const key = String(config.client?.[0]?.api_key?.[0]?.current_key ?? "").trim();
  if (!key) throw new Error("DEVELOPMENT_FIREBASE_PUBLIC_KEY_MISSING");
  return key;
}

async function responseJson(response, code) {
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(code);
  return payload;
}

export function unwrapCallableResult(payload) {
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

export function developmentOperatorPath(merchantId, uid) {
  if (merchantId !== MERCHANT_ID || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    throw new Error("DEVELOPMENT_OPERATOR_BINDING_INVALID");
  }
  return `stores/${merchantId}/operators/${uid}`;
}

async function createTemporaryDevelopmentSession(apiKey) {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const payload = await responseJson(
    response,
    "DEVELOPMENT_ANONYMOUS_AUTH_FAILED",
  );
  const uid = String(payload.localId ?? "").trim();
  const idToken = String(payload.idToken ?? "").trim();
  if (!uid || !idToken) throw new Error("DEVELOPMENT_ANONYMOUS_AUTH_INVALID");
  return { uid, idToken };
}

async function run(options) {
  if (!options.execute) {
    console.log(
      JSON.stringify({
        mode: "dry-run",
        projectId: options.projectId,
        runId: options.runId,
        merchantId: MERCHANT_ID,
        channel: options.channel,
        creditAmountMinor: options.creditAmountMinor,
        externalTransactionPlanned: true,
      }),
    );
    return;
  }

  const origin = `https://us-central1-${options.projectId}.cloudfunctions.net`;
  const environmentResponse = await fetch(`${origin}/getEnvironmentInfo`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ data: {} }),
  });
  const environment = unwrapCallableResult(
    await responseJson(
      environmentResponse,
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

  const app = initializeApp({
    projectId: options.projectId,
    credential: applicationDefault(),
  });
  const auth = getAuth(app);
  const db = getFirestore(app);
  const apiKey = await publicApiKey();
  const session = await createTemporaryDevelopmentSession(apiKey);
  const operatorRef = db.doc(developmentOperatorPath(MERCHANT_ID, session.uid));
  let createdIntentId = "";
  try {
    await operatorRef.set({
      uid: session.uid,
      storeId: MERCHANT_ID,
      role: "owner",
      status: "active",
      synthetic: true,
      developmentPaymentQaRunId: options.runId,
      createdAt: FieldValue.serverTimestamp(),
    });
    const authorization = { authorization: `Bearer ${session.idToken}` };
    const requestBody = {
      storeId: MERCHANT_ID,
      merchantId: MERCHANT_ID,
      creditAmountMinor: options.creditAmountMinor,
      channel: options.channel,
    };
    const quoteResponse = await fetch(`${origin}/getCampaignTopupQuoteV2`, {
      method: "POST",
      headers: { ...authorization, "content-type": "application/json" },
      body: JSON.stringify(requestBody),
    });
    const quote = await responseJson(
      quoteResponse,
      "CAMPAIGN_SMOKE_QUOTE_FAILED",
    );

    const createResponse = await fetch(`${origin}/createCampaignTopupV2`, {
      method: "POST",
      headers: { ...authorization, "content-type": "application/json" },
      body: JSON.stringify({
        ...requestBody,
        email: DEVELOPMENT_PAYSTACK_EMAIL,
        idempotencyKey: `development-smoke:${options.runId}`,
      }),
    });
    const created = await responseJson(
      createResponse,
      "CAMPAIGN_SMOKE_INITIALIZATION_FAILED",
    );
    const authorizationUrl = new URL(String(created.authorizationUrl ?? ""));
    if (
      authorizationUrl.protocol !== "https:" ||
      authorizationUrl.hostname !== "checkout.paystack.com"
    ) {
      throw new Error("CAMPAIGN_SMOKE_CHECKOUT_URL_INVALID");
    }
    if (!/^pi_[a-f0-9]{64}$/.test(String(created.intentId ?? ""))) {
      throw new Error("CAMPAIGN_SMOKE_INTENT_INVALID");
    }
    createdIntentId = String(created.intentId);
    await writeFile(
      options.output,
      `${JSON.stringify({
        authorizationUrl: authorizationUrl.toString(),
        reference: String(created.reference ?? ""),
        intentId: String(created.intentId),
        quote,
      })}\n`,
      { mode: 0o600 },
    );
    await chmod(options.output, 0o600);
  } finally {
    await Promise.allSettled([
      operatorRef.delete(),
      auth.deleteUser(session.uid),
    ]);
  }
  console.log(
    JSON.stringify({
      mode: "execute",
      projectId: options.projectId,
      runId: options.runId,
      initialized: true,
      intentId: createdIntentId,
      output: options.output,
    }),
  );
}

async function main() {
  await run(validateDevelopmentCampaignSmokeOptions(process.argv.slice(2)));
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  await main();
}
