import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { after, before, test } from "node:test";
import admin from "firebase-admin";

const projectId =
  process.env.GCLOUD_PROJECT || "demo-spazaone-shared-credits";
if (!admin.apps.length) admin.initializeApp({ projectId });
const db = admin.firestore();
const ownerUid = "migration-shared-owner";

function runMigration(...args) {
  return execFileSync(
    process.execPath,
    [
      "scripts/migrate-shared-campaign-credits.mjs",
      "--project",
      projectId,
      ...args,
    ],
    { cwd: process.cwd(), env: process.env, encoding: "utf8" },
  );
}

function spawnMigration(...args) {
  return spawnSync(
    process.execPath,
    [
      "scripts/migrate-shared-campaign-credits.mjs",
      "--project",
      projectId,
      ...args,
    ],
    { cwd: process.cwd(), env: process.env, encoding: "utf8" },
  );
}

async function clear() {
  for (const collection of [
    "users",
    "stores",
    "operators",
    "campaignWalletBalances",
    "campaignWalletAccess",
    "campaignWalletOperations",
    "sharedCampaignCreditMigrations",
  ]) {
    await admin.firestore().recursiveDelete(db.collection(collection));
  }
}

async function seed() {
  await Promise.all([
    db.doc(`stores/${ownerUid}`).set({
      name: "Primary",
      ownerUid,
      status: "active",
    }),
    db.doc("stores/migration-secondary").set({
      name: "Secondary",
      ownerUid,
      status: "active",
      createdAt: admin.firestore.Timestamp.now(),
    }),
    db.doc(`stores/${ownerUid}/operators/${ownerUid}`).set({
      role: "owner",
      status: "active",
    }),
    db.doc("stores/migration-secondary/operators/migration-operator").set({
      role: "operator",
      status: "active",
    }),
    db.doc(`users/${ownerUid}/wallet/current`).set({
      virtualBalance: 12,
      salesVirtualBalance: 500,
    }),
    db.doc("users/migration-secondary/wallet/current").set({
      virtualBalance: 3,
      salesVirtualBalance: 70,
    }),
  ]);
}

before(async () => {
  await clear();
  await seed();
});
after(clear);

test("production execution needs owner-scoped double confirmation", () => {
  const result = spawnSync(
    process.execPath,
    [
      "scripts/migrate-shared-campaign-credits.mjs",
      "--project",
      "pasella-ledger",
      "--owner",
      ownerUid,
      "--execute",
    ],
    { cwd: process.cwd(), env: process.env, encoding: "utf8" },
  );
  assert.notEqual(result.status, 0);
  assert.match(`${result.stdout}${result.stderr}`, /Production write blocked/);
});

test("dry-run is inert, balance merge is explicit, and safe rollback restores", async () => {
  const dryRun = JSON.parse(runMigration("--owner", ownerUid).trim());
  assert.equal(dryRun.mode, "dry-run");
  assert.equal(dryRun.mergedBalance, 15);
  assert.equal(dryRun.requiresBalanceMerge, true);
  assert.equal(
    (await db.doc(`stores/${ownerUid}`).get()).get(
      "sharedCampaignCreditsEnabled",
    ),
    undefined,
  );

  const refused = spawnMigration("--owner", ownerUid, "--execute");
  assert.notEqual(refused.status, 0);
  assert.match(
    `${refused.stdout}${refused.stderr}`,
    /allow-balance-merge/i,
  );

  const output = runMigration(
    "--owner",
    ownerUid,
    "--execute",
    "--allow-balance-merge",
  )
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line));
  const runId = output.at(-1).runId;
  assert.equal(output.at(-1).enrolled, true);
  assert.equal(
    (await db.doc(`users/${ownerUid}/wallet/current`).get()).get(
      "virtualBalance",
    ),
    15,
  );
  assert.equal(
    (
      await db.doc("users/migration-secondary/wallet/current").get()
    ).get("virtualBalance"),
    0,
  );
  assert.equal(
    (
      await db.doc(
        `campaignWalletAccess/${ownerUid}/members/migration-operator`,
      ).get()
    ).get("storeIds")[0],
    "migration-secondary",
  );
  assert.equal(
    (await db.doc(`campaignWalletBalances/${ownerUid}`).get()).get("balance"),
    15,
  );
  // Sales proceeds are never merged.
  assert.equal(
    (await db.doc(`users/${ownerUid}/wallet/current`).get()).get(
      "salesVirtualBalance",
    ),
    500,
  );
  assert.equal(
    (
      await db.doc("users/migration-secondary/wallet/current").get()
    ).get("salesVirtualBalance"),
    70,
  );

  const rollback = runMigration("--rollback", runId, "--execute")
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line));
  assert.equal(rollback.at(-1).rolledBack, true);
  assert.equal(
    (await db.doc(`users/${ownerUid}/wallet/current`).get()).get(
      "virtualBalance",
    ),
    12,
  );
  assert.equal(
    (
      await db.doc("users/migration-secondary/wallet/current").get()
    ).get("virtualBalance"),
    3,
  );
});

test("rollback refuses after any campaign-credit operation", async () => {
  const output = runMigration(
    "--owner",
    ownerUid,
    "--execute",
    "--allow-balance-merge",
  )
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line));
  const runId = output.at(-1).runId;
  await db
    .doc(`campaignWalletOperations/${ownerUid}/entries/activity-1`)
    .set({ kind: "test" });

  const refused = spawnMigration("--rollback", runId, "--execute");
  assert.notEqual(refused.status, 0);
  assert.match(
    `${refused.stdout}${refused.stderr}`,
    /Rollback refused/i,
  );
});
