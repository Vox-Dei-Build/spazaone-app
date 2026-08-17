import assert from "node:assert/strict";
import test from "node:test";
import { Timestamp } from "firebase-admin/firestore";

import { paymentAdminAccessDecision } from "../lib/payments/v2/paymentAdminAuth.js";
import {
  maskBankAccount,
  settlementAdminRequestId,
  settlementAdminRequestProjection,
  settlementAuthorizationRequestDecision,
} from "../lib/payments/v2/settlementAdminRequests.js";
import { merchantVerificationJourney } from "../lib/payments/v2/merchantOverview.js";

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
    "status",
    "storeName",
    "type",
    "updatedAtMs",
  ]);
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

test("bank account masking exposes only the last four digits", () => {
  assert.equal(maskBankAccount("1234 5678 9012"), "•••• 9012");
  assert.equal(maskBankAccount("12"), "");
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
