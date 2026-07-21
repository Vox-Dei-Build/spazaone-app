import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { after, before, test } from "node:test";
import admin from "firebase-admin";

const projectId = process.env.GCLOUD_PROJECT || "demo-spazaone-multistore";
if (!admin.apps.length) admin.initializeApp({ projectId });
const db = admin.firestore();

function runMigration(...args) {
  return execFileSync(
    process.execPath,
    ["scripts/migrate-multistore.mjs", "--project", projectId, ...args],
    { cwd: process.cwd(), env: process.env, encoding: "utf8" },
  );
}

async function clear() {
  for (const collection of [
    "users",
    "stores",
    "operators",
    "operatorPhoneLookup",
  ]) {
    await admin.firestore().recursiveDelete(db.collection(collection));
  }
}

before(async () => {
  await clear();
  await db.doc("users/migrate-owner").set({
    name: "Migration Owner",
    shopName: "Migration Shop",
    mobileNumber: "0820000010",
    fcmToken: "migration-device",
    fcmTokens: ["migration-device"],
    protectedLegacyValue: 42,
  });
});

after(clear);

test("production execution is blocked without two explicit confirmations", () => {
  const result = spawnSync(
    process.execPath,
    [
      "scripts/migrate-multistore.mjs",
      "--project",
      "pasella-ledger",
      "--execute",
    ],
    { cwd: process.cwd(), env: process.env, encoding: "utf8" },
  );
  assert.notEqual(result.status, 0);
  assert.match(`${result.stdout}${result.stderr}`, /Production write blocked/);
});

test("dry-run is inert and execute/rollback never changes legacy data", async () => {
  const beforeUser = (await db.doc("users/migrate-owner").get()).data();
  const dryRun = JSON.parse(runMigration().trim());
  assert.equal(dryRun.mode, "dry-run");
  assert.equal(dryRun.planned, 1);
  assert.equal((await db.doc("stores/migrate-owner").get()).exists, false);

  const executed = JSON.parse(runMigration("--execute").trim());
  assert.equal(executed.mode, "execute");
  assert.equal(executed.existingUserDocumentsModified, 0);
  const store = await db.doc("stores/migrate-owner").get();
  assert.equal(store.exists, true);
  const runId = store.get("migrationRunId");
  const member = await db
    .doc("stores/migrate-owner/operators/migrate-owner")
    .get();
  assert.deepEqual(member.get("fcmTokens"), ["migration-device"]);
  assert.deepEqual(
    (await db.doc("users/migrate-owner").get()).data(),
    beforeUser,
  );

  const rollbackOutput = runMigration("--rollback", runId, "--execute")
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line));
  assert.equal(rollbackOutput.at(-1).rolledBack, 1);
  assert.equal((await db.doc("stores/migrate-owner").get()).exists, false);
  assert.equal(
    (await db.doc("operators/migrate-owner/stores/migrate-owner").get()).exists,
    false,
  );
  assert.deepEqual(
    (await db.doc("users/migrate-owner").get()).data(),
    beforeUser,
  );
});
