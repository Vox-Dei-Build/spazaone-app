import assert from "node:assert/strict";
import test from "node:test";
import { resolveBotStore } from "../lib/stores/botStoreSelection.js";

const stores = [
  { merchantId: "store-z", shopName: "Zulu Shop", role: "operator" },
  { merchantId: "store-a", shopName: "Alpha Shop", role: "admin" },
];

test("multiple stores require a deterministic bot choice", () => {
  const result = resolveBotStore(stores, "", "");
  assert.equal(result.kind, "selection-required");
  assert.deepEqual(
    result.stores.map((store) => store.merchantId),
    ["store-a", "store-z"],
  );
});

test("bot can resolve by explicit store id or numbered reply", () => {
  assert.equal(
    resolveBotStore(stores, "store-z", "").store.merchantId,
    "store-z",
  );
  assert.equal(resolveBotStore(stores, "", "1").store.merchantId, "store-a");
  assert.equal(resolveBotStore(stores, "other", "").kind, "forbidden");
});

test("a single store stays backward compatible", () => {
  const result = resolveBotStore([stores[0]], "", "");
  assert.equal(result.kind, "selected");
  assert.equal(result.store.merchantId, "store-z");
});
