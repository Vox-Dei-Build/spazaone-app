import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  customerPaymentRequestFeatureEnabled,
  selectCustomerPaymentRequestMode,
  paymentRequestCooldownEndsAtMs,
  verifyPaymentRequestWebhookSignature,
} from "../lib/payments/v2/customerPaymentRequests.js";
import { createHmac } from "node:crypto";

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

test("customer payment requests open only for the exact production canary", () => {
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "production",
      SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
      PAYSTACK_PROVIDER_MODE: "disabled",
      PAYSTACK_ACCOUNT_PAYMENT_CANARY_ENABLED: "true",
      PAYSTACK_ACCOUNT_PAYMENT_CANARY_MERCHANT_ID: "merchant_canary",
      CUSTOMER_PAYMENT_REQUESTS_ENABLED: "false",
    },
    () => {
      assert.equal(
        customerPaymentRequestFeatureEnabled({}, "merchant_canary"),
        true,
      );
      assert.equal(
        customerPaymentRequestFeatureEnabled({}, "merchant_other"),
        false,
      );
      process.env.CUSTOMER_PAYMENT_REQUESTS_ENABLED = "true";
      assert.equal(
        customerPaymentRequestFeatureEnabled(
          { customerPaymentRequestsEnabled: true },
          "merchant_other",
        ),
        true,
      );
    },
  );
});

test("routes online WhatsApp, reminder WhatsApp and definitive SMS separately", () => {
  assert.equal(
    selectCustomerPaymentRequestMode({
      whatsappCapability: "whatsapp",
      onlinePaymentsReady: true,
      whatsappTemplateReady: true,
      smsReady: true,
    }),
    "whatsapp_online",
  );
  assert.equal(
    selectCustomerPaymentRequestMode({
      whatsappCapability: "unknown",
      onlinePaymentsReady: false,
      whatsappTemplateReady: true,
      smsReady: true,
    }),
    "whatsapp_reminder",
  );
  assert.equal(
    selectCustomerPaymentRequestMode({
      whatsappCapability: "sms",
      onlinePaymentsReady: true,
      whatsappTemplateReady: true,
      smsReady: true,
    }),
    "sms_reminder",
  );
  assert.equal(
    selectCustomerPaymentRequestMode({
      whatsappCapability: "sms",
      onlinePaymentsReady: true,
      whatsappTemplateReady: true,
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

test("sends proactive payment requests through approved Twilio Content", () => {
  const source = readFileSync(
    new URL("../src/payments/v2/customerPaymentRequests.ts", import.meta.url),
    "utf8",
  );
  const start = source.indexOf(
    "export async function dispatchCustomerPaymentRequest",
  );
  const end = source.indexOf(
    "export const claimCustomerPaymentRequestDeliveryV1BotHttp",
    start,
  );
  const dispatch = source.slice(start, end);
  assert.match(source, /TWILIO_PAYMENT_REQUEST_CONTENT_SID/);
  assert.match(dispatch, /contentSid:\s*runtime\.contentSid/);
  assert.match(dispatch, /messagingServiceSid:\s*runtime\.messagingServiceSid/);
  assert.match(dispatch, /contentVariables:\s*JSON\.stringify/);
  assert.doesNotMatch(dispatch, /BOTPRESS_PAYMENT_REQUEST_WEBHOOK_URL/);
});
