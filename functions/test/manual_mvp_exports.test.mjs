import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { test } from "node:test";

const requireModule = createRequire(import.meta.url);
const deployedExports = requireModule("../lib/index.js");

test("manual MVP does not export the dedicated commerce Paystack webhook", () => {
  assert.equal(typeof deployedExports.createCommerceOrder, "function");
  assert.equal(typeof deployedExports.getCommerceOrderStatus, "function");
  assert.equal(deployedExports.verifyCommercePaystackTransaction, undefined);
});
