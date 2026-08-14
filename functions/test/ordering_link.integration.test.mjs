import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import admin from "firebase-admin";
import functionsTest from "firebase-functions-test";
import { getMerchantOrderingLink } from "../lib/ecommerce/getMerchantOrderingLink.js";

const projectId = process.env.GCLOUD_PROJECT || "demo-spazaone-ordering-link";
const fft = functionsTest({ projectId });
const db = admin.firestore();
const originalOrderingNumber = process.env.ORDERING_WHATSAPP_NUMBER;

const ownerContext = {
  auth: {
    uid: "ordering-owner",
    token: {
      phone_number: "+27820000901",
      auth_time: Math.floor(Date.now() / 1000),
      firebase: { sign_in_provider: "phone" },
    },
  },
};

const strangerContext = {
  auth: {
    uid: "ordering-stranger",
    token: {
      phone_number: "+27820000902",
      auth_time: Math.floor(Date.now() / 1000),
      firebase: { sign_in_provider: "phone" },
    },
  },
};

async function clearOrderingData() {
  await Promise.all([
    admin.firestore().recursiveDelete(db.collection("users")),
    admin.firestore().recursiveDelete(db.collection("merchant_referrals")),
    admin.firestore().recursiveDelete(db.collection("stores")),
  ]);
}

before(async () => {
  await clearOrderingData();
  await db.doc("users/ordering-owner").set({
    shopName: "Ordering Test Shop",
  });
});

after(async () => {
  if (originalOrderingNumber == null) {
    delete process.env.ORDERING_WHATSAPP_NUMBER;
  } else {
    process.env.ORDERING_WHATSAPP_NUMBER = originalOrderingNumber;
  }
  await clearOrderingData();
  fft.cleanup();
});

test("missing direct WhatsApp configuration creates no referral or link", async () => {
  delete process.env.ORDERING_WHATSAPP_NUMBER;
  const callable = fft.wrap(getMerchantOrderingLink);

  await assert.rejects(
    () => callable({ action: "get", storeId: "ordering-owner" }, ownerContext),
    /not configured/i,
  );

  assert.equal((await db.collection("merchant_referrals").get()).size, 0);
  assert.equal(
    (await db.doc("users/ordering-owner").get()).get("whatsappOrdering"),
    undefined,
  );
});

test("zero-product shop creates one stable direct-WhatsApp link", async () => {
  process.env.ORDERING_WHATSAPP_NUMBER = "+27600000000";
  const callable = fft.wrap(getMerchantOrderingLink);
  const results = await Promise.all(
    Array.from({ length: 5 }, () =>
      callable({ action: "get", storeId: "ordering-owner" }, ownerContext),
    ),
  );

  assert.equal(new Set(results.map((result) => result.code)).size, 1);
  assert.match(results[0].orderingUrl, /^https:\/\/wa\.me\/27600000000/);
  assert.equal(
    (await db.doc("users/ordering-owner").get()).get("whatsappOrdering.code"),
    results[0].code,
  );
  const referrals = await db
    .collection("merchant_referrals")
    .where("merchantId", "==", "ordering-owner")
    .where("status", "==", "active")
    .get();
  assert.equal(referrals.size, 1);
});

test("failed regeneration preserves the active link", async () => {
  const callable = fft.wrap(getMerchantOrderingLink);
  const before = (await db.doc("users/ordering-owner").get()).get(
    "whatsappOrdering.code",
  );
  delete process.env.ORDERING_WHATSAPP_NUMBER;

  await assert.rejects(
    () =>
      callable(
        { action: "regenerate", storeId: "ordering-owner" },
        ownerContext,
      ),
    /not configured/i,
  );

  const afterCode = (await db.doc("users/ordering-owner").get()).get(
    "whatsappOrdering.code",
  );
  assert.equal(afterCode, before);
  assert.equal(
    (await db.doc(`merchant_referrals/${before}`).get()).get("status"),
    "active",
  );
});

test("successful regeneration atomically retires the previous code", async () => {
  process.env.ORDERING_WHATSAPP_NUMBER = "+27600000000";
  const callable = fft.wrap(getMerchantOrderingLink);
  const oldCode = (await db.doc("users/ordering-owner").get()).get(
    "whatsappOrdering.code",
  );
  const replacement = await callable(
    { action: "regenerate", storeId: "ordering-owner" },
    ownerContext,
  );

  assert.notEqual(replacement.code, oldCode);
  assert.equal(replacement.regenerated, true);
  assert.equal(
    (await db.doc(`merchant_referrals/${oldCode}`).get()).get("status"),
    "revoked",
  );
  assert.equal(
    (await db.doc(`merchant_referrals/${replacement.code}`).get()).get(
      "status",
    ),
    "active",
  );
});

test("another user cannot manage the shop link", async () => {
  process.env.ORDERING_WHATSAPP_NUMBER = "+27600000000";
  await assert.rejects(
    () =>
      fft.wrap(getMerchantOrderingLink)(
        { action: "get", storeId: "ordering-owner" },
        strangerContext,
      ),
    /do not have access/i,
  );
});
