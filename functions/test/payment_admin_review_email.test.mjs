import assert from "node:assert/strict";
import test from "node:test";
import {
  paymentAdminReviewEmailContent,
  paymentAdminReviewEmailId,
  paymentAdminReviewEmailProjection,
  shouldSendPaymentAdminReviewEmail,
} from "../lib/payments/v2/paymentAdminReviewEmail.js";

const fingerprint = "a".repeat(64);
const secondFingerprint = "b".repeat(64);

function pendingProfile(value = fingerprint) {
  return {
    status: "pending_review",
    pendingSettlement: {
      accountFingerprint: value,
      bankName: "Test Bank",
      accountLast4: "1234",
      accountNumber: "1234567890",
      identityNumber: "9001015009087",
    },
  };
}

test("payment review email identifiers deduplicate one destination", () => {
  const first = paymentAdminReviewEmailId({
    merchantId: "merchant-a",
    accountFingerprint: fingerprint,
  });
  assert.equal(first.length, 64);
  assert.equal(
    first,
    paymentAdminReviewEmailId({
      merchantId: "merchant-a",
      accountFingerprint: fingerprint,
    }),
  );
  assert.notEqual(
    first,
    paymentAdminReviewEmailId({
      merchantId: "merchant-a",
      accountFingerprint: secondFingerprint,
    }),
  );
});

test("only a newly pending destination sends an admin email", () => {
  assert.equal(shouldSendPaymentAdminReviewEmail({}, pendingProfile()), true);
  assert.equal(
    shouldSendPaymentAdminReviewEmail(pendingProfile(), pendingProfile()),
    false,
  );
  assert.equal(
    shouldSendPaymentAdminReviewEmail(
      pendingProfile(),
      pendingProfile(secondFingerprint),
    ),
    true,
  );
  assert.equal(
    shouldSendPaymentAdminReviewEmail(pendingProfile(), {
      status: "enabled",
    }),
    false,
  );
});

test("email outbox projection retains masked review data only", () => {
  const projection = paymentAdminReviewEmailProjection({
    merchantId: "merchant-a",
    merchantName: "Example Shop",
    profile: pendingProfile(),
  });
  assert.equal(projection.recipient, "tsepo.ntsaba@thedelta.io");
  assert.equal(projection.maskedAccount, "•••• 1234");
  assert.equal(projection.bankName, "Test Bank");
  const serialized = JSON.stringify(projection);
  assert.doesNotMatch(serialized, /1234567890/);
  assert.doesNotMatch(serialized, /9001015009087/);
});

test("email content has a clear manual action without raw bank data", () => {
  const content = paymentAdminReviewEmailContent({
    emailId: "c".repeat(64),
    merchantName: "Example <Shop>",
    bankName: "Test Bank",
    maskedAccount: "•••• 1234",
  });
  assert.match(content.subject, /SpazaOne payment review/);
  assert.match(content.text, /approve or reject/);
  assert.match(content.text, /•••• 1234/);
  assert.match(content.html, /Example &lt;Shop&gt;/);
  assert.doesNotMatch(content.text, /1234567890/);
});
