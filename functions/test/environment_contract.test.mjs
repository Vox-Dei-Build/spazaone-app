import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  assertProjectMatchesEnvironment,
  paystackAccountPaymentCanaryEnabled,
  paystackCanaryIntentBindingValid,
  paystackPaymentProviderMode,
  paystackPaymentSecret,
  paystackProviderMode,
  paystackReadOnlySecret,
  paystackSecret,
  paystackSettlementVerificationSecret,
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

test("production payment kill switch keeps the governed verification lane available", () => {
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "production",
      SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
      PAYSTACK_PROVIDER_MODE: "disabled",
      PAYSTACK_SECRET_KEY: "sk_live_read-only-catalogue",
    },
    () => {
      assert.equal(paystackReadOnlySecret(), "sk_live_read-only-catalogue");
      assert.equal(
        paystackSettlementVerificationSecret(),
        "sk_live_read-only-catalogue",
      );
      assert.throws(paystackSecret, /PAYSTACK_PROVIDER_DISABLED/);
    },
  );
});

test("production account-payment canary is exact and leaves the global kill switch on", () => {
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "production",
      SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
      PAYSTACK_PROVIDER_MODE: "disabled",
      PAYSTACK_SECRET_KEY: "sk_live_account-payment-canary",
      PAYSTACK_ACCOUNT_PAYMENT_CANARY_ENABLED: "true",
      PAYSTACK_ACCOUNT_PAYMENT_CANARY_MERCHANT_ID: "merchant_canary",
    },
    () => {
      const canary = {
        merchantId: "merchant_canary",
        purpose: "account_settlement",
      };
      assert.equal(paystackProviderMode(), "disabled");
      assert.equal(paystackAccountPaymentCanaryEnabled(canary), true);
      assert.equal(paystackPaymentProviderMode(canary), "live");
      assert.equal(
        paystackPaymentSecret(canary),
        "sk_live_account-payment-canary",
      );
      assert.throws(paystackSecret, /PAYSTACK_PROVIDER_DISABLED/);

      for (const denied of [
        { merchantId: "merchant_other", purpose: "account_settlement" },
        { merchantId: "merchant_canary", purpose: "repayment_installment" },
        { merchantId: "merchant_canary", purpose: "merchant_order" },
        { merchantId: "merchant_canary", purpose: "supplier_order" },
        { merchantId: "merchant_canary", purpose: "campaign_credit" },
      ]) {
        assert.equal(paystackAccountPaymentCanaryEnabled(denied), false);
        assert.equal(paystackPaymentProviderMode(denied), "disabled");
        assert.throws(
          () => paystackPaymentSecret(denied),
          /PAYSTACK_PROVIDER_DISABLED/,
        );
      }
    },
  );
});

test("disabled-provider webhook requires the exact immutable canary binding", () => {
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "production",
      SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
      PAYSTACK_PROVIDER_MODE: "disabled",
      PAYSTACK_ACCOUNT_PAYMENT_CANARY_ENABLED: "true",
      PAYSTACK_ACCOUNT_PAYMENT_CANARY_MERCHANT_ID: "merchant_canary",
    },
    () => {
      const binding = {
        metadataMerchantId: "merchant_canary",
        metadataPurpose: "account_settlement",
        intentMerchantId: "merchant_canary",
        intentPurpose: "account_settlement",
        intentProviderMode: "live",
        intentActivationScope: "account_payment_canary",
      };
      assert.equal(paystackCanaryIntentBindingValid(binding), true);
      for (const override of [
        { metadataMerchantId: "merchant_other" },
        { metadataPurpose: "merchant_order" },
        { intentMerchantId: "merchant_other" },
        { intentPurpose: "repayment_installment" },
        { intentProviderMode: "test" },
        { intentActivationScope: "global" },
      ]) {
        assert.equal(
          paystackCanaryIntentBindingValid({ ...binding, ...override }),
          false,
        );
      }
    },
  );
});

test("live webhook gates the canary before any payment or quarantine mutation", () => {
  const source = readFileSync(
    join(sourceRoot, "payments/paystack/verifyPaystackTransaction.ts"),
    "utf8",
  );
  const gate = source.indexOf("!paystackCanaryIntentBindingValid");
  const currencyQuarantine = source.indexOf(
    'isQuarantinableV2Charge(transaction, "PROVIDER_CURRENCY_MISMATCH")',
  );
  const paymentDispatch = source.indexOf(
    "applyVerifiedAccountSettlementV2(",
    currencyQuarantine,
  );
  assert.ok(gate > 0);
  assert.ok(currencyQuarantine > gate);
  assert.ok(paymentDispatch > currencyQuarantine);
});

test("account-payment canary fails closed outside production or with a malformed merchant ID", () => {
  const context = {
    merchantId: "merchant_canary",
    purpose: "account_settlement",
  };
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "development",
      SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
      PAYSTACK_PROVIDER_MODE: "test",
      PAYSTACK_ACCOUNT_PAYMENT_CANARY_ENABLED: "true",
      PAYSTACK_ACCOUNT_PAYMENT_CANARY_MERCHANT_ID: "merchant_canary",
    },
    () => assert.equal(paystackAccountPaymentCanaryEnabled(context), false),
  );
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "production",
      SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
      PAYSTACK_PROVIDER_MODE: "disabled",
      PAYSTACK_ACCOUNT_PAYMENT_CANARY_ENABLED: "true",
      PAYSTACK_ACCOUNT_PAYMENT_CANARY_MERCHANT_ID: "merchant canary,*",
    },
    () => assert.equal(paystackAccountPaymentCanaryEnabled(context), false),
  );
});

test("production read-only Paystack access rejects a test key", () => {
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "production",
      SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
      PAYSTACK_PROVIDER_MODE: "disabled",
      PAYSTACK_SECRET_KEY: "sk_test_wrong-environment",
    },
    () => {
      assert.throws(paystackReadOnlySecret, /PAYSTACK_LIVE_KEY_REQUIRED/);
      assert.throws(
        paystackSettlementVerificationSecret,
        /PAYSTACK_LIVE_KEY_REQUIRED/,
      );
    },
  );
});

test("settlement verification cannot weaken the development key boundary", () => {
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "development",
      SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
      PAYSTACK_PROVIDER_MODE: "test",
      PAYSTACK_SECRET_KEY: "sk_live_wrong-environment",
    },
    () => {
      assert.throws(
        paystackSettlementVerificationSecret,
        /PAYSTACK_TEST_KEY_REQUIRED/,
      );
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
  assert.match(command, /requirePaymentAdmin\(context\)/);
  assert.match(command, /paymentAdministrationAudit/);
});

test("payment admin commands share the fail-closed portal policy", () => {
  const policy = readFileSync(
    join(sourceRoot, "payments/v2/paymentAdminAuth.ts"),
    "utf8",
  );
  assert.match(policy, /spazaAdmin/);
  assert.match(policy, /appCheckVerified/);
  assert.match(policy, /appCheckAlreadyConsumed/);
  assert.match(policy, /emailVerified/);
  assert.match(policy, /signInProvider/);
  assert.match(policy, /allowedEmails/);
  assert.match(policy, /allowedOrigins/);
  assert.match(policy, /PAYMENT_ADMIN_RECENT_AUTH_REQUIRED/);

  const admin = readFileSync(join(sourceRoot, "payments/v2/admin.ts"), "utf8");
  assert.doesNotMatch(admin, /function requireAdmin\(/);
  assert.match(admin, /requirePaymentAdmin\(context\)/);
  assert.match(admin, /consumeAppCheckToken:\s*true/);

  const profiles = readFileSync(
    join(sourceRoot, "payments/v2/merchantProfiles.ts"),
    "utf8",
  );
  const reviewStart = profiles.indexOf(
    "export const reviewMerchantSettlementProfileV2",
  );
  assert.notEqual(reviewStart, -1);
  assert.match(
    profiles.slice(reviewStart, reviewStart + 900),
    /requirePaymentAdmin\(context\)/,
  );
});

test("settlement detail is a recent-auth read without App Check token consumption", () => {
  const admin = readFileSync(join(sourceRoot, "payments/v2/admin.ts"), "utf8");
  const start = admin.indexOf(
    "export const getSettlementVerificationRequestDetailV1",
  );
  const end = admin.indexOf(
    "export const setGlobalPaymentConfigurationV2",
    start,
  );
  assert.notEqual(start, -1);
  assert.notEqual(end, -1);
  const detail = admin.slice(start, end);

  assert.match(detail, /paymentAdminReadRuntime\.https\.onCall/);
  assert.match(detail, /requirePaymentAdmin\(context\)/);
  assert.match(detail, /MERCHANT_RESUBMISSION_REQUIRED/);
  assert.doesNotMatch(detail, /requireRecentAuth:\s*false/);
  assert.doesNotMatch(detail, /paymentAdminMutationRuntime/);
});

test("settlement approval queue is server-only and masks its public projection", () => {
  const requests = readFileSync(
    join(sourceRoot, "payments/v2/settlementAdminRequests.ts"),
    "utf8",
  );
  assert.match(requests, /settlementAdminRequestProjection/);
  assert.match(requests, /maskedAccount/);
  assert.doesNotMatch(
    requests.slice(
      requests.indexOf(
        "return {",
        requests.indexOf("settlementAdminRequestProjection"),
      ),
    ),
    /merchantId|accountFingerprint|requestedBy|paystackSubaccountCode/,
  );
  const rules = readFileSync(
    join(sourceRoot, "..", "..", "firestore.rules"),
    "utf8",
  );
  assert.match(
    rules,
    /match \/paymentAdministrationRequests\/\{document=\*\*\}[\s\S]*?allow read, write: if false;/,
  );
});

test("merchant settlement responses do not expose account fingerprints", () => {
  const profiles = readFileSync(
    join(sourceRoot, "payments/v2/merchantProfiles.ts"),
    "utf8",
  );
  const summaryStart = profiles.indexOf("function profileSummary");
  assert.notEqual(summaryStart, -1);
  const returnStart = profiles.indexOf("return {", summaryStart);
  const returnEnd = profiles.indexOf("\n  };", returnStart);
  assert.notEqual(returnStart, -1);
  assert.notEqual(returnEnd, -1);
  assert.doesNotMatch(
    profiles.slice(returnStart, returnEnd),
    /accountFingerprint|paystackSubaccountCode|merchantId:/,
  );
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
  const authorizationCheck = source.indexOf(
    "initialAuthorizationDecision",
    start,
  );
  const bankLookup = source.indexOf(
    "fetchSupportedSettlementBanks(secret)",
    start,
  );
  assert.ok(
    authorizationCheck > start && bankLookup > authorizationCheck,
    "admin preauthorization must be checked before the provider lookup used by billable verification",
  );
  assert.match(source, /https:\/\/api\.paystack\.co\/bank\/validate/);
  assert.doesNotMatch(source, /decision\/bin|authorization\/verify|\/card\//);
});

test("settlement verification provider authority is isolated from payment flows", () => {
  const profiles = readFileSync(
    join(sourceRoot, "payments/v2/merchantProfiles.ts"),
    "utf8",
  );
  const prepareStart = profiles.indexOf(
    "export const prepareMerchantSettlementProfileV2",
  );
  const reviewStart = profiles.indexOf(
    "async function applySettlementProfileReview",
  );
  assert.notEqual(prepareStart, -1);
  assert.notEqual(reviewStart, -1);
  assert.match(
    profiles.slice(prepareStart, reviewStart),
    /paystackSettlementVerificationSecret\(\)/,
  );
  assert.match(
    profiles.slice(reviewStart),
    /paystackSettlementVerificationSecret\(\)/,
  );
  assert.doesNotMatch(profiles, /paystackSecret\(\)/);

  for (const [relativePath, accessor] of [
    ["payments/v2/campaignTopup.ts", /paystackSecret\(\)/],
    ["payments/v2/ownedOrders.ts", /paystackSecret\(\)/],
    ["payments/v2/accountSettlements.ts", /paystackPaymentSecret\(/],
    ["payments/v2/supplierOrders.ts", /paystackSecret\(\)/],
    ["payments/v2/refunds.ts", /paystackPaymentSecret\(/],
  ]) {
    const source = readFileSync(join(sourceRoot, relativePath), "utf8");
    assert.match(source, accessor, relativePath);
    assert.doesNotMatch(
      source,
      /paystackSettlementVerificationSecret/,
      relativePath,
    );
  }
});

test("merchant verification begins with an attested idempotent request", () => {
  const source = readFileSync(
    join(sourceRoot, "payments/v2/merchantProfiles.ts"),
    "utf8",
  );
  const start = source.indexOf(
    "export const requestMerchantSettlementVerificationV1",
  );
  assert.notEqual(start, -1);
  const request = source.slice(
    start,
    source.indexOf("export const prepareMerchantSettlementProfileV2", start),
  );
  assert.match(request, /enforceAppCheck:\s*true/);
  assert.match(request, /assertStoreAccess/);
  assert.match(request, /upsertSettlementAuthorizationRequest/);
  assert.match(request, /Enter the bank name/);
  assert.match(request, /six-digit branch code/);
  assert.match(request, /Enter a valid bank account number/);
  assert.match(request, /Enter the bank account holder name/);
  assert.doesNotMatch(
    request,
    /documentNumber|PAYSTACK_SECRET_KEY|api\.paystack\.co/,
  );
});

test("merchant heartbeat records only an exact source commit", () => {
  const heartbeat = readFileSync(
    join(sourceRoot, "utils/heartbeatMerchantApp.ts"),
    "utf8",
  );
  assert.match(heartbeat, /\^\[a-f0-9\]\{40\}\$/);
  assert.match(heartbeat, /appCommitSha: commitSha/);

  const appBoot = readFileSync(
    join(sourceRoot, "..", "..", "lib", "main.dart"),
    "utf8",
  );
  assert.match(appBoot, /merchantHeartbeatBuildChanged/);
  assert.match(appBoot, /keyPrefix}_commit/);

  const pipeline = readFileSync(
    join(sourceRoot, "..", "..", "codemagic.yaml"),
    "utf8",
  );
  assert.equal(
    pipeline.match(/--dart-define=BUILD_COMMIT="\$CM_COMMIT"/g)?.length,
    2,
  );

  const xcodeCloudBootstrap = readFileSync(
    join(sourceRoot, "..", "..", "ios", "ci_scripts", "ci_post_clone.sh"),
    "utf8",
  );
  assert.match(xcodeCloudBootstrap, /--dart-define=BUILD_COMMIT="\$CI_COMMIT"/);
  assert.match(
    xcodeCloudBootstrap,
    /flutter build ios --config-only --flavor production --release/,
  );

  const defaultXcodeScheme = readFileSync(
    join(
      sourceRoot,
      "..",
      "..",
      "ios",
      "Runner.xcodeproj",
      "xcshareddata",
      "xcschemes",
      "Runner.xcscheme",
    ),
    "utf8",
  );
  assert.match(
    defaultXcodeScheme,
    /<ArchiveAction\s+buildConfiguration = "Release-production"/,
  );
});
