#!/usr/bin/env node

import process from "node:process";
import { execFile } from "node:child_process";
import { pathToFileURL } from "node:url";
import { promisify } from "node:util";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const DEVELOPMENT_PROJECTS = new Set(["spazaone-dev", "spazaone-dev-za"]);
export const DEVELOPMENT_QA_MERCHANT_ID = "dev-seed-merchant";
const QA_EMAIL = "merchant-qa@spazaone.test";
const QA_CAPABILITIES = new Set([
  "campaign_credit",
  "merchant_order",
  "account_settlement",
  "supplier_order",
]);
const execFileAsync = promisify(execFile);

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

export function validateDevelopmentPaymentQaOptions(argv) {
  const args = argsMap(argv);
  const projectId = String(args.get("project") ?? "").trim();
  const runId = String(args.get("run-id") ?? "").trim();
  const execute = args.get("execute") === true;
  const verify = args.get("verify") === true;
  const rollback = args.get("rollback") === true;
  const capabilities = String(args.get("capabilities") ?? "campaign_credit")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  const testSubaccountCode = String(
    args.get("test-subaccount-code") ?? "",
  ).trim();
  if (!DEVELOPMENT_PROJECTS.has(projectId)) {
    throw new Error("Payment QA requires an explicit registered dev project.");
  }
  if ([execute, verify, rollback].filter(Boolean).length > 1) {
    throw new Error("Choose only one of --execute, --verify or --rollback.");
  }
  if (
    (execute || verify || rollback) &&
    !/^[A-Za-z0-9:_-]{1,120}$/.test(runId)
  ) {
    throw new Error("Payment QA mutations require an explicit --run-id.");
  }
  if (
    capabilities.length === 0 ||
    new Set(capabilities).size !== capabilities.length ||
    capabilities.some((capability) => !QA_CAPABILITIES.has(capability))
  ) {
    throw new Error("DEVELOPMENT_PAYMENT_QA_CAPABILITIES_INVALID");
  }
  const settlementCapabilitySelected = capabilities.some((capability) =>
    ["merchant_order", "account_settlement", "supplier_order"].includes(
      capability,
    ),
  );
  if (
    (execute || verify) &&
    settlementCapabilitySelected &&
    !/^ACCT_[A-Za-z0-9]+$/.test(testSubaccountCode)
  ) {
    throw new Error("DEVELOPMENT_PAYMENT_QA_TEST_SUBACCOUNT_REQUIRED");
  }
  return {
    projectId,
    runId: runId || `payment-qa-dry-${Date.now()}`,
    execute,
    verify,
    rollback,
    capabilities,
    testSubaccountCode,
    settlementCapabilitySelected,
  };
}

function capabilityMap(capabilities) {
  return Object.fromEntries(
    capabilities.map((capability) => [capability, true]),
  );
}

async function upsertSyntheticAuthUser(auth) {
  try {
    await auth.updateUser(DEVELOPMENT_QA_MERCHANT_ID, {
      email: QA_EMAIL,
      emailVerified: true,
      displayName: "SpazaOne Development Merchant",
      disabled: false,
    });
  } catch (error) {
    if (error?.code !== "auth/user-not-found") throw error;
    await auth.createUser({
      uid: DEVELOPMENT_QA_MERCHANT_ID,
      email: QA_EMAIL,
      emailVerified: true,
      displayName: "SpazaOne Development Merchant",
      disabled: false,
    });
  }
  await auth.setCustomUserClaims(DEVELOPMENT_QA_MERCHANT_ID, {
    developmentSeed: true,
  });
}

async function verifiedPaystackTestSubaccount(options) {
  if (!options.settlementCapabilitySelected) return null;
  let secret;
  try {
    const result = await execFileAsync(
      "firebase",
      [
        "--project",
        options.projectId,
        "functions:secrets:access",
        "PAYSTACK_SECRET_KEY",
      ],
      { encoding: "utf8", maxBuffer: 1024 * 1024 },
    );
    secret = String(result.stdout ?? "").trim();
  } catch {
    throw new Error("DEVELOPMENT_PAYMENT_QA_PAYSTACK_SECRET_UNAVAILABLE");
  }
  if (!/^sk_test_/.test(secret)) {
    throw new Error("DEVELOPMENT_PAYMENT_QA_PAYSTACK_TEST_KEY_REQUIRED");
  }
  const response = await fetch(
    `https://api.paystack.co/subaccount/${encodeURIComponent(options.testSubaccountCode)}`,
    { headers: { authorization: `Bearer ${secret}` } },
  );
  const payload = await response.json().catch(() => ({}));
  const account = payload?.data ?? {};
  if (
    !response.ok ||
    payload?.status !== true ||
    account.domain !== "test" ||
    account.currency !== "ZAR" ||
    account.active !== true ||
    account.subaccount_code !== options.testSubaccountCode ||
    account.business_name !== "SpazaOne Development Merchant"
  ) {
    throw new Error("DEVELOPMENT_PAYMENT_QA_TEST_SUBACCOUNT_INVALID");
  }
  const accountNumber = String(account.account_number ?? "");
  if (!/^\d{6,20}$/.test(accountNumber)) {
    throw new Error("DEVELOPMENT_PAYMENT_QA_TEST_SUBACCOUNT_INVALID");
  }
  return {
    code: options.testSubaccountCode,
    bankName: String(account.settlement_bank ?? ""),
    resolvedAccountName: String(
      account.account_name ?? account.business_name ?? "",
    ),
    accountLast4: accountNumber.slice(-4),
  };
}

async function run(options) {
  if (!options.execute && !options.verify && !options.rollback) {
    console.log(
      JSON.stringify({
        mode: "dry-run",
        projectId: options.projectId,
        runId: options.runId,
        synthetic: true,
        merchantId: DEVELOPMENT_QA_MERCHANT_ID,
        globalCapabilities: options.capabilities,
        settlementCapabilitySelected: options.settlementCapabilitySelected,
        testSubaccountRequired: options.settlementCapabilitySelected,
        writesPlanned: 4,
      }),
    );
    return;
  }

  const testSubaccount =
    options.execute || options.verify
      ? await verifiedPaystackTestSubaccount(options)
      : null;

  const app = initializeApp({
    projectId: options.projectId,
    credential: applicationDefault(),
  });
  const db = getFirestore(app);
  const auth = getAuth(app);
  const configRef = db.doc("paymentConfiguration/global");
  const profileRef = db.doc(
    `merchantPaymentProfiles/${DEVELOPMENT_QA_MERCHANT_ID}`,
  );
  const runRef = db.doc(`developmentPaymentQaRuns/${options.runId}`);

  if (options.verify) {
    const [config, profile, qaRun, user] = await Promise.all([
      configRef.get(),
      profileRef.get(),
      runRef.get(),
      auth.getUser(DEVELOPMENT_QA_MERCHANT_ID),
    ]);
    const valid =
      qaRun.get("status") === "active" &&
      qaRun.get("projectId") === options.projectId &&
      options.capabilities.every(
        (capability) => config.get(`capabilities.${capability}`) === true,
      ) &&
      config.get("emergencySuspended") === false &&
      profile.get("status") === "enabled" &&
      options.capabilities.every(
        (capability) => profile.get(`capabilities.${capability}`) === true,
      ) &&
      JSON.stringify(qaRun.get("capabilities") ?? []) ===
        JSON.stringify(options.capabilities) &&
      (!options.settlementCapabilitySelected ||
        (qaRun.get("testSubaccountCode") === testSubaccount?.code &&
          profile.get("bankVerificationStatus") === "approved" &&
          profile.get("paystackSubaccountCode") === testSubaccount?.code &&
          profile.get("bankName") === testSubaccount?.bankName &&
          profile.get("accountLast4") === testSubaccount?.accountLast4)) &&
      user.email === QA_EMAIL &&
      user.customClaims?.developmentSeed === true;
    if (!valid) throw new Error("DEVELOPMENT_PAYMENT_QA_VERIFICATION_FAILED");
    console.log(
      JSON.stringify({
        mode: "verify",
        projectId: options.projectId,
        runId: options.runId,
        verified: true,
      }),
    );
    return;
  }

  if (options.rollback) {
    await db.runTransaction(async (tx) => {
      const runSnapshot = await tx.get(runRef);
      if (!runSnapshot.exists)
        throw new Error("DEVELOPMENT_PAYMENT_QA_RUN_NOT_FOUND");
      if (runSnapshot.get("status") === "rolled_back") return;
      if (
        runSnapshot.get("projectId") !== options.projectId ||
        runSnapshot.get("merchantId") !== DEVELOPMENT_QA_MERCHANT_ID
      ) {
        throw new Error("DEVELOPMENT_PAYMENT_QA_RUN_BINDING_MISMATCH");
      }
      const previousConfig = runSnapshot.get("previousConfig");
      const previousProfile = runSnapshot.get("previousProfile");
      if (previousConfig == null) tx.delete(configRef);
      else tx.set(configRef, previousConfig, { merge: false });
      if (previousProfile == null) tx.delete(profileRef);
      else tx.set(profileRef, previousProfile, { merge: false });
      tx.update(runRef, {
        status: "rolled_back",
        rolledBackAt: FieldValue.serverTimestamp(),
      });
    });
    console.log(
      JSON.stringify({
        mode: "rollback",
        projectId: options.projectId,
        runId: options.runId,
        rolledBack: true,
      }),
    );
    return;
  }

  await upsertSyntheticAuthUser(auth);
  let deduped = false;
  await db.runTransaction(async (tx) => {
    const [existingRun, previousConfig, previousProfile] = await Promise.all([
      tx.get(runRef),
      tx.get(configRef),
      tx.get(profileRef),
    ]);
    if (existingRun.exists) {
      if (
        existingRun.get("projectId") !== options.projectId ||
        existingRun.get("merchantId") !== DEVELOPMENT_QA_MERCHANT_ID
      ) {
        throw new Error("DEVELOPMENT_PAYMENT_QA_RUN_BINDING_MISMATCH");
      }
      if (
        JSON.stringify(existingRun.get("capabilities") ?? []) !==
          JSON.stringify(options.capabilities) ||
        String(existingRun.get("testSubaccountCode") ?? "") !==
          String(testSubaccount?.code ?? "")
      ) {
        throw new Error("DEVELOPMENT_PAYMENT_QA_RUN_BINDING_MISMATCH");
      }
      if (existingRun.get("status") !== "active") {
        throw new Error("DEVELOPMENT_PAYMENT_QA_RUN_ALREADY_ROLLED_BACK");
      }
      deduped = true;
      return;
    }
    const now = FieldValue.serverTimestamp();
    tx.set(
      configRef,
      {
        capabilities: capabilityMap(options.capabilities),
        emergencySuspended: false,
        schemaVersion: 2,
        synthetic: true,
        developmentPaymentQaRunId: options.runId,
        updatedBy: "development-payment-qa",
        updatedAt: now,
      },
      { merge: true },
    );
    tx.set(
      profileRef,
      {
        merchantId: DEVELOPMENT_QA_MERCHANT_ID,
        status: "enabled",
        capabilities: capabilityMap(options.capabilities),
        bankVerificationStatus: testSubaccount ? "approved" : "not_started",
        ...(testSubaccount
          ? {
              paystackSubaccountCode: testSubaccount.code,
              bankName: testSubaccount.bankName,
              resolvedAccountName: testSubaccount.resolvedAccountName,
              accountLast4: testSubaccount.accountLast4,
              verificationSource: "paystack_test_api",
            }
          : {}),
        schemaVersion: 2,
        synthetic: true,
        developmentPaymentQaRunId: options.runId,
        updatedBy: "development-payment-qa",
        updatedAt: now,
      },
      { merge: true },
    );
    tx.create(runRef, {
      runId: options.runId,
      projectId: options.projectId,
      merchantId: DEVELOPMENT_QA_MERCHANT_ID,
      status: "active",
      synthetic: true,
      capabilities: options.capabilities,
      testSubaccountCode: testSubaccount?.code ?? null,
      previousConfig: previousConfig.exists ? previousConfig.data() : null,
      previousProfile: previousProfile.exists ? previousProfile.data() : null,
      createdAt: now,
    });
  });
  console.log(
    JSON.stringify({
      mode: "execute",
      projectId: options.projectId,
      runId: options.runId,
      merchantId: DEVELOPMENT_QA_MERCHANT_ID,
      synthetic: true,
      deduped,
    }),
  );
}

async function main() {
  await run(validateDevelopmentPaymentQaOptions(process.argv.slice(2)));
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  await main();
}
