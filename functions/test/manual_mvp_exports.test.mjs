import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { test } from "node:test";

const requireModule = createRequire(import.meta.url);
const deployedExports = requireModule("../lib/index.js");

test("manual MVP keeps the gated commerce Paystack webhook exported", () => {
  assert.equal(typeof deployedExports.createCommerceOrder, "function");
  assert.equal(typeof deployedExports.getCommerceOrderStatus, "function");
  assert.equal(
    typeof deployedExports.verifyCommercePaystackTransaction,
    "function",
  );
  assert.equal(typeof deployedExports.prepareCommerceCheckout, "function");
  assert.equal(typeof deployedExports.setSavedSupplierProduct, "function");
  assert.equal(typeof deployedExports.listSavedSupplierProducts, "function");
});
