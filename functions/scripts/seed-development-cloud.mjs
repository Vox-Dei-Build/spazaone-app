#!/usr/bin/env node

import process from "node:process";
import { pathToFileURL } from "node:url";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const DEVELOPMENT_PROJECTS = new Set(["spazaone-dev", "spazaone-dev-za"]);
const SEED_VERSION = 2;
const MERCHANT_ID = "dev-seed-merchant";
const CUSTOMER_ID = "dev-seed-customer";
const ORDER_ID = "dev-seed-owned-order";

function argsMap(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (!value.startsWith("--")) continue;
    const [key, inline] = value.slice(2).split("=", 2);
    const next = argv[index + 1];
    if (inline != null) args.set(key, inline);
    else if (next && !next.startsWith("--")) {
      args.set(key, next);
      index += 1;
    } else args.set(key, true);
  }
  return args;
}

export function validateDevelopmentSeedOptions(argv) {
  const args = argsMap(argv);
  const projectId = String(args.get("project") ?? "").trim();
  const execute = args.get("execute") === true;
  const verify = args.get("verify") === true;
  const runId = String(args.get("run-id") ?? "").trim();
  if (!DEVELOPMENT_PROJECTS.has(projectId)) {
    throw new Error(
      "Development seed requires an explicit registered dev project.",
    );
  }
  if (execute && verify) throw new Error("Choose --execute or --verify.");
  if ((execute || verify) && !/^[A-Za-z0-9:_-]{1,120}$/.test(runId)) {
    throw new Error("Execute and verify require an explicit --run-id.");
  }
  return {
    projectId,
    execute,
    verify,
    runId: runId || `spazaone-development-dry-${Date.now()}`,
  };
}

function expectedPaths(runId) {
  return [
    `users/${MERCHANT_ID}`,
    `users/${MERCHANT_ID}/wallet/current`,
    `users/${MERCHANT_ID}/customers/${CUSTOMER_ID}`,
    `users/${MERCHANT_ID}/customers/${CUSTOMER_ID}/transactions/development_seed_credit`,
    `users/${MERCHANT_ID}/products/dev-seed-owned-product`,
    `users/${MERCHANT_ID}/sales/${ORDER_ID}`,
    `stores/${MERCHANT_ID}`,
    `stores/${MERCHANT_ID}/operators/${MERCHANT_ID}`,
    `operators/${MERCHANT_ID}/stores/${MERCHANT_ID}`,
    "paymentConfiguration/global",
    `developmentSeedRuns/${runId}`,
  ];
}

async function runSeed(options) {
  const app = initializeApp({
    projectId: options.projectId,
    credential: applicationDefault(),
  });
  const db = getFirestore(app);
  const paths = expectedPaths(options.runId);
  const runRef = db.doc(paths.at(-1));

  if (!options.execute && !options.verify) {
    console.log(
      JSON.stringify({
        mode: "dry-run",
        projectId: options.projectId,
        runId: options.runId,
        synthetic: true,
        writesPlanned: paths.length,
      }),
    );
    return;
  }

  if (options.verify) {
    const snapshots = await db.getAll(...paths.map((path) => db.doc(path)));
    const missing = snapshots.filter((snapshot) => !snapshot.exists);
    const invalid = snapshots.filter((snapshot) => {
      if (!snapshot.exists) return false;
      const data = snapshot.data() ?? {};
      if (snapshot.ref.path === "paymentConfiguration/global") {
        return (
          data.schemaVersion !== 2 ||
          Object.keys(data.capabilities ?? {}).length !== 0
        );
      }
      return (
        data.developmentSeedRunId !== options.runId || data.synthetic !== true
      );
    });
    if (missing.length || invalid.length) {
      throw new Error(
        `DEVELOPMENT_SEED_VERIFICATION_FAILED missing=${missing.length} invalid=${invalid.length}`,
      );
    }
    console.log(
      JSON.stringify({
        mode: "verify",
        projectId: options.projectId,
        runId: options.runId,
        verified: true,
        documents: snapshots.length,
      }),
    );
    return;
  }

  let deduped = false;
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(runRef);
    if (existing.exists) {
      const data = existing.data() ?? {};
      if (
        data.projectId !== options.projectId ||
        data.seedVersion !== SEED_VERSION
      ) {
        throw new Error("DEVELOPMENT_SEED_RUN_BINDING_MISMATCH");
      }
      deduped = true;
      return;
    }

    const now = FieldValue.serverTimestamp();
    const common = {
      synthetic: true,
      developmentSeedRunId: options.runId,
      updatedAt: now,
    };
    tx.set(db.doc(`users/${MERCHANT_ID}`), {
      ...common,
      name: "SpazaOne Dev Merchant",
      shopName: "SpazaOne Development Store",
      businessType: "Synthetic QA",
      businessCategory: "General dealer",
    });
    tx.set(db.doc(`users/${MERCHANT_ID}/wallet/current`), {
      ...common,
      virtualBalance: 250.0,
      salesVirtualBalance: 42.5,
      cashAdvanceBalance: 0.0,
      accountSuspended: false,
    });
    tx.set(db.doc(`users/${MERCHANT_ID}/customers/${CUSTOMER_ID}`), {
      ...common,
      name: "Synthetic Customer",
      number: "0000000000",
      category: "Customer",
      balance: -125.0,
      isNPA: false,
      ordersUnreadCount: 0,
    });
    tx.set(
      db.doc(
        `users/${MERCHANT_ID}/customers/${CUSTOMER_ID}/transactions/development_seed_credit`,
      ),
      {
        ...common,
        type: "Credit",
        amount: 125.0,
        amountMinor: 12_500,
        date: now,
        status: "DUE",
        remarks: "Synthetic development opening balance",
        source: "development_seed",
        schemaVersion: 2,
      },
    );
    tx.set(db.doc(`users/${MERCHANT_ID}/products/dev-seed-owned-product`), {
      ...common,
      name: "Development loaf",
      description: "Synthetic owned-stock product for payment QA.",
      cost: 12.0,
      sellingPrice: 16.0,
      quantity: 20,
      whatsappListed: true,
      isDropshipListing: false,
    });
    tx.set(db.doc(`users/${MERCHANT_ID}/sales/${ORDER_ID}`), {
      ...common,
      saleId: ORDER_ID,
      customerId: CUSTOMER_ID,
      customerName: "Synthetic Customer",
      amount: 16.0,
      paymentType: "Online",
      paymentStatus: "Pending",
      orderStatus: "awaiting payment",
      source: "development_seed",
      createdAt: now,
    });
    tx.set(db.doc(`stores/${MERCHANT_ID}`), {
      ...common,
      name: "SpazaOne Development Store",
      ownerUid: MERCHANT_ID,
      status: "active",
      legacyUserPath: `users/${MERCHANT_ID}`,
      schemaVersion: 2,
    });
    const membership = {
      ...common,
      storeId: MERCHANT_ID,
      uid: MERCHANT_ID,
      role: "owner",
      status: "active",
      displayName: "SpazaOne Dev Merchant",
      schemaVersion: 2,
    };
    tx.set(
      db.doc(`stores/${MERCHANT_ID}/operators/${MERCHANT_ID}`),
      membership,
    );
    tx.set(db.doc(`operators/${MERCHANT_ID}/stores/${MERCHANT_ID}`), {
      ...membership,
      storeName: "SpazaOne Development Store",
    });
    tx.set(db.doc("paymentConfiguration/global"), {
      capabilities: {},
      emergencySuspended: false,
      schemaVersion: 2,
      synthetic: true,
      developmentSeedRunId: options.runId,
      updatedAt: now,
    });
    tx.create(runRef, {
      ...common,
      runId: options.runId,
      projectId: options.projectId,
      seedVersion: SEED_VERSION,
      status: "applied",
      documents: paths.length,
      createdAt: now,
    });
  });

  console.log(
    JSON.stringify({
      mode: "execute",
      projectId: options.projectId,
      runId: options.runId,
      synthetic: true,
      documents: paths.length,
      deduped,
    }),
  );
}

async function main() {
  await runSeed(validateDevelopmentSeedOptions(process.argv.slice(2)));
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  await main();
}
