import assert from "node:assert/strict";
import test from "node:test";
import {
  selectCustomerPaymentRequestMode,
  paymentRequestCooldownEndsAtMs,
  verifyPaymentRequestWebhookSignature,
} from "../lib/payments/v2/customerPaymentRequests.js";
import { createHmac } from "node:crypto";

test("routes online WhatsApp, reminder WhatsApp and definitive SMS separately", () => {
  assert.equal(
    selectCustomerPaymentRequestMode({
      whatsappCapability: "whatsapp",
      onlinePaymentsReady: true,
      botpressReady: true,
      smsReady: true,
    }),
    "whatsapp_online",
  );
  assert.equal(
    selectCustomerPaymentRequestMode({
      whatsappCapability: "unknown",
      onlinePaymentsReady: false,
      botpressReady: true,
      smsReady: true,
    }),
    "whatsapp_reminder",
  );
  assert.equal(
    selectCustomerPaymentRequestMode({
      whatsappCapability: "sms",
      onlinePaymentsReady: true,
      botpressReady: true,
      smsReady: true,
    }),
    "sms_reminder",
  );
  assert.equal(
    selectCustomerPaymentRequestMode({
      whatsappCapability: "sms",
      onlinePaymentsReady: true,
      botpressReady: true,
      smsReady: false,
    }),
    null,
  );
});

test("starts the non-overridable cooldown exactly 24 hours after acceptance", () => {
  const accepted = Date.UTC(2026, 7, 14, 8, 30, 0);
  assert.equal(
    paymentRequestCooldownEndsAtMs(accepted),
    accepted + 24 * 60 * 60 * 1000,
  );
  assert.throws(() => paymentRequestCooldownEndsAtMs(0), /ACCEPTED_AT_INVALID/);
});

test("verifies proactive delivery payload signatures without timing leaks", () => {
  const payload = JSON.stringify({ requestId: "cpr_test", amount: "R90,00" });
  const secret = "development-only-test-secret";
  const signature = createHmac("sha256", secret).update(payload).digest("hex");
  assert.equal(
    verifyPaymentRequestWebhookSignature({ payload, signature, secret }),
    true,
  );
  assert.equal(
    verifyPaymentRequestWebhookSignature({
      payload,
      signature: `${signature.slice(0, -1)}0`,
      secret,
    }),
    false,
  );
});
