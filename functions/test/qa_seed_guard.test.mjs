import assert from "node:assert/strict";
import { test } from "node:test";
import {
  buildQaCatalogDocuments,
  validateQaSeedEnvironment,
} from "../scripts/seed-local-qa.mjs";

const safeEnv = {
  GCLOUD_PROJECT: "demo-spazaone-qa",
  FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
  FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9099",
  FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:9199",
  QA_DEVICE_FIREBASE_HOST: "10.0.2.2",
};

test("QA seed refuses a production Firebase project", () => {
  assert.throws(
    () =>
      validateQaSeedEnvironment({
        ...safeEnv,
        GCLOUD_PROJECT: "pasella-ledger",
      }),
    /demo-\*/i,
  );
});

test("QA seed refuses missing, conflicting, or non-local emulator targets", () => {
  assert.throws(
    () =>
      validateQaSeedEnvironment({ ...safeEnv, FIRESTORE_EMULATOR_HOST: "" }),
    /FIRESTORE_EMULATOR_HOST/,
  );
  assert.throws(
    () =>
      validateQaSeedEnvironment({
        ...safeEnv,
        GOOGLE_CLOUD_PROJECT: "demo-another-project",
      }),
    /one matching demo-/i,
  );
  assert.throws(
    () =>
      validateQaSeedEnvironment({
        ...safeEnv,
        FIREBASE_AUTH_EMULATOR_HOST: "firebase.example.com:9099",
      }),
    /loopback/i,
  );
});

test("QA seed accepts an explicit local demo target", () => {
  assert.deepEqual(validateQaSeedEnvironment(safeEnv), {
    projectId: "demo-spazaone-qa",
    firestoreHost: "127.0.0.1:8080",
    authHost: "127.0.0.1:9099",
    storageHost: "127.0.0.1:9199",
    deviceHost: "10.0.2.2",
  });
});

test("QA catalogue fixtures are fresh schema-v2 ZA snapshots", () => {
  const nowMs = Date.parse("2026-08-06T02:00:00.000Z");
  const products = buildQaCatalogDocuments({ nowMs });
  assert.equal(products.length, 12);
  assert.equal(new Set(products.map((item) => item.productId)).size, 12);
  assert.ok(new Set(products.map((item) => item.document.category)).size >= 6);

  for (const { id, productId, document } of products) {
    assert.equal(id, `cj_${productId}`);
    assert.equal(document.schemaVersion, 2);
    assert.equal(document.active, true);
    assert.equal(document.destinationCountryCode, "ZA");
    assert.equal(document.deliveryVerifiedAt, new Date(nowMs).toISOString());
    assert.equal(
      document.recommendedQuote.verifiedAt,
      document.deliveryVerifiedAt,
    );
    assert.equal(document.recommendedQuote.variant.productId, productId);
    assert.equal(
      document.recommendedQuote.landedCostMinor,
      document.recommendedQuote.productCostMinor +
        document.recommendedQuote.shippingCostMinor,
    );
    assert.ok(document.recommendedQuote.stock > 0);
    assert.ok(document.activeSearchTokens.length > 0);
  }
});
