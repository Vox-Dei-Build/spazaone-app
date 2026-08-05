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

const splitOwnerContext = {
  auth: {
    uid: "owner-split",
    token: {
      name: "Split Owner",
      phone_number: "+27820000006",
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
    admin.auth().createUser({
      uid: "owner-split",
      phoneNumber: "+27820000006",
      displayName: "Split Owner",
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

test("adopts a legacy owner and automatically shares credits with an added store", async () => {
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

  await db.doc("users/owner-a/wallet/current").set({
    virtualBalance: 15,
    salesVirtualBalance: 120,
  });
  const created = await create(
    {
      name: "Second Shop",
      operatorName: "Owner A",
      campaignCreditsMode: "shared-v1",
      shareCampaignCredits: true,
    },
    ownerContext,
  );
  assert.notEqual(created.storeId, "owner-a");
  assert.equal(created.sharedCampaignCredits, true);
  assert.equal(created.campaignWalletStoreId, "owner-a");
  assert.equal(
    (await db.doc(`users/${created.storeId}/wallet/current`).get()).get(
      "virtualBalance",
    ),
    0,
  );
  assert.equal(
    (await db.doc("stores/owner-a").get()).get(
      "sharedCampaignCreditsEnabled",
    ),
    true,
  );
  assert.equal(
    (await db.doc("campaignWalletBalances/owner-a").get()).get("balance"),
    15,
  );
  const afterCreate = await bootstrap({}, ownerContext);
  assert.deepEqual(
    afterCreate.stores.map((store) => store.storeName),
    ["Legacy Alpha", "Second Shop"],
  );

  await assertStoreAccess("owner-a", created.storeId);
  await assert.rejects(
    () => assertStoreAccess("operator-a", created.storeId),
    /do not have access/i,
  );
});

test("old clients are blocked and capable clients cannot opt out of the shared wallet", async () => {
  const create = fft.wrap(createStore);

  await assert.rejects(
    () =>
      create(
        {
          name: "Outdated Client Shop",
          operatorName: "Owner A",
        },
        ownerContext,
      ),
    /update Spaza One/i,
  );

  const created = await create(
    {
      name: "Always Shared Shop",
      operatorName: "Owner A",
      campaignCreditsMode: "shared-v1",
      shareCampaignCredits: false,
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

test("refuses to create another isolated wallet when owned stores need migration", async () => {
  const create = fft.wrap(createStore);
  const stores = [
    { id: "split-primary", name: "Split Primary", balance: 20 },
    { id: "split-secondary", name: "Split Secondary", balance: 0 },
  ];
  for (const store of stores) {
    await Promise.all([
      db.doc(`stores/${store.id}`).set({
        name: store.name,
        ownerUid: "owner-split",
        status: "active",
        schemaVersion: 2,
      }),
      db.doc(`stores/${store.id}/operators/owner-split`).set({
        uid: "owner-split",
        storeId: store.id,
        role: "owner",
        status: "active",
      }),
      db.doc(`operators/owner-split/stores/${store.id}`).set({
        uid: "owner-split",
        storeId: store.id,
        storeName: store.name,
        role: "owner",
        status: "active",
      }),
      db.doc(`users/${store.id}/wallet/current`).set({
        virtualBalance: store.balance,
      }),
    ]);
  }

  await assert.rejects(
    () =>
      create(
        {
          name: "Unsafe Third Shop",
          operatorName: "Split Owner",
          campaignCreditsMode: "shared-v1",
          shareCampaignCredits: true,
        },
        splitOwnerContext,
      ),
    /one-time campaign credit migration/i,
  );
  assert.equal(
    (
      await db
        .collection("stores")
        .where("ownerUid", "==", "owner-split")
        .get()
    ).size,
    2,
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
  assert.deepEqual(
    claimed.stores.map((store) => store.storeName),
    ["Legacy Alpha"],
  );
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
