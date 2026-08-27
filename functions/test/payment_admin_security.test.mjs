import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import test from "node:test";
import { Timestamp } from "firebase-admin/firestore";

import { paymentAdminAccessDecision } from "../lib/payments/v2/paymentAdminAuth.js";
import {
  automaticSettlementAuthorizationDecision,
  maskBankAccount,
  settlementAdminRequestDetailProjection,
  settlementAdminRequestId,
  settlementAdminRequestProjection,
  settlementAuthorizationOpenDecision,
  settlementAuthorizationRequestDecision,
  settlementSupportReviewResetDecision,
} from "../lib/payments/v2/settlementAdminRequests.js";
import { merchantVerificationJourney } from "../lib/payments/v2/merchantOverview.js";
import {
  paymentOperationsRecipientEmails,
  mailgunOperationsEmailConfig,
  mailgunVerificationMessageFields,
  sendMailgunVerificationMessage,
  settlementOperationsEmailCopy,
  settlementOperationsNotificationCopy,
  settlementOperationsNotificationId,
} from "../lib/payments/v2/settlementOperationsNotifications.js";

const requireModule = createRequire(import.meta.url);
const axios = requireModule("axios");

const secureAdminRequest = {
  authenticated: true,
  spazaAdmin: true,
  appCheckVerified: true,
  appCheckAlreadyConsumed: false,
  email: "tsepo.ntsaba@thedelta.io",
  emailVerified: true,
  signInProvider: "google.com",
  authTimeSeconds: 1_000,
  nowSeconds: 1_100,
  origin: "https://workspace.spazaone.com",
  allowedEmails: ["tsepo.ntsaba@thedelta.io"],
  allowedOrigins: ["https://workspace.spazaone.com"],
  requireRecentAuth: true,
};

test("payment admin access requires every independent security control", () => {
  assert.deepEqual(paymentAdminAccessDecision(secureAdminRequest), {
    allowed: true,
  });

  const denied = [
    ["authenticated", false, "PAYMENT_ADMIN_AUTH_REQUIRED"],
    ["spazaAdmin", false, "PAYMENT_ADMIN_CLAIM_REQUIRED"],
    ["appCheckVerified", false, "PAYMENT_ADMIN_APP_CHECK_REQUIRED"],
    ["appCheckAlreadyConsumed", true, "PAYMENT_ADMIN_APP_CHECK_REPLAYED"],
    ["emailVerified", false, "PAYMENT_ADMIN_EMAIL_NOT_ALLOWED"],
    ["email", "attacker@example.com", "PAYMENT_ADMIN_EMAIL_NOT_ALLOWED"],
    ["signInProvider", "password", "PAYMENT_ADMIN_GOOGLE_SIGN_IN_REQUIRED"],
    ["origin", "https://lookalike.example", "PAYMENT_ADMIN_ORIGIN_NOT_ALLOWED"],
    ["authTimeSeconds", 100, "PAYMENT_ADMIN_RECENT_AUTH_REQUIRED"],
  ];
  for (const [field, value, reason] of denied) {
    const decision = paymentAdminAccessDecision({
      ...secureAdminRequest,
      [field]: value,
    });
    assert.equal(decision.allowed, false, `${field} must fail closed`);
    assert.equal(decision.reason, reason);
  }
});

test("missing admin allowlists fail closed", () => {
  assert.equal(
    paymentAdminAccessDecision({
      ...secureAdminRequest,
      allowedEmails: [],
    }).allowed,
    false,
  );
  assert.equal(
    paymentAdminAccessDecision({
      ...secureAdminRequest,
      allowedOrigins: [],
    }).allowed,
    false,
  );
});

test("read-only queue listing can outlive the mutation reauth window", () => {
  assert.deepEqual(
    paymentAdminAccessDecision({
      ...secureAdminRequest,
      authTimeSeconds: 1,
      requireRecentAuth: false,
    }),
    { allowed: true },
  );
});

test("campaign recovery callable is admin-only and accepts no money binding", () => {
  const source = readFileSync(
    new URL("../src/payments/v2/campaignTopupRecovery.ts", import.meta.url),
    "utf8",
  );
  const callable = source.slice(
    source.indexOf("export const recoverCampaignTopupV2OnDemand"),
  );
  assert.match(callable, /requirePaymentAdmin\(context\)/);
  assert.match(callable, /enforceAppCheck: true/);
  assert.match(callable, /consumeAppCheckToken: true/);
  assert.match(callable, /intentId: data\?\.intentId/);
  assert.match(callable, /operationId: data\?\.operationId/);
  assert.match(callable, /reason: data\?\.reason/);
  assert.doesNotMatch(callable, /data\?\.(merchantId|reference|amount)/);
});

test("settlement request projection never crosses internal identifiers or PII", () => {
  const projection = settlementAdminRequestProjection("request_opaque", {
    type: "settlement_verification",
    status: "pending_review",
    storeName: "Corner Store",
    bankName: "Example Bank",
    maskedAccount: "•••• 6789",
    maskedAccountHolder: "T•••• N••••",
    requestedAt: Timestamp.fromMillis(1_000),
    updatedAt: Timestamp.fromMillis(2_000),
    merchantId: "secret-merchant-id",
    requestedBy: "secret-firebase-uid",
    accountFingerprint: "a".repeat(64),
    paystackSubaccountCode: "ACCT_secret",
    accountNumber: "123456789",
    documentNumber: "9001010000000",
  });
  assert.deepEqual(Object.keys(projection).sort(), [
    "bankName",
    "maskedAccount",
    "maskedAccountHolder",
    "requestId",
    "requestedAtMs",
    "requiresMerchantResubmission",
    "status",
    "storeName",
    "type",
    "updatedAtMs",
  ]);
  assert.equal(projection.requiresMerchantResubmission, true);
  const serialized = JSON.stringify(projection);
  for (const forbidden of [
    "secret-merchant-id",
    "secret-firebase-uid",
    "ACCT_secret",
    "123456789",
    "9001010000000",
    "a".repeat(64),
  ]) {
    assert.equal(serialized.includes(forbidden), false);
  }
});

test("secure banking bindings make settlement requests reviewable", () => {
  const projection = settlementAdminRequestProjection("request_bound", {
    type: "settlement_verification",
    status: "authorization_required",
    bankingDetailsId: "banking-a",
    bankingDetailsUpdatedAtMs: 3_000,
  });
  assert.equal(projection.requiresMerchantResubmission, false);
});

test("bank account masking exposes only the last four digits", () => {
  assert.equal(maskBankAccount("1234 5678 9012"), "•••• 9012");
  assert.equal(maskBankAccount("12"), "");
});

test("recent-auth detail projection reveals only banking fields needed for review", () => {
  const detail = settlementAdminRequestDetailProjection({
    requestId: "request_opaque",
    request: {
      type: "settlement_verification",
      status: "pending_review",
      storeName: "Corner Store",
      bankName: "Example Bank",
      maskedAccount: "•••• 6789",
      maskedAccountHolder: "T•••• N••••",
      requestedAt: Timestamp.fromMillis(1_000),
      updatedAt: Timestamp.fromMillis(2_000),
      bankingDetailsId: "banking-a",
      bankingDetailsUpdatedAtMs: 3_000,
      merchantId: "secret-merchant-id",
      accountFingerprint: "a".repeat(64),
    },
    banking: {
      bankName: "Example Bank",
      accountNumber: "1234 56789",
      accountHolderName: "Tsepo Example",
      accountType: "Current / cheque",
      branchCode: "632005",
      documentNumber: "9001010000000",
    },
    bankingDetailsId: "banking-a",
    bankingDetailsUpdatedAtMs: 3_000,
  });
  assert.equal(detail.account, "123456789");
  assert.equal(detail.holder, "Tsepo Example");
  assert.equal(detail.accountType, "Current / cheque");
  assert.equal(detail.branchCode, "632005");
  const serialized = JSON.stringify(detail);
  assert.equal(serialized.includes("secret-merchant-id"), false);
  assert.equal(serialized.includes("9001010000000"), false);
  assert.equal(serialized.includes("a".repeat(64)), false);
});

test("detail projection fails closed when the reviewed bank version changed", () => {
  assert.throws(
    () =>
      settlementAdminRequestDetailProjection({
        requestId: "request_opaque",
        request: {
          type: "settlement_verification",
          status: "pending_review",
          bankingDetailsId: "banking-a",
          bankingDetailsUpdatedAtMs: 3_000,
        },
        banking: {
          accountNumber: "123456789",
          accountHolderName: "Tsepo Example",
          accountType: "Savings",
          branchCode: "632005",
        },
        bankingDetailsId: "banking-a",
        bankingDetailsUpdatedAtMs: 3_001,
      }),
    /VERSION_CHANGED/,
  );
});

test("merchant authorization requests are deterministic and duplicate-safe", () => {
  assert.equal(
    settlementAdminRequestId("merchant-a"),
    settlementAdminRequestId("merchant-a"),
  );
  assert.notEqual(
    settlementAdminRequestId("merchant-a"),
    settlementAdminRequestId("merchant-b"),
  );
  assert.deepEqual(
    settlementAuthorizationRequestDecision({
      existingStatus: "authorization_required",
      sameVisibleDestination: true,
    }),
    {
      nextStatus: "authorization_required",
      createOrRefresh: false,
      deduped: true,
    },
  );
  assert.deepEqual(
    settlementAuthorizationRequestDecision({
      existingStatus: "authorization_required",
      sameVisibleDestination: false,
    }),
    {
      nextStatus: "authorization_required",
      createOrRefresh: true,
      deduped: false,
    },
  );
  assert.deepEqual(
    settlementAuthorizationRequestDecision({
      existingStatus: "changes_required",
      sameVisibleDestination: false,
    }),
    {
      nextStatus: "authorization_required",
      createOrRefresh: true,
      deduped: false,
    },
  );
  assert.equal(
    settlementAuthorizationRequestDecision({
      existingStatus: "authorized",
      sameVisibleDestination: true,
      authorizationInvalid: true,
    }).nextStatus,
    "authorization_required",
  );
  assert.equal(
    settlementAuthorizationRequestDecision({
      existingStatus: "authorized",
      sameVisibleDestination: false,
    }).nextStatus,
    "authorization_required",
  );
});

test("only a merchant's first guarded bank check is auto-authorized", () => {
  assert.deepEqual(
    automaticSettlementAuthorizationDecision({
      requestStatus: "authorization_required",
      authorizationState: "",
      validationAttemptState: "",
      validationLifetimeAttemptCount: 0,
    }),
    { allowed: true, reason: "automatic_initial_authorization" },
  );
  assert.equal(
    automaticSettlementAuthorizationDecision({
      requestStatus: "authorized",
      authorizationState: "consumed",
      validationAttemptState: "failed",
      validationLifetimeAttemptCount: 1,
    }).reason,
    "provider_attempt_requires_review",
  );
  assert.equal(
    automaticSettlementAuthorizationDecision({
      requestStatus: "revoked",
      authorizationState: "revoked",
      validationAttemptState: "",
      validationLifetimeAttemptCount: 0,
    }).reason,
    "authorization_revoked",
  );
  assert.equal(
    automaticSettlementAuthorizationDecision({
      requestStatus: "pending_review",
      authorizationState: "authorized",
      validationAttemptState: "completed",
      validationLifetimeAttemptCount: 0,
    }).reason,
    "request_requires_review",
  );
  assert.equal(
    automaticSettlementAuthorizationDecision({
      requestStatus: "authorization_required",
      authorizationState: "",
      validationAttemptState: "provider_outcome_unknown",
      validationLifetimeAttemptCount: 0,
    }).reason,
    "provider_attempt_requires_review",
  );
});

test("a reviewed authorization clears only a completed provider failure", () => {
  assert.deepEqual(
    settlementSupportReviewResetDecision({
      authorized: true,
      validationAttemptState: "failed",
      validationAttemptFailureCode: "BANK_ACCOUNT_NOT_VERIFIED",
    }),
    { clearPreviousFailure: true },
  );
  assert.equal(
    settlementSupportReviewResetDecision({
      authorized: false,
      validationAttemptState: "failed",
      validationAttemptFailureCode: "BANK_ACCOUNT_NOT_VERIFIED",
    }).clearPreviousFailure,
    false,
  );
  assert.equal(
    settlementSupportReviewResetDecision({
      authorized: true,
      validationAttemptState: "provider_outcome_unknown",
      validationAttemptFailureCode: "BANK_VALIDATION_OUTCOME_UNKNOWN",
    }).clearPreviousFailure,
    false,
  );
});

test("automatic authorization opens initial checks and queues only exceptions", () => {
  assert.deepEqual(
    settlementAuthorizationOpenDecision({
      automaticRequested: true,
      activeAuthorization: false,
      existingAutomaticAuthorization: false,
      automaticEligible: true,
      existingStatus: "authorization_required",
      sameVisibleDestination: true,
    }),
    {
      nextStatus: "authorized",
      createOrRefresh: true,
      deduped: false,
      automaticallyAuthorized: true,
    },
  );
  assert.deepEqual(
    settlementAuthorizationOpenDecision({
      automaticRequested: true,
      activeAuthorization: true,
      existingAutomaticAuthorization: true,
      automaticEligible: false,
      existingStatus: "authorized",
      sameVisibleDestination: true,
    }),
    {
      nextStatus: "authorized",
      createOrRefresh: false,
      deduped: true,
      automaticallyAuthorized: true,
    },
  );
  assert.deepEqual(
    settlementAuthorizationOpenDecision({
      automaticRequested: true,
      activeAuthorization: false,
      existingAutomaticAuthorization: false,
      automaticEligible: false,
      existingStatus: "authorized",
      sameVisibleDestination: true,
    }),
    {
      nextStatus: "authorization_required",
      createOrRefresh: true,
      deduped: false,
      automaticallyAuthorized: false,
    },
    "an expired or consumed repeat attempt is visible to support",
  );
  assert.deepEqual(
    settlementAuthorizationOpenDecision({
      automaticRequested: true,
      activeAuthorization: false,
      existingAutomaticAuthorization: false,
      automaticEligible: false,
      existingStatus: "pending_review",
      sameVisibleDestination: true,
    }),
    {
      nextStatus: "pending_review",
      createOrRefresh: false,
      deduped: true,
      automaticallyAuthorized: false,
    },
    "a duplicate tap cannot reopen final review",
  );
  assert.deepEqual(
    settlementAuthorizationOpenDecision({
      automaticRequested: true,
      activeAuthorization: false,
      existingAutomaticAuthorization: false,
      automaticEligible: false,
      existingStatus: "approved",
      sameVisibleDestination: false,
    }),
    {
      nextStatus: "authorization_required",
      createOrRefresh: true,
      deduped: false,
      automaticallyAuthorized: false,
    },
    "a changed approved destination must return to support review",
  );
});

test("operations request alerts are deterministic, admin-only and PII-free", () => {
  const input = {
    requestId: "request-opaque",
    bankingDetailsId: "banking-version-opaque",
    bankingDetailsUpdatedAtMs: 1_000,
    sequence: 1,
  };
  assert.equal(
    settlementOperationsNotificationId(input),
    settlementOperationsNotificationId(input),
  );
  assert.notEqual(
    settlementOperationsNotificationId(input),
    settlementOperationsNotificationId({ ...input, sequence: 2 }),
  );
  assert.deepEqual(
    paymentOperationsRecipientEmails(
      " Ops@example.com,ops@example.com,not-an-email ",
    ),
    ["ops@example.com"],
  );
  assert.deepEqual(
    paymentOperationsRecipientEmails("tsepo.ntsaba@thedelta.io"),
    ["tsepo.ntsaba@thedelta.io"],
  );
  const copy = settlementOperationsNotificationCopy();
  assert.match(copy.body, /merchant requested bank verification/i);
  assert.match(copy.body, /Payment Operations workspace/);
  assert.doesNotMatch(
    JSON.stringify(copy),
    /account|branch|identity|provider|reviewer/i,
  );

  const source = readFileSync(
    new URL(
      "../src/payments/v2/settlementOperationsNotifications.ts",
      import.meta.url,
    ),
    "utf8",
  );
  assert.match(source, /PAYMENT_ADMIN_ALLOWED_EMAILS/);
  assert.match(source, /admin\.auth\(\)\.getUserByEmail/);
  assert.match(source, /secrets:\s*\["MAILGUN_API_KEY"\]/);
  assert.doesNotMatch(source, /readStoreNotificationTokens/);
});

test("verification email is allowlisted, tracking-free and PII-free", () => {
  const config = mailgunOperationsEmailConfig({
    MAILGUN_PROVIDER_MODE: "live",
    MAILGUN_REGION: "eu",
    MAILGUN_API_KEY: "test-key",
    MAILGUN_DOMAIN: "mg.spazaone.com",
    MAILGUN_FROM: "SpazaOne Operations <notifications@mg.spazaone.com>",
  });
  assert.deepEqual(config, {
    apiBaseUrl: "https://api.eu.mailgun.net",
    apiKey: "test-key",
    domain: "mg.spazaone.com",
    from: "SpazaOne Operations <notifications@mg.spazaone.com>",
  });
  assert.equal(
    mailgunOperationsEmailConfig({
      MAILGUN_PROVIDER_MODE: "disabled",
      MAILGUN_API_KEY: "test-key",
      MAILGUN_DOMAIN: "mg.spazaone.com",
      MAILGUN_FROM: "notifications@mg.spazaone.com",
    }),
    null,
  );
  assert.equal(
    mailgunOperationsEmailConfig({
      MAILGUN_PROVIDER_MODE: "live",
      MAILGUN_REGION: "invalid",
      MAILGUN_API_KEY: "test-key",
      MAILGUN_DOMAIN: "mg.spazaone.com",
      MAILGUN_FROM: "notifications@mg.spazaone.com",
    }),
    null,
  );

  const copy = settlementOperationsEmailCopy();
  assert.match(copy.subject, /verification request/i);
  assert.match(copy.text, /merchant requested bank verification/i);
  assert.match(copy.text, /https:\/\/workspace\.spazaone\.com\//);
  assert.doesNotMatch(copy.text, /\d{4,}|@|branch|identity number|provider/i);

  const fields = mailgunVerificationMessageFields({
    from: config.from,
    recipient: "tsepo.ntsaba@thedelta.io",
    notificationId: "opaque-notification-id",
  });
  assert.equal(fields.to, "tsepo.ntsaba@thedelta.io");
  assert.equal(fields["o:tracking"], "no");
  assert.equal(fields["o:require-tls"], "yes");
  assert.equal(
    fields["h:X-SpazaOne-Notification-Id"],
    "opaque-notification-id",
  );
});

test("verification email uses Mailgun's authenticated message endpoint", async () => {
  const originalAdapter = axios.defaults.adapter;
  let captured;
  axios.defaults.adapter = async (request) => {
    captured = request;
    return {
      data: { id: "queued-message" },
      status: 200,
      statusText: "OK",
      headers: {},
      config: request,
    };
  };
  try {
    await sendMailgunVerificationMessage({
      config: {
        apiBaseUrl: "https://api.mailgun.net",
        apiKey: "domain-sending-key",
        domain: "mg.spazaone.com",
        from: "SpazaOne Operations <notifications@mg.spazaone.com>",
      },
      notificationId: "opaque-notification-id",
      recipient: "tsepo.ntsaba@thedelta.io",
    });
  } finally {
    axios.defaults.adapter = originalAdapter;
  }

  assert.equal(
    captured.url,
    "https://api.mailgun.net/v3/mg.spazaone.com/messages",
  );
  assert.deepEqual(captured.auth, {
    username: "api",
    password: "domain-sending-key",
  });
  assert.equal(captured.timeout, 15_000);
  const fields = Object.fromEntries(captured.data.entries());
  assert.equal(fields.to, "tsepo.ntsaba@thedelta.io");
  assert.equal(fields["o:tracking"], "no");
  assert.equal(fields["o:require-tls"], "yes");
});

test("merchant verification journey covers every persistent review state", () => {
  const nowMs = 10_000;
  const journey = (request, profile = {}, hasSavedBankingDetails = true) =>
    merchantVerificationJourney({
      request,
      profile,
      hasSavedBankingDetails,
      nowMs,
    });
  assert.equal(journey({}, {}, false).stage, "missing_information");
  assert.equal(journey({}).stage, "ready_to_submit");
  assert.equal(
    journey({ status: "authorization_required" }).stage,
    "submitted",
  );
  assert.equal(
    journey(
      { status: "authorized" },
      {
        settlementVerificationAuthorization: {
          state: "authorized",
          expiresAtMs: nowMs + 1_000,
          remainingAttempts: 1,
        },
      },
    ).stage,
    "ready_to_verify",
  );
  assert.deepEqual(
    journey(
      { status: "authorized" },
      {
        settlementVerificationAuthorization: {
          state: "consumed",
          expiresAtMs: nowMs + 1_000,
          remainingAttempts: 0,
        },
        validationAttemptState: "failed",
        validationAttemptFailureCode: "BANK_ACCOUNT_NOT_VALIDATED",
      },
    ),
    { stage: "blocked", reason: "approved_attempts_consumed" },
  );
  assert.deepEqual(
    journey(
      { status: "authorized" },
      {
        settlementVerificationAuthorization: {
          state: "authorized",
          expiresAtMs: nowMs + 1_000,
          remainingAttempts: 1,
        },
        validationAttemptState: "failed",
        validationAttemptFailureCode: "BANK_ACCOUNT_NOT_VALIDATED",
      },
    ),
    { stage: "blocked", reason: "provider_could_not_validate_account" },
  );
  assert.deepEqual(
    journey(
      { status: "authorized" },
      {
        settlementVerificationAuthorization: {
          state: "authorized",
          expiresAtMs: nowMs + 1_000,
          remainingAttempts: 1,
        },
        validationAttemptState: "failed",
        validationAttemptFailureCode: "BANK_ACCOUNT_HOLDER_MISMATCH",
      },
    ),
    { stage: "blocked", reason: "bank_account_holder_mismatch" },
  );
  assert.deepEqual(
    journey(
      { status: "authorized" },
      {
        settlementVerificationAuthorization: {
          state: "authorized",
          expiresAtMs: nowMs + 1_000,
          remainingAttempts: 1,
        },
        validationAttemptFailureCode: "BANK_VALIDATION_DAILY_LIMIT",
      },
    ),
    { stage: "blocked", reason: "daily_validation_limit_reached" },
  );
  assert.deepEqual(
    journey(
      { status: "authorized" },
      {
        settlementVerificationAuthorization: {
          state: "authorized",
          expiresAtMs: nowMs + 1_000,
          remainingAttempts: 1,
        },
        validationAttemptFailureCode: "BANK_VALIDATION_SUSPENDED",
      },
    ),
    { stage: "blocked", reason: "platform_security_suspension" },
  );
  assert.equal(
    merchantVerificationJourney({
      request: { status: "authorized" },
      profile: {
        settlementVerificationAuthorization: {
          state: "authorized",
          expiresAtMs: nowMs + 1_000,
          remainingAttempts: 2,
        },
      },
      hasSavedBankingDetails: true,
      destinationMatchesRequest: false,
      nowMs,
    }).stage,
    "ready_to_submit",
  );
  assert.equal(
    journey(
      {},
      {
        validationAttemptState: "processing",
        validationAttemptLeaseUntilMs: nowMs + 1,
      },
    ).stage,
    "submitting",
  );
  assert.equal(journey({ status: "pending_review" }).stage, "pending_review");
  assert.equal(journey({ status: "approved" }).stage, "approved");
  assert.equal(
    journey({ status: "changes_required" }).stage,
    "changes_required",
  );
  assert.equal(journey({ status: "rejected" }).stage, "rejected");
  assert.equal(journey({ status: "revoked" }).stage, "blocked");
});
