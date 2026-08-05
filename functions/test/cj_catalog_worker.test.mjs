import assert from "node:assert/strict";
import test from "node:test";
import {
  DAILY_CATALOG_POINT_BUDGET,
  ROTATING_DISCOVERY_INTERVAL_MS,
  catalogQueueOrder,
  catalogRefreshPriority,
  estimatedCatalogJobPoints,
} from "../lib/commerce/cjCatalogWorker.js";

test("catalogue budget preserves capacity for buyer quotes", () => {
  const cjBasePoints = 50_000;

  assert.equal(DAILY_CATALOG_POINT_BUDGET, 36_000);
  assert.equal(cjBasePoints - DAILY_CATALOG_POINT_BUDGET, 14_000);
  assert.equal(estimatedCatalogJobPoints("discover_query"), 50);
  assert.equal(estimatedCatalogJobPoints("refresh_product"), 130);
});

test("rotating discovery gets a fair slot without blocking seller demand", () => {
  assert.equal(ROTATING_DISCOVERY_INTERVAL_MS, 2 * 60 * 60 * 1000);
  assert.deepEqual(catalogQueueOrder(true), [
    "demand",
    "background",
    "refresh",
  ]);
  assert.deepEqual(catalogQueueOrder(false), [
    "demand",
    "refresh",
    "background",
  ]);
  assert.equal(catalogRefreshPriority(50), 35);
  assert.equal(catalogRefreshPriority(10), 5);
});
