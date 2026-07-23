const assert = require("node:assert/strict");
const { createHmac } = require("node:crypto");
const { after, before, test } = require("node:test");
const admin = require("firebase-admin");
const axios = require("axios");
const {
  verifyPaystackTransaction,
} = require("../lib/payments/paystack/verifyPaystackTransaction.js");

const projectId = process.env.GCLOUD_PROJECT || "demo-spazaone-shared-credits";
const db = admin.firestore();
const secret = "emulator-paystack-secret";
const originalAxiosAdapter = axios.defaults.adapter;

async function clear() {
  for (const collection of [
    "users",
    "stores",
    "payments",
    "campaignWalletBalances",
    "campaignWalletOperations",
  ]) {
    await admin.firestore().recursiveDelete(db.collection(collection));
  }
}

function responseRecorder() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
    send(body) {
      this.body = body;
      return this;
    },
  };
}

async function sendVerifiedWebhook({
  reference,
  purpose,
  saleId,
  amountCents = 10_000,
  feeCents = 100,
}) {
  const body = {
    event: "charge.success",
    data: { reference },
  };
  const rawBody = Buffer.from(JSON.stringify(body));
  axios.defaults.adapter = async (config) => ({
    data: {
      status: true,
      data: {
        status: "success",
        reference,
        currency: "ZAR",
        amount: amountCents,
        fees: feeCents,
        channel: "card",
        metadata: {
          merchantId: "store-secondary",
          purpose,
          saleId: saleId ?? null,
          initiatedBy: "operator-secondary",
        },
      },
    },
    status: 200,
    statusText: "OK",
    headers: {},
    config,
  });
  const request = {
    method: "POST",
    body,
    rawBody,
    get(name) {
      return name.toLowerCase() === "x-paystack-signature"
        ? createHmac("sha512", secret).update(rawBody).digest("hex")
        : undefined;
    },
  };
  const response = responseRecorder();
  await verifyPaystackTransaction(request, response);
  return response;
}

before(async () => {
  process.env.PAYSTACK_SECRET_KEY = secret;
  await clear();
  await Promise.all([
    db.doc("stores/owner-shared").set({
      ownerUid: "owner-shared",
      sharedCampaignCreditsEnabled: true,
      campaignWalletStoreId: "owner-shared",
    }),
    db.doc("stores/store-secondary").set({
      ownerUid: "owner-shared",
      sharedCampaignCreditsEnabled: true,
      campaignWalletStoreId: "owner-shared",
    }),
    db.doc("users/owner-shared/wallet/current").set({
      virtualBalance: 25,
      salesVirtualBalance: 900,
    }),
    db.doc("users/store-secondary/wallet/current").set({
      virtualBalance: 0,
      salesVirtualBalance: 40,
    }),
    db.doc("campaignWalletBalances/owner-shared").set({
      balance: 25,
      shared: true,
      walletStoreId: "owner-shared",
    }),
  ]);
});

after(async () => {
  axios.defaults.adapter = originalAxiosAdapter;
  delete process.env.PAYSTACK_SECRET_KEY;
  await clear();
});

test("top-up credits the shared wallet and remains idempotent", async () => {
  const first = await sendVerifiedWebhook({
    reference: "shared-topup-1",
    purpose: "topup",
  });
  const duplicate = await sendVerifiedWebhook({
    reference: "shared-topup-1",
    purpose: "topup",
  });

  assert.equal(first.statusCode, 200);
  assert.equal(duplicate.statusCode, 200);
  assert.equal(duplicate.body.deduped, true);
  assert.equal(
    (await db.doc("users/owner-shared/wallet/current").get()).get(
      "virtualBalance",
    ),
    124,
  );
  assert.equal(
    (await db.doc("users/store-secondary/wallet/current").get()).get(
      "virtualBalance",
    ),
    0,
  );
  assert.equal(
    (await db.doc("campaignWalletBalances/owner-shared").get()).get("balance"),
    124,
  );
  assert.equal(
    (
      await db
        .doc("users/store-secondary/topUpTransactions/shared-topup-1")
        .get()
    ).get("netAmount"),
    99,
  );
});

test("sale proceeds stay on the selected store", async () => {
  await db.doc("users/store-secondary/sales/sale-1").set({
    amount: 100,
    status: "pending",
  });
  const response = await sendVerifiedWebhook({
    reference: "store-sale-1",
    purpose: "sale",
    saleId: "sale-1",
  });

  assert.equal(response.statusCode, 200);
  assert.equal(
    (await db.doc("users/store-secondary/wallet/current").get()).get(
      "salesVirtualBalance",
    ),
    139,
  );
  assert.equal(
    (await db.doc("users/owner-shared/wallet/current").get()).get(
      "salesVirtualBalance",
    ),
    900,
  );
  assert.equal(
    (await db.doc("users/owner-shared/wallet/current").get()).get(
      "virtualBalance",
    ),
    124,
  );
});
