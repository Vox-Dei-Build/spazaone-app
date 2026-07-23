import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import admin from "firebase-admin";
import functionsTest from "firebase-functions-test";
import {
  bootstrapStoreAccess,
  cancelStoreOperatorInvite,
  createStore,
  inviteStoreOperator,
  listStoreOperators,
  removeStoreOperator,
} from "../lib/stores/storeManagement.js";
import { assertStoreAccess } from "../lib/stores/storeAccess.js";
import { deleteUserAccount } from "../lib/services/deleteUserAccount.js";

const projectId = process.env.GCLOUD_PROJECT || "demo-spazaone-multistore";
const fft = functionsTest({ projectId });
const db = admin.firestore();

const ownerContext = {
  auth: {
    uid: "owner-a",
    token: {
      name: "Owner A",
      phone_number: "+27820000001",
      auth_time: Math.floor(Date.now() / 1000),
      firebase: { sign_in_provider: "phone" },
    },
  },
};

const operatorContext = {
  auth: {
    uid: "operator-a",
    token: {
      name: "Operator A",
      phone_number: "+27820000002",
      auth_time: Math.floor(Date.now() / 1000),
      firebase: { sign_in_provider: "phone" },
    },
  },
};

const pendingOperatorContext = {
  auth: {
    uid: "operator-pending",
    token: {
      name: "Pending Operator",
      phone_number: "+27820000003",
      auth_time: Math.floor(Date.now() / 1000),
      firebase: { sign_in_provider: "phone" },
    },
  },
};

const deletingOperatorContext = {
  auth: {
    uid: "operator-delete",
    token: {
      name: "Deleting Operator",
      phone_number: "+27820000005",
      auth_time: Math.floor(Date.now() / 1000),
      firebase: { sign_in_provider: "phone" },
    },
  },
};

async function clearEmulators() {
  for (const collection of [
    "users",
    "stores",
    "operators",
    "operatorInvites",
    "operatorPhoneLookup",
    "releaseControls",
    "campaignWalletBalances",
    "campaignWalletAccess",
    "campaignWalletOperations",
    "campaignWalletReservations",
  ]) {
    await admin.firestore().recursiveDelete(db.collection(collection));
  }
  const users = await admin.auth().listUsers();
  if (users.users.length) {
    await admin.auth().deleteUsers(users.users.map((user) => user.uid));
  }
}

before(async () => {
  await clearEmulators();
  await Promise.all([
    admin.auth().createUser({
      uid: "owner-a",
      phoneNumber: "+27820000001",
      displayName: "Owner A",
    }),
    admin.auth().createUser({
      uid: "operator-a",
      phoneNumber: "+27820000002",
      displayName: "Operator A",
    }),
    admin.auth().createUser({
      uid: "operator-delete",
      phoneNumber: "+27820000005",
      displayName: "Deleting Operator",
    }),
    db.doc("users/owner-a").set({
      name: "Owner A",
      shopName: "Legacy Alpha",
      mobileNumber: "+27820000001",
      fcmToken: "owner-device",
      fcmTokens: ["owner-device"],
    }),
  ]);
});

after(async () => {
  await clearEmulators();
  fft.cleanup();
});

test("adopts legacy owner, creates a zero-credit store, and enforces access", async () => {
  const bootstrap = fft.wrap(bootstrapStoreAccess);
  const create = fft.wrap(createStore);

  const adopted = await bootstrap({}, ownerContext);
  assert.equal(adopted.adoptedLegacyStore, true);
  assert.equal(adopted.stores[0].storeId, "owner-a");
  assert.equal(adopted.sharedCampaignCreditsEnrollmentAllowed, false);
  assert.deepEqual(
    (await db.doc("stores/owner-a/operators/owner-a").get()).get("fcmTokens"),
    ["owner-device"],
  );

  const created = await create(
    { name: "Second Shop", operatorName: "Owner A" },
    ownerContext,
  );
  assert.notEqual(created.storeId, "owner-a");
  assert.equal(
    (await db.doc(`users/${created.storeId}/wallet/current`).get()).get(
      "virtualBalance",
    ),
    0,
  );

  await assertStoreAccess("owner-a", created.storeId);
  await assert.rejects(
    () => assertStoreAccess("operator-a", created.storeId),
    /do not have access/i,
  );
});

test("shared store creation fails closed until the owner is server-allowed", async () => {
  const create = fft.wrap(createStore);
  await db.doc("users/owner-a/wallet/current").set({
    virtualBalance: 15,
    salesVirtualBalance: 120,
  });

  await assert.rejects(
    () =>
      create(
        {
          name: "Blocked Shared Shop",
          operatorName: "Owner A",
          shareCampaignCredits: true,
        },
        ownerContext,
      ),
    /not enabled/i,
  );

  await db.doc("releaseControls/sharedCampaignCredits").set({
    enabled: true,
    ownerUids: ["owner-a"],
  });
  const allowedBootstrap = await fft.wrap(bootstrapStoreAccess)(
    {},
    ownerContext,
  );
  assert.equal(allowedBootstrap.sharedCampaignCreditsEnrollmentAllowed, true);
  const created = await create(
    {
      name: "Shared Shop",
      operatorName: "Owner A",
      shareCampaignCredits: true,
    },
    ownerContext,
  );
  assert.equal(created.sharedCampaignCredits, true);
  assert.equal(created.campaignWalletStoreId, "owner-a");
  assert.equal(
    (await db.doc(`stores/${created.storeId}`).get()).get(
      "campaignWalletStoreId",
    ),
    "owner-a",
  );
  assert.equal(
    (await db.doc("campaignWalletBalances/owner-a").get()).get("balance"),
    15,
  );
  assert.equal(
    (await db.doc(`users/${created.storeId}/wallet/current`).get()).get(
      "virtualBalance",
    ),
    0,
  );
});

test("persists, claims, lists, and cancels pending phone invitations", async () => {
  const invite = fft.wrap(inviteStoreOperator);
  const list = fft.wrap(listStoreOperators);
  const cancel = fft.wrap(cancelStoreOperatorInvite);

  const invited = await invite(
    { storeId: "owner-a", phone: "0820000003", role: "admin" },
    ownerContext,
  );
  assert.equal(invited.status, "invited");
  let listing = await list({ storeId: "owner-a" }, ownerContext);
  assert.equal(listing.pendingInvites.length, 1);

  await admin.auth().createUser({
    uid: "operator-pending",
    phoneNumber: "+27820000003",
    displayName: "Pending Operator",
  });
  const claimed = await fft.wrap(bootstrapStoreAccess)(
    {},
    pendingOperatorContext,
  );
  assert.equal(claimed.claimedInvites, 1);
  await assertStoreAccess("operator-pending", "owner-a", ["admin"]);
  listing = await list({ storeId: "owner-a" }, ownerContext);
  assert.equal(listing.pendingInvites.length, 0);

  await invite(
    { storeId: "owner-a", phone: "0820000004", role: "operator" },
    ownerContext,
  );
  listing = await list({ storeId: "owner-a" }, ownerContext);
  assert.equal(listing.pendingInvites.length, 1);
  await cancel(
    {
      storeId: "owner-a",
      inviteId: listing.pendingInvites[0].inviteId,
    },
    ownerContext,
  );
  listing = await list({ storeId: "owner-a" }, ownerContext);
  assert.equal(listing.pendingInvites.length, 0);
});

test("adds an existing operator, revokes tokens, and prevents orphaning", async () => {
  const invite = fft.wrap(inviteStoreOperator);
  const remove = fft.wrap(removeStoreOperator);
  const removeAccount = fft.wrap(deleteUserAccount);

  const invited = await invite(
    { storeId: "owner-a", phone: "0820000002", role: "operator" },
    ownerContext,
  );
  assert.equal(invited.status, "added");
  await db
    .doc("stores/owner-a/operators/operator-a")
    .set(
      { fcmToken: "operator-device", fcmTokens: ["operator-device"] },
      { merge: true },
    );
  await db
    .doc("users/owner-a")
    .set(
      { fcmTokens: admin.firestore.FieldValue.arrayUnion("operator-device") },
      { merge: true },
    );

  await assertStoreAccess("operator-a", "owner-a");
  await assert.rejects(
    () => removeAccount({}, ownerContext),
    /STORE_HAS_OTHER_OPERATORS/,
  );

  await db
    .doc("stores/owner-a/operators/operator-a")
    .set({ status: "pending" }, { merge: true });
  await assert.rejects(
    () => assertStoreAccess("operator-a", "owner-a"),
    /do not have access/i,
  );
  await db
    .doc("stores/owner-a/operators/operator-a")
    .set({ status: "active" }, { merge: true });

  await remove({ storeId: "owner-a", operatorUid: "operator-a" }, ownerContext);
  await remove(
    { storeId: "owner-a", operatorUid: "operator-pending" },
    ownerContext,
  );
  assert.equal(
    (await db.doc("stores/owner-a/operators/operator-a").get()).get("status"),
    "disabled",
  );
  assert.deepEqual((await db.doc("users/owner-a").get()).get("fcmTokens"), [
    "owner-device",
  ]);
  await assert.rejects(
    () => assertStoreAccess("operator-a", "owner-a"),
    /do not have access/i,
  );

  const operatorStores = await fft.wrap(bootstrapStoreAccess)(
    {},
    operatorContext,
  );
  assert.equal(
    operatorStores.stores.some((store) => store.storeId === "owner-a"),
    false,
  );

  await invite(
    { storeId: "owner-a", phone: "0820000005", role: "operator" },
    ownerContext,
  );
  await db
    .doc("stores/owner-a/operators/operator-delete")
    .set(
      { fcmToken: "deleted-device", fcmTokens: ["deleted-device"] },
      { merge: true },
    );
  await db.doc("users/owner-a").set(
    {
      fcmToken: "deleted-device",
      fcmTokens: admin.firestore.FieldValue.arrayUnion("deleted-device"),
    },
    { merge: true },
  );
  await removeAccount({}, deletingOperatorContext);
  assert.equal(
    (await db.doc("stores/owner-a/operators/operator-delete").get()).exists,
    false,
  );
  const legacyTokens = (await db.doc("users/owner-a").get()).get("fcmTokens");
  assert.equal(legacyTokens.includes("deleted-device"), false);
  assert.equal((await db.doc("users/owner-a").get()).get("fcmToken"), undefined);
  assert.equal((await db.doc("users/owner-a").get()).exists, true);
});
