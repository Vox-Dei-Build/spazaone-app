#!/usr/bin/env node

import process from "node:process";
import { pathToFileURL } from "node:url";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const PRODUCTION_PROJECT = "pasella-ledger";
const DEVELOPMENT_PROJECTS = new Set(["spazaone-dev", "spazaone-dev-za"]);

function readArgs(argv) {
  const result = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (!value.startsWith("--")) continue;
    const [key, inline] = value.slice(2).split("=", 2);
    const next = argv[index + 1];
    if (inline != null) result.set(key, inline);
    else if (next && !next.startsWith("--")) {
      result.set(key, next);
      index += 1;
    } else result.set(key, true);
  }
  return result;
}

export function validateMigrationOptions(argv, env = process.env) {
  const args = readArgs(argv);
  const projectId = String(args.get("project") ?? "").trim();
  const execute = args.get("execute") === true;
  const verify = args.get("verify") === true;
  const runId = String(args.get("run-id") ?? "").trim();
  if (!projectId) throw new Error("Pass --project <firebase-project>.");
  if (execute && verify) throw new Error("Choose --execute or --verify.");
  if ((execute || verify) && !/^[A-Za-z0-9:_-]{1,120}$/.test(runId)) {
    throw new Error("Execute and verify require an explicit --run-id.");
  }
  if (projectId.startsWith("demo-") && !env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("A demo-* migration requires FIRESTORE_EMULATOR_HOST.");
  }
  if (projectId !== PRODUCTION_PROJECT &&
      !projectId.startsWith("demo-") &&
      !DEVELOPMENT_PROJECTS.has(projectId)) {
    throw new Error("Unregistered migration project.");
  }
  if (execute && projectId === PRODUCTION_PROJECT) {
    const confirmed = env.PAYMENTS_MIGRATION_PRODUCTION_CONFIRM === projectId;
    const backup = String(args.get("backup-evidence") ?? "").trim();
    if (!confirmed || !backup) {
      throw new Error(
        "Production apply requires backup evidence and action-time confirmation.",
      );
    }
  }
  return {
    projectId,
    execute,
    verify,
    runId: runId || `payments-v2-dry-${Date.now()}`,
    backupEvidence: String(args.get("backup-evidence") ?? "").trim() || null,
  };
}

async function scanLegacyBalances(db) {
  const users = await db.collection("users").get();
  let nonZeroLegacyBalances = 0;
  let invalidLegacyBalances = 0;
  for (const document of users.docs) {
    const raw = document.data().salesVirtualBalance;
    if (raw == null) continue;
    const amount = Number(raw);
    if (!Number.isFinite(amount)) invalidLegacyBalances += 1;
    else if (amount !== 0) nonZeroLegacyBalances += 1;
  }
  return {
    usersScanned: users.size,
    nonZeroLegacyBalances,
    invalidLegacyBalances,
    historicalDocumentsModified: 0,
  };
}

async function runMigration(options) {
  const app = initializeApp({
    projectId: options.projectId,
    ...(process.env.FIRESTORE_EMULATOR_HOST
      ? {}
      : { credential: applicationDefault() }),
  });
  const db = getFirestore(app);
  const runRef = db.doc(`financialMigrationRuns/${options.runId}`);
  const schemaRef = db.doc("schemaMetadata/paymentsV2");

  if (options.verify) {
    const [run, schema] = await Promise.all([runRef.get(), schemaRef.get()]);
    const valid = run.exists &&
      run.data()?.status === "applied" &&
      schema.exists &&
      schema.data()?.schemaVersion === 2 &&
      schema.data()?.migrationRunId === options.runId;
    if (!valid) throw new Error("PAYMENTS_V2_MIGRATION_VERIFICATION_FAILED");
    console.log(JSON.stringify({
      mode: "verify",
      projectId: options.projectId,
      runId: options.runId,
      verified: true,
      counts: run.data()?.counts ?? {},
    }));
    return;
  }

  const counts = await scanLegacyBalances(db);
  if (counts.invalidLegacyBalances > 0) {
    throw new Error("INVALID_LEGACY_BALANCE_REQUIRES_REVIEW");
  }
  if (!options.execute) {
    console.log(JSON.stringify({
      mode: "dry-run",
      projectId: options.projectId,
      runId: options.runId,
      counts,
      writesPlanned: 2,
    }));
    return;
  }

  let deduped = false;
  await db.runTransaction(async (tx) => {
    const [existingRun, existingSchema] = await Promise.all([
      tx.get(runRef),
      tx.get(schemaRef),
    ]);
    if (existingRun.exists) {
      if (existingRun.data()?.projectId !== options.projectId ||
          existingRun.data()?.status !== "applied" ||
          existingSchema.data()?.migrationRunId !== options.runId) {
        throw new Error("MIGRATION_RUN_BINDING_MISMATCH");
      }
      deduped = true;
      return;
    }
    const now = FieldValue.serverTimestamp();
    tx.set(schemaRef, {
      product: "SpazaOne",
      schema: "payments-v2",
      schemaVersion: 2,
      migrationRunId: options.runId,
      legacyBalancePolicy: "read_boundary_only",
      historicalDocumentsModified: 0,
      updatedAt: now,
    });
    tx.create(runRef, {
      runId: options.runId,
      projectId: options.projectId,
      migration: "payments-v2-additive-readiness",
      status: "applied",
      counts,
      backupEvidence: options.backupEvidence,
      compensatingEntryPolicy: true,
      createdAt: now,
      verifiedAt: null,
    });
  });
  console.log(JSON.stringify({
    mode: "execute",
    projectId: options.projectId,
    runId: options.runId,
    counts,
    deduped,
  }));
}

async function main() {
  const options = validateMigrationOptions(process.argv.slice(2));
  await runMigration(options);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
