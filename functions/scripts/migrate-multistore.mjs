#!/usr/bin/env node

import { createHash } from "node:crypto";
import process from "node:process";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

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
  } else args.set(key, true);
}

const projectId = String(args.get("project") ?? "").trim();
const execute = args.get("execute") === true;
const allowProductionWrite = args.get("allow-production-write") === true;
const limit = Math.max(1, Number(args.get("limit") ?? 10000));
const rollbackRunId = String(args.get("rollback") ?? "").trim();
const productionProject = "pasella-ledger";

if (!projectId) {
  throw new Error(
    "Pass --project <firebase-project>. Dry-run is the default; add --execute to write.",
  );
}

if (
  execute &&
  projectId === productionProject &&
  (!allowProductionWrite ||
    process.env.MULTISTORE_PRODUCTION_CONFIRM !== productionProject)
) {
  throw new Error(
    "Production write blocked. Require both --allow-production-write and " +
      "MULTISTORE_PRODUCTION_CONFIRM=pasella-ledger.",
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
  `multistore-v2-${new Date().toISOString().replace(/[:.]/g, "-")}`;

function e164(raw) {
  const digits = String(raw ?? "").replace(/\D/g, "");
  if (/^0[6-9][0-9]{8}$/.test(digits)) return `+27${digits.slice(1)}`;
  if (/^27[6-9][0-9]{8}$/.test(digits)) return `+${digits}`;
  return "";
}

function hashPhone(phone) {
  return createHash("sha256").update(phone).digest("hex");
}

async function rollback() {
  const stores = await db
    .collection("stores")
    .where("migrationRunId", "==", rollbackRunId)
    .limit(limit)
    .get();
  console.log(
    JSON.stringify({
      mode: execute ? "rollback" : "rollback-dry-run",
      projectId,
      runId: rollbackRunId,
      stores: stores.size,
    }),
  );
  if (!execute) return;

  for (const store of stores.docs) {
    const storeData = store.data();
    const operators = await store.ref.collection("operators").get();
    const batch = db.batch();
    for (const member of operators.docs) {
      batch.delete(db.doc(`operators/${member.id}/stores/${store.id}`));
      batch.delete(member.ref);
    }
    if (storeData.operatorPhoneHash) {
      batch.delete(
        db.doc(
          `operatorPhoneLookup/${storeData.operatorPhoneHash}/stores/${store.id}`,
        ),
      );
    }
    batch.delete(store.ref);
    await batch.commit();
  }
  console.log(
    JSON.stringify({ rolledBack: stores.size, runId: rollbackRunId }),
  );
}

async function migrate() {
  const users = await db.collection("users").limit(limit).get();
  let planned = 0;
  let skipped = 0;
  for (const user of users.docs) {
    const storeRef = db.doc(`stores/${user.id}`);
    if ((await storeRef.get()).exists) {
      skipped += 1;
      continue;
    }
    planned += 1;
    if (!execute) continue;

    const data = user.data();
    const storeName = String(data.shopName ?? data.name ?? "My Store").trim();
    const phone = e164(data.mobileNumber);
    const fcmTokens = [
      data.fcmToken,
      ...(Array.isArray(data.fcmTokens) ? data.fcmTokens : []),
    ]
      .filter((token) => typeof token === "string" && token.trim())
      .map((token) => token.trim());
    const shared = {
      storeId: user.id,
      uid: user.id,
      role: "owner",
      status: "active",
      displayName: String(data.name ?? "Owner"),
      phoneLast4: phone.replace(/\D/g, "").slice(-4),
      joinedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      source: "migration-script",
      schemaVersion: 2,
      migrationRunId: runId,
      ...(fcmTokens.length
        ? {
            fcmToken: fcmTokens[0],
            fcmTokens: [...new Set(fcmTokens)],
            notificationUpdatedAt: FieldValue.serverTimestamp(),
          }
        : {}),
    };
    const batch = db.batch();
    batch.create(storeRef, {
      name: storeName,
      ownerUid: user.id,
      status: "active",
      legacyUserPath: `users/${user.id}`,
      schemaVersion: 2,
      migrationRunId: runId,
      migratedAt: FieldValue.serverTimestamp(),
      migrationSource: "legacy-owner-v1",
      operatorPhoneHash: phone ? hashPhone(phone) : null,
    });
    batch.set(db.doc(`stores/${user.id}/operators/${user.id}`), shared);
    batch.set(db.doc(`operators/${user.id}/stores/${user.id}`), {
      ...shared,
      storeName,
    });
    if (phone) {
      batch.set(
        db.doc(`operatorPhoneLookup/${hashPhone(phone)}/stores/${user.id}`),
        {
          storeId: user.id,
          uid: user.id,
          role: "owner",
          status: "active",
          storeName,
          updatedAt: FieldValue.serverTimestamp(),
          migrationRunId: runId,
        },
      );
    }
    await batch.commit();
  }

  console.log(
    JSON.stringify({
      mode: execute ? "execute" : "dry-run",
      projectId,
      runId,
      scanned: users.size,
      planned,
      skipped,
      existingUserDocumentsModified: 0,
    }),
  );
}

if (rollbackRunId) await rollback();
else await migrate();
