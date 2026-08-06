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
const functionsBase = `http://${functionsHost}/${projectId}/us-central1`;
const endpoint = `${functionsBase}/fetchMerchantDetails`;

function hashPhone(phone) {
  return createHash("sha256").update(phone).digest("hex");
}

async function clear() {
  for (const collection of ["users", "operatorPhoneLookup", "commerceOrders"]) {
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
  const now = Date.now();
  await Promise.all([
    db.doc("users/store-alpha").set({
      name: "Alice",
      shopName: "Alpha Shop",
      mobileNumber: "0820000020",
    }),
    db.doc("users/store-alpha/customers/customer-alpha").set({
      name: "Commerce Buyer",
      number: "0820000020",
      category: "Customer",
    }),
    db.doc("commerceOrders/commerce-order-alpha").set({
      sellerId: "store-alpha",
      customerId: "customer-alpha",
      status: "shipped",
      fulfilmentStatus: "shipped",
      paymentStatus: "paid",
      paymentMethod: "manual",
      amountDueMinor: 54_789,
      createdAt: admin.firestore.Timestamp.fromMillis(now),
      lineItems: [
        {
          sellerProductId: "seller-product-alpha",
          title: "Messenger bag",
          quantity: 1,
        },
      ],
    }),
    db.doc("users/store-alpha/sales/legacy-order-alpha").set({
      customerId: "customer-alpha",
      status: "delivered",
      amount: 100,
      dateAdded: admin.firestore.Timestamp.fromMillis(now - 1_000),
      id: "stored-id-must-not-win",
      source: "commerce",
    }),
    db.doc("users/store-alpha/customers/customer-legacy").set({
      name: "Legacy Buyer",
      number: "0820000021",
      category: "Customer",
    }),
    db.doc("users/store-alpha/sales/legacy-open-trusted").set({
      customerId: "customer-legacy",
      status: "accepted",
      inventoryFinalized: false,
      amount: 250,
      dateAdded: admin.firestore.Timestamp.fromMillis(now + 1_000),
      id: "stored-id-must-not-win",
      source: "commerce",
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

test("authenticated bot tracking reads supplier orders without exposing them publicly", async () => {
  const query = new URLSearchParams({
    merchantId: "store-alpha",
    customerId: "customer-alpha",
  });
  const unauthorized = await fetch(`${functionsBase}/getOpenSale?${query}`);
  assert.equal(unauthorized.status, 401);

  const openResponse = await fetch(`${functionsBase}/getOpenSale?${query}`, {
    headers: { "X-Pasella-Bot-Token": botSecret },
  });
  assert.equal(openResponse.status, 200);
  const open = await openResponse.json();
  assert.equal(open.openSale.id, "commerce-order-alpha");
  assert.equal(open.openSale.source, "commerce");
  assert.equal(open.openSale.total, 547.89);

  const statusResponse = await fetch(
    `${functionsBase}/getSaleStatus?${new URLSearchParams({
      merchantId: "store-alpha",
      saleId: "commerce-order-alpha",
    })}`,
    { headers: { "X-Pasella-Bot-Token": botSecret } },
  );
  assert.equal(statusResponse.status, 200);
  assert.equal((await statusResponse.json()).sale.source, "commerce");

  const legacyStatusResponse = await fetch(
    `${functionsBase}/getSaleStatus?${new URLSearchParams({
      merchantId: "store-alpha",
      saleId: "legacy-order-alpha",
    })}`,
    { headers: { "X-Pasella-Bot-Token": botSecret } },
  );
  assert.equal(legacyStatusResponse.status, 200);
  const legacyStatus = (await legacyStatusResponse.json()).sale;
  assert.equal(legacyStatus.id, "legacy-order-alpha");
  assert.equal(legacyStatus.source, "legacy");

  const legacyOpenResponse = await fetch(
    `${functionsBase}/getOpenSale?${new URLSearchParams({
      merchantId: "store-alpha",
      customerId: "customer-legacy",
    })}`,
    { headers: { "X-Pasella-Bot-Token": botSecret } },
  );
  assert.equal(legacyOpenResponse.status, 200);
  const legacyOpen = (await legacyOpenResponse.json()).openSale;
  assert.equal(legacyOpen.id, "legacy-open-trusted");
  assert.equal(legacyOpen.source, "legacy");

  const ordersResponse = await fetch(`${functionsBase}/getCustomerOrders`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Pasella-Bot-Token": botSecret,
    },
    body: JSON.stringify({
      data: {
        merchantId: "store-alpha",
        customerId: "customer-alpha",
      },
    }),
  });
  assert.equal(ordersResponse.status, 200);
  const callableBody = await ordersResponse.json();
  assert.equal(callableBody.result.orders[0].source, "commerce");
  assert.equal(callableBody.result.orders[0].id, "commerce-order-alpha");
  assert.equal(callableBody.result.orders[1].source, "legacy");
  assert.equal(callableBody.result.orders[1].id, "legacy-order-alpha");
});
