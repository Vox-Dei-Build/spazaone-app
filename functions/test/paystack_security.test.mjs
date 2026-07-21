import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";
import {
  centsFromRands,
  verifyPaystackSignature,
} from "../lib/payments/paystack/paystackSecurity.js";

test("accepts only the SHA-512 HMAC for the exact webhook bytes", () => {
  const secret = "test-secret";
  const body = Buffer.from(
    '{"event":"charge.success","data":{"reference":"r1"}}',
  );
  const signature = createHmac("sha512", secret).update(body).digest("hex");
  assert.equal(verifyPaystackSignature(body, signature, secret), true);
  assert.equal(
    verifyPaystackSignature(
      Buffer.from(`${body.toString()} `),
      signature,
      secret,
    ),
    false,
  );
  assert.equal(verifyPaystackSignature(body, "not-a-signature", secret), false);
});

test("normalizes ZAR rands to integer cents", () => {
  assert.equal(centsFromRands(12.34), 1234);
  assert.equal(centsFromRands("10.005"), 1001);
});
