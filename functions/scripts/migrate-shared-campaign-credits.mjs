#!/usr/bin/env node

import process from "node:process";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import {
  FieldValue,
  getFirestore,
} from "firebase-admin/firestore";

const args = new Map();
for (let index = 2; index < process.argv.length; index += 1) {
  const value = process.argv[index];
  if (!value.startsWith("--")) continue;
  const [key, inline] = value.slice(2).split("=", 2);
  const next = process.argv[index + 1];
  if (inline != null) args.set(key, inline);
  else if (next && !next.startsWith("--")) {
    args.set(key, next);
    index += 1;
  } else {
    args.set(key, true);
  }
}

const projectId = String(args.get("project") ?? "").trim();
const ownerUid = String(args.get("owner") ?? "").trim();
const rollbackRunId = String(args.get("rollback") ?? "").trim();
const execute = args.get("execute") === true;
const allowBalanceMerge = args.get("allow-balance-merge") === true;
const allowProductionWrite = args.get("allow-production-write") === true;
const productionProject = "pasella-ledger";

if (!projectId) {
  throw new Error(
    "Pass --project <firebase-project>. Dry-run is the default; add --execute to write.",
  );
}
if (!ownerUid && !rollbackRunId) {
  throw new Error(
    "Pass one explicit --owner <uid>. This migration never enrolls every merchant.",
  );
}
if (
  execute &&
  projectId === productionProject &&
  (!allowProductionWrite ||
    process.env.SHARED_CREDITS_PRODUCTION_CONFIRM !==
      `${productionProject}:${ownerUid || rollbackRunId}`)
) {
  throw new Error(
    "Production write blocked. Require --allow-production-write and " +
      "SHARED_CREDITS_PRODUCTION_CONFIRM=pasella-ledger:<owner-or-run-id>.",
  );
}

const app = initializeApp({
  projectId,
  ...(process.env.FIRESTORE_EMULATOR_HOST
    ? {}
    : { credential: applicationDefault() }),
});
const db = getFirestore(app);
const runId =
  rollbackRunId ||
  `shared-campaign-credits-${ownerUid}-${new Date()
    .toISOString()
    .replace(/[:.]/g, "-")}`;

function number(value, label) {
  const parsed = Number(value ?? 0);
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new Error(`${label} must be a non-negative number.`);
  }
  return Math.round(parsed * 100) / 100;
}

function timestampMillis(value) {
  return typeof value?.toMillis === "function"
    ? value.toMillis()
    : Number.MAX_SAFE_INTEGER;
}

async function loadPlan() {
  const storeSnapshot = await db
    .collection("stores")
    .where("ownerUid", "==", ownerUid)
    .get();
  if (storeSnapshot.size < 2) {
    throw new Error(
      `Owner ${ownerUid} needs at least two store records; found ${storeSnapshot.size}.`,
    );
  }

  const stores = [...storeSnapshot.docs].sort((left, right) => {
    const time =
      timestampMillis(left.data().createdAt) -
      timestampMillis(right.data().createdAt);
    return time || left.id.localeCompare(right.id);
  });
  const existingShared = stores.filter(
    (store) => store.data().sharedCampaignCreditsEnabled === true,
  );
  const existingWalletIds = new Set(
    existingShared.map((store) =>
      String(store.data().campaignWalletStoreId ?? ""),
    ),
  );
  if (existingWalletIds.size > 1) {
    throw new Error("Stores already point at conflicting campaign wallets.");
  }

  const canonicalStoreId =
    [...existingWalletIds][0] ||
    stores.find((store) => store.id === ownerUid)?.id ||
    stores[0].id;
  if (!stores.some((store) => store.id === canonicalStoreId)) {
    throw new Error(
      "The configured campaign wallet is not owned by this merchant.",
    );
  }

  const wallets = await db.getAll(
    ...stores.map((store) =>
      db.doc(`users/${store.id}/wallet/current`),
    ),
  );
  const balances = Object.fromEntries(
    wallets.map((wallet) => [
      wallet.ref.parent.parent.id,
      number(
        wallet.data()?.virtualBalance,
        `${wallet.ref.path}.virtualBalance`,
      ),
    ]),
  );
  const mergedBalance =
    Math.round(
      Object.values(balances).reduce((sum, balance) => sum + balance, 0) *
        100,
    ) / 100;
  const secondaryBalance = Object.entries(balances)
    .filter(([storeId]) => storeId !== canonicalStoreId)
    .reduce((sum, [, balance]) => sum + balance, 0);

  const membersByStore = new Map();
  for (const store of stores) {
    const members = await store.ref
      .collection("operators")
      .where("status", "==", "active")
      .get();
    membersByStore.set(store.id, members.docs.map((member) => member.id));
  }

  return {
    stores,
    canonicalStoreId,
    balances,
    mergedBalance,
    secondaryBalance: Math.round(secondaryBalance * 100) / 100,
    membersByStore,
  };
}

async function migrate() {
  const plan = await loadPlan();
  const summary = {
    mode: execute ? "execute" : "dry-run",
    projectId,
    ownerUid,
    runId,
    canonicalStoreId: plan.canonicalStoreId,
    storeIds: plan.stores.map((store) => store.id),
    balancesBefore: plan.balances,
    mergedBalance: plan.mergedBalance,
    requiresBalanceMerge: plan.secondaryBalance > 0,
    secondaryBalance: plan.secondaryBalance,
    currentUsersAffected: 1,
    allOtherUsersAffected: 0,
  };
  console.log(JSON.stringify(summary));
  if (!execute) return;
  if (plan.secondaryBalance > 0 && !allowBalanceMerge) {
    throw new Error(
      "Secondary stores contain campaign credits. Review the dry-run and add " +
        "--allow-balance-merge to merge them exactly once.",
    );
  }

  const writeCount =
    plan.stores.length * 2 +
    [...plan.membersByStore.values()].reduce(
      (sum, members) => sum + members.length,
      0,
    ) +
    2;
  if (writeCount > 450) {
    throw new Error(
      `Migration needs ${writeCount} writes; split operator cleanup before enrolling.`,
    );
  }

  const migrationRef = db.doc(`sharedCampaignCreditMigrations/${runId}`);
  await db.runTransaction(async (tx) => {
    const currentMigration = await tx.get(migrationRef);
    if (currentMigration.exists) {
      throw new Error("Migration run id already exists.");
    }
    const currentStores = await Promise.all(
      plan.stores.map((store) => tx.get(store.ref)),
    );
    const currentWallets = await Promise.all(
      plan.stores.map((store) =>
        tx.get(db.doc(`users/${store.id}/wallet/current`)),
      ),
    );

    for (const store of currentStores) {
      const data = store.data() ?? {};
      if (
        data.sharedCampaignCreditsEnabled === true &&
        String(data.campaignWalletStoreId ?? "") !== plan.canonicalStoreId
      ) {
        throw new Error(`${store.id} changed after the dry-run.`);
      }
    }
    for (const wallet of currentWallets) {
      const storeId = wallet.ref.parent.parent.id;
      const currentBalance = number(
        wallet.data()?.virtualBalance,
        `${wallet.ref.path}.virtualBalance`,
      );
      if (currentBalance !== plan.balances[storeId]) {
        throw new Error(`${storeId} balance changed after the dry-run.`);
      }
    }

    const now = FieldValue.serverTimestamp();
    for (const store of plan.stores) {
      tx.set(
        store.ref,
        {
          sharedCampaignCreditsEnabled: true,
          campaignWalletStoreId: plan.canonicalStoreId,
          sharedCampaignCreditsEnrolledAt: now,
          sharedCampaignCreditsSource: "migration-script",
          sharedCampaignCreditsMigrationRunId: runId,
        },
        { merge: true },
      );
      tx.set(
        db.doc(`users/${store.id}/wallet/current`),
        {
          virtualBalance:
            store.id === plan.canonicalStoreId ? plan.mergedBalance : 0,
          sharedCampaignCreditsMigrationRunId: runId,
        },
        { merge: true },
      );
      for (const uid of plan.membersByStore.get(store.id) ?? []) {
        tx.set(
          db.doc(
            `campaignWalletAccess/${plan.canonicalStoreId}/members/${uid}`,
          ),
          {
            uid,
            walletStoreId: plan.canonicalStoreId,
            storeIds: FieldValue.arrayUnion(store.id),
            updatedAt: now,
            migrationRunId: runId,
          },
          { merge: true },
        );
      }
    }
    tx.set(db.doc(`campaignWalletBalances/${plan.canonicalStoreId}`), {
      walletStoreId: plan.canonicalStoreId,
      balance: plan.mergedBalance,
      shared: true,
      sourceStoreId: plan.canonicalStoreId,
      updatedAt: now,
      migrationRunId: runId,
    });
    tx.create(migrationRef, {
      ownerUid,
      canonicalStoreId: plan.canonicalStoreId,
      storeIds: plan.stores.map((store) => store.id),
      membersByStore: Object.fromEntries(plan.membersByStore),
      balancesBefore: plan.balances,
      balancesAfter: Object.fromEntries(
        plan.stores.map((store) => [
          store.id,
          store.id === plan.canonicalStoreId ? plan.mergedBalance : 0,
        ]),
      ),
      status: "active",
      createdAt: now,
    });
  });
  console.log(JSON.stringify({ enrolled: true, runId }));
}

async function rollback() {
  const migrationRef = db.doc(
    `sharedCampaignCreditMigrations/${rollbackRunId}`,
  );
  const migration = await migrationRef.get();
  if (!migration.exists) {
    throw new Error(`Migration ${rollbackRunId} was not found.`);
  }
  const data = migration.data();
  const canonicalStoreId = String(data.canonicalStoreId ?? "");
  const storeIds = Array.isArray(data.storeIds) ? data.storeIds : [];
  const balancesBefore = data.balancesBefore ?? {};
  const balancesAfter = data.balancesAfter ?? {};
  const entries = await db
    .collection(`campaignWalletOperations/${canonicalStoreId}/entries`)
    .limit(1)
    .get();
  const currentWallets = await db.getAll(
    ...storeIds.map((storeId) =>
      db.doc(`users/${storeId}/wallet/current`),
    ),
  );
  const balancesUnchanged = currentWallets.every((wallet) => {
    const storeId = wallet.ref.parent.parent.id;
    return (
      number(wallet.data()?.virtualBalance, wallet.ref.path) ===
      number(balancesAfter[storeId], `${storeId} expected balance`)
    );
  });
  const safe =
    data.status === "active" && entries.empty && balancesUnchanged;

  console.log(
    JSON.stringify({
      mode: execute ? "rollback" : "rollback-dry-run",
      projectId,
      runId: rollbackRunId,
      ownerUid: data.ownerUid,
      canonicalStoreId,
      operationCountAtLeast: entries.size,
      balancesUnchanged,
      safe,
    }),
  );
  if (!execute) return;
  if (!safe) {
    throw new Error(
      "Rollback refused: campaign-credit activity or balance changes exist. " +
        "Disable new enrollment and use a reconciled forward migration.",
    );
  }

  const membersByStore = data.membersByStore ?? {};
  await db.runTransaction(async (tx) => {
    const freshMigration = await tx.get(migrationRef);
    if (freshMigration.data()?.status !== "active") {
      throw new Error("Migration is no longer active.");
    }
    const now = FieldValue.serverTimestamp();
    for (const storeId of storeIds) {
      tx.set(
        db.doc(`users/${storeId}/wallet/current`),
        {
          virtualBalance: number(
            balancesBefore[storeId],
            `${storeId} original balance`,
          ),
          sharedCampaignCreditsMigrationRunId: FieldValue.delete(),
        },
        { merge: true },
      );
      tx.set(
        db.doc(`stores/${storeId}`),
        {
          sharedCampaignCreditsEnabled: FieldValue.delete(),
          campaignWalletStoreId: FieldValue.delete(),
          sharedCampaignCreditsEnrolledAt: FieldValue.delete(),
          sharedCampaignCreditsSource: FieldValue.delete(),
          sharedCampaignCreditsMigrationRunId: FieldValue.delete(),
        },
        { merge: true },
      );
      for (const uid of membersByStore[storeId] ?? []) {
        tx.set(
          db.doc(
            `campaignWalletAccess/${canonicalStoreId}/members/${uid}`,
          ),
          {
            storeIds: FieldValue.arrayRemove(storeId),
            updatedAt: now,
          },
          { merge: true },
        );
      }
    }
    tx.delete(db.doc(`campaignWalletBalances/${canonicalStoreId}`));
    tx.set(
      migrationRef,
      { status: "rolled-back", rolledBackAt: now },
      { merge: true },
    );
  });
  console.log(JSON.stringify({ rolledBack: true, runId: rollbackRunId }));
}

if (rollbackRunId) await rollback();
else await migrate();
