import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";
import admin from "firebase-admin";
import functionsTest from "firebase-functions-test";
import {
  debitCampaignCredits,
  recordCampaignReservationSpend,
  reserveCampaignCredits,
  settleCampaignReservation,
  transferSalesToCampaignCredits,
} from "../lib/wallet/campaignCredits.js";

const projectId =
  process.env.GCLOUD_PROJECT || "demo-spazaone-shared-credits";
const fft = functionsTest({ projectId });
const db = admin.firestore();

const ownerContext = {
  auth: { uid: "owner-shared", token: { name: "Shared Owner" } },
};
const operatorContext = {
  auth: { uid: "operator-secondary", token: { name: "Operator" } },
};

async function clear() {
  for (const collection of [
    "users",
    "stores",
    "operators",
    "campaignWalletBalances",
    "campaignWalletAccess",
    "campaignWalletOperations",
    "campaignWalletReservations",
  ]) {
    await admin.firestore().recursiveDelete(db.collection(collection));
  }
}

async function seedShared(balance = 25) {
  await Promise.all([
    db.doc("stores/owner-shared").set({
      ownerUid: "owner-shared",
      status: "active",
      sharedCampaignCreditsEnabled: true,
      campaignWalletStoreId: "owner-shared",
    }),
    db.doc("stores/store-secondary").set({
      ownerUid: "owner-shared",
      status: "active",
      sharedCampaignCreditsEnabled: true,
      campaignWalletStoreId: "owner-shared",
    }),
    db.doc("stores/owner-shared/operators/owner-shared").set({
      role: "owner",
      status: "active",
    }),
    db.doc("stores/store-secondary/operators/operator-secondary").set({
      role: "operator",
      status: "active",
    }),
    db.doc("users/owner-shared/wallet/current").set({
      virtualBalance: balance,
      salesVirtualBalance: 900,
    }),
    db.doc("users/store-secondary/wallet/current").set({
      virtualBalance: 0,
      salesVirtualBalance: 40,
    }),
    db.doc("campaignWalletBalances/owner-shared").set({
      balance,
      shared: true,
      walletStoreId: "owner-shared",
    }),
  ]);
}

before(clear);
beforeEach(async () => {
  await clear();
  await seedShared();
});
after(async () => {
  await clear();
  fft.cleanup();
});

test("secondary operator debits canonical credits without touching sales", async () => {
  const debit = fft.wrap(debitCampaignCredits);
  const payload = {
    storeId: "store-secondary",
    amount: 5,
    operationId: "message-1",
    reason: "test",
  };
  const first = await debit(payload, operatorContext);
  const duplicate = await debit(payload, operatorContext);

  assert.equal(first.balance, 20);
  assert.equal(first.shared, true);
  assert.equal(duplicate.deduped, true);
  assert.equal(
    (await db.doc("users/owner-shared/wallet/current").get()).get(
      "virtualBalance",
    ),
    20,
  );
  assert.equal(
    (await db.doc("campaignWalletBalances/owner-shared").get()).get("balance"),
    20,
  );
  assert.equal(
    (await db.doc("users/owner-shared/wallet/current").get()).get(
      "salesVirtualBalance",
    ),
    900,
  );
  assert.equal(
    (await db.doc("users/store-secondary/wallet/current").get()).get(
      "salesVirtualBalance",
    ),
    40,
  );
});

test("sales transfer debits only the selected store and credits shared funds", async () => {
  const transfer = fft.wrap(transferSalesToCampaignCredits);
  const result = await transfer(
    {
      storeId: "store-secondary",
      amount: 10,
      operationId: "transfer-1",
    },
    operatorContext,
  );

  assert.equal(result.balance, 35);
  assert.equal(
    (await db.doc("users/store-secondary/wallet/current").get()).get(
      "salesVirtualBalance",
    ),
    30,
  );
  assert.equal(
    (await db.doc("users/owner-shared/wallet/current").get()).get(
      "salesVirtualBalance",
    ),
    900,
  );

  await db.doc("users/store-secondary/wallet/current").update({
    salesVirtualBalance: 0,
  });
  const duplicate = await transfer(
    {
      storeId: "store-secondary",
      amount: 10,
      operationId: "transfer-1",
    },
    operatorContext,
  );
  assert.equal(duplicate.deduped, true);
  assert.equal(duplicate.balance, 35);
});

test("concurrent stores cannot drive a shared wallet negative", async () => {
  await db.doc("users/owner-shared/wallet/current").update({
    virtualBalance: 10,
  });
  await db.doc("campaignWalletBalances/owner-shared").update({ balance: 10 });
  const debit = fft.wrap(debitCampaignCredits);

  const results = await Promise.allSettled([
    debit(
      {
        storeId: "owner-shared",
        amount: 7,
        operationId: "concurrent-primary",
      },
      ownerContext,
    ),
    debit(
      {
        storeId: "store-secondary",
        amount: 7,
        operationId: "concurrent-secondary",
      },
      operatorContext,
    ),
  ]);

  assert.equal(
    results.filter((result) => result.status === "fulfilled").length,
    1,
  );
  assert.equal(
    results.filter((result) => result.status === "rejected").length,
    1,
  );
  assert.equal(
    (await db.doc("users/owner-shared/wallet/current").get()).get(
      "virtualBalance",
    ),
    3,
  );
});

test("campaign reservations serialize the worst-case spend before sending", async () => {
  await db.doc("users/owner-shared/wallet/current").update({
    virtualBalance: 10,
  });
  await db.doc("campaignWalletBalances/owner-shared").update({ balance: 10 });
  const primaryWallet = {
    storeId: "owner-shared",
    walletStoreId: "owner-shared",
    shared: true,
  };
  const secondaryWallet = {
    storeId: "store-secondary",
    walletStoreId: "owner-shared",
    shared: true,
  };

  const results = await Promise.allSettled([
    reserveCampaignCredits(primaryWallet, "promo-primary", 7, "owner-shared"),
    reserveCampaignCredits(
      secondaryWallet,
      "promo-secondary",
      7,
      "operator-secondary",
    ),
  ]);
  assert.equal(
    results.filter((result) => result.status === "fulfilled").length,
    1,
  );
  assert.equal(
    (await db.doc("users/owner-shared/wallet/current").get()).get(
      "virtualBalance",
    ),
    3,
  );

  const reservation = results.find(
    (result) => result.status === "fulfilled",
  ).value;
  await assert.rejects(
    () =>
      reserveCampaignCredits(
        reservation.walletContext,
        reservation.walletContext.storeId === "owner-shared"
          ? "promo-primary"
          : "promo-secondary",
        7,
      ),
    /already running|already been sent/i,
  );
  assert.equal(
    (await db.doc("users/owner-shared/wallet/current").get()).get(
      "virtualBalance",
    ),
    3,
  );
  await db.runTransaction((tx) =>
    recordCampaignReservationSpend(tx, reservation, 5),
  );
  await settleCampaignReservation(reservation);
  assert.equal(
    (await db.doc("users/owner-shared/wallet/current").get()).get(
      "virtualBalance",
    ),
    5,
  );
});

test("broken cross-owner wallet pointers fail closed", async () => {
  await db.doc("stores/other-owner").set({
    ownerUid: "other-owner",
    sharedCampaignCreditsEnabled: true,
    campaignWalletStoreId: "other-owner",
  });
  await db.doc("stores/store-secondary").update({
    campaignWalletStoreId: "other-owner",
  });

  await assert.rejects(
    () =>
      fft.wrap(debitCampaignCredits)(
        {
          storeId: "store-secondary",
          amount: 1,
          operationId: "cross-owner",
        },
        operatorContext,
      ),
    /temporarily unavailable/i,
  );
});
