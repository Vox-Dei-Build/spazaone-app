import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { after, before, test } from "node:test";
import admin from "firebase-admin";

const projectId = process.env.GCLOUD_PROJECT || "demo-spazaone-multistore";
const functionsHost = process.env.FUNCTIONS_EMULATOR_HOST || "127.0.0.1:5001";
const botSecret = process.env.PASELLA_BOT_TOKEN;

if (!botSecret) {
  throw new Error("PASELLA_BOT_TOKEN must be set to an emulator-only value.");
}
if (!admin.apps.length) admin.initializeApp({ projectId });
const db = admin.firestore();
const endpoint = `http://${functionsHost}/${projectId}/us-central1/fetchMerchantDetails`;

function hashPhone(phone) {
  return createHash("sha256").update(phone).digest("hex");
}

async function clear() {
  for (const collection of ["users", "operatorPhoneLookup"]) {
    await admin.firestore().recursiveDelete(db.collection(collection));
  }
}

async function request(query, authenticated = true) {
  return fetch(`${endpoint}?${new URLSearchParams(query)}`, {
    headers: authenticated ? { "X-Pasella-Bot-Token": botSecret } : {},
  });
}

before(async () => {
  await clear();
  const phone = "+27820000020";
  const hash = hashPhone(phone);
  await Promise.all([
    db.doc("users/store-alpha").set({
      name: "Alice",
      shopName: "Alpha Shop",
      mobileNumber: "0820000020",
    }),
    db.doc("users/store-beta").set({
      name: "Bob",
      shopName: "Beta Shop",
      mobileNumber: "0820000020",
    }),
    db.doc(`operatorPhoneLookup/${hash}/stores/store-beta`).set({
      status: "active",
      role: "operator",
      storeName: "Beta Shop",
    }),
    db.doc(`operatorPhoneLookup/${hash}/stores/store-alpha`).set({
      status: "active",
      role: "admin",
      storeName: "Alpha Shop",
    }),
    db.doc(`operatorPhoneLookup/${hash}/stores/store-disabled`).set({
      status: "disabled",
      role: "operator",
      storeName: "Disabled Shop",
    }),
    db.doc("users/legacy-store").set({
      name: "Legacy Owner",
      shopName: "Legacy Shop",
      mobileNumber: "0820000030",
      balanceData: {
        lastUpdated: admin.firestore.Timestamp.fromMillis(Date.now()),
      },
    }),
  ]);
});

after(clear);

test("live bot endpoint rejects missing secret and never guesses a store", async () => {
  const unauthorized = await request({ number: "+27820000020" }, false);
  assert.equal(unauthorized.status, 401);

  const unresolved = await request({ number: "+27820000020" });
  assert.equal(unresolved.status, 200);
  const body = await unresolved.json();
  assert.equal(body.requiresStoreSelection, true);
  assert.deepEqual(
    body.stores.map((store) => [store.choice, store.merchantId]),
    [
      ["1", "store-alpha"],
      ["2", "store-beta"],
    ],
  );

  const invalid = await request({
    number: "+27820000020",
    storeId: "store-disabled",
  });
  assert.equal(invalid.status, 403);
});

test("live bot endpoint resolves an explicit choice and legacy owner", async () => {
  const selected = await request({
    number: "+27820000020",
    storeChoice: "2",
  });
  assert.equal(selected.status, 200);
  const selectedBody = await selected.json();
  assert.equal(selectedBody.merchantDetails.merchantId, "store-beta");
  assert.equal(selectedBody.merchantDetails.operatorRole, "operator");

  const legacy = await request({ number: "+27820000030" });
  assert.equal(legacy.status, 200);
  const legacyBody = await legacy.json();
  assert.equal(legacyBody.merchantDetails.merchantId, "legacy-store");
});
