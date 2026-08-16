import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  assertProjectMatchesEnvironment,
  paystackProviderMode,
  paystackSecret,
  resolveEnvironment,
} from "../lib/config/environment.js";

const sourceRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "src");

function withEnvironment(values, run) {
  const previous = new Map();
  for (const [key, value] of Object.entries(values)) {
    previous.set(key, process.env[key]);
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  try {
    return run();
  } finally {
    for (const [key, value] of previous) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

test("development rejects the production Firebase project", () => {
  assert.throws(
    () => assertProjectMatchesEnvironment("development", "pasella-ledger"),
    /DEVELOPMENT_FIREBASE_PROJECT_INVALID/,
  );
});

test("production rejects test Paystack mode", () => {
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "production",
      SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
      PAYSTACK_PROVIDER_MODE: "test",
    },
    () => {
      assert.throws(paystackProviderMode, /PRODUCTION_PAYSTACK_MODE_INVALID/);
    },
  );
});

test("development requires a test Paystack key", () => {
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "development",
      SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
      PAYSTACK_PROVIDER_MODE: "test",
      PAYSTACK_SECRET_KEY: "sk_live_wrong-environment",
    },
    () => {
      assert.throws(paystackSecret, /PAYSTACK_TEST_KEY_REQUIRED/);
    },
  );
});

test("local tests default to an isolated local environment", () => {
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: undefined,
      SPAZAONE_FIREBASE_PROJECT_ID: undefined,
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      assert.equal(resolveEnvironment(), "local");
    },
  );
});

test("bot-callable payment entrypoints bind the bot secret", () => {
  const entrypoints = [
    ["ecommerce/checkoutCart.ts", "checkoutCart"],
    ["payments/v2/ownedOrders.ts", "createOwnedOrderPaymentV2"],
    ["payments/v2/accountSettlements.ts", "createAccountSettlementLinkV2"],
    ["payments/v2/accountSettlements.ts", "createRepaymentPlanV2"],
    [
      "payments/v2/customerPaymentRequests.ts",
      "getCustomerPaymentRequestContextV1BotHttp",
    ],
    [
      "payments/v2/customerPaymentRequests.ts",
      "claimCustomerPaymentRequestDeliveryV1BotHttp",
    ],
    [
      "payments/v2/customerPaymentRequests.ts",
      "recordCustomerPaymentRequestDeliveryV1BotHttp",
    ],
    ["ecommerce/cancelOrder.ts", "cancelOrder"],
  ];
  for (const [relativePath, exportName] of entrypoints) {
    const source = readFileSync(join(sourceRoot, relativePath), "utf8");
    const start = source.indexOf(`export const ${exportName}`);
    assert.notEqual(start, -1, `${exportName} export missing`);
    const binding = source.slice(start, start + 260);
    assert.match(binding, /runWith\(\{ secrets: \[[^\]]*"PASELLA_BOT_TOKEN"/);
  }
});

test("merchant payment-request entrypoints require auth and App Check", () => {
  const source = readFileSync(
    join(sourceRoot, "payments/v2/customerPaymentRequests.ts"),
    "utf8",
  );
  assert.match(source, /requireAppCheck:\s*true/);
  for (const exportName of [
    "getCustomerPaymentRequestOverviewV1",
    "sendCustomerPaymentRequestV1",
    "getCustomerPaymentRequestStatusV1",
  ]) {
    const start = source.indexOf(`export const ${exportName}`);
    assert.notEqual(start, -1, `${exportName} export missing`);
    const endpoint = source.slice(start, start + 2_500);
    assert.match(endpoint, /authenticateMerchant\(/);
  }
  assert.doesNotMatch(
    source.slice(
      source.indexOf("export const getCustomerPaymentRequestOverviewV1"),
      source.indexOf("async function reserveRequest"),
    ),
    /api\.paystack\.co/,
  );
});

test("payment-request review is an admin and App Check protected command", () => {
  const source = readFileSync(join(sourceRoot, "payments/v2/admin.ts"), "utf8");
  const start = source.indexOf(
    "export const resolveCustomerPaymentRequestDeliveryReviewV1",
  );
  assert.notEqual(start, -1);
  const command = source.slice(start, start + 1_800);
  assert.match(command, /requireAdmin\(context\)/);
  assert.match(command, /if \(!context\.app\)/);
  assert.match(command, /paymentAdministrationAudit/);
});

test("billable settlement verification is app-attested and bank-only", () => {
  const source = readFileSync(
    join(sourceRoot, "payments/v2/merchantProfiles.ts"),
    "utf8",
  );
  const start = source.indexOf(
    "export const prepareMerchantSettlementProfileV2",
  );
  assert.notEqual(start, -1);
  const endpoint = source.slice(start, start + 4_000);
  assert.match(endpoint, /requireAppCheck:\s*true/);
  assert.match(
    endpoint,
    /assertStoreAccess\(uid, merchantId, \["owner", "admin"\]\)/,
  );
  assert.match(endpoint, /assertBankAccountOnlyVerificationPayload/);
  assert.match(source, /settlementVerificationAuthorizationDecision/);
  assert.doesNotMatch(source, /settlement_profile_auto_approved/);
  assert.ok(
    source.indexOf("initialAuthorizationDecision") <
      source.indexOf("https://api.paystack.co/bank"),
    "admin preauthorization must be checked before every Paystack bank API call",
  );
  assert.match(source, /https:\/\/api\.paystack\.co\/bank\/validate/);
  assert.doesNotMatch(source, /decision\/bin|authorization\/verify|\/card\//);
});
