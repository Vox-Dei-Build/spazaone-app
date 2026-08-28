import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { beforeEach, test } from "node:test";
import admin from "firebase-admin";
import {
  buildMerchantCatalogDecision,
  catalogRetailerId,
} from "../lib/whatsapp/catalogProjection.js";
import { controlledWhatsAppRecipientDigest } from "../lib/whatsapp/nativeProductList.js";
import { resolveMerchantWhatsAppCatalogProductBotHandler } from "../lib/whatsapp/nativeProductListDelivery.js";
import {
  WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS,
  WHATSAPP_CATALOG_RECONCILIATION_RUN_RETENTION_MS,
  cleanupExpiredWhatsAppCatalogReconciliationRuns,
  runWhatsAppCatalogFullReconciliationPage,
  runWhatsAppCatalogFullReconciliationBotHttp,
  whatsappCatalogReconciliationCleanupEvidenceDigest,
} from "../lib/whatsapp/catalogReconciliation.js";
import {
  currentWhatsAppCatalogDeploymentBinding,
  whatsappCatalogTargetConfigurationDigestSha256,
} from "../lib/whatsapp/catalogProductionTarget.js";
import { reconcileMerchantWhatsAppCatalogCompleteness } from "../lib/whatsapp/catalogCompleteness.js";
import {
  WhatsAppCatalogCartValidationError,
  replaceWhatsAppCatalogCartAtomically,
} from "../lib/ecommerce/replaceWhatsAppCatalogCart.js";
import {
  cancelFailedNativeInventoryReservationAtomically,
  nativeCatalogCheckoutHandler,
} from "../lib/ecommerce/checkoutCart.js";

const projectId = process.env.GCLOUD_PROJECT || "demo-spazaone-native-cart";
if (!admin.apps.length) admin.initializeApp({ projectId });
const db = admin.firestore();
const merchantId = "merchant_a";
const customerId = "customer_1";
const recipientPhone = "+27821234567";
const senderPhoneNumberId = "9876543210";
const catalogId = "1234567890";
const controlledRecipientHashKey = "emulator-only-whatsapp-recipient-key-2026";
const recipientHash = createHash("sha256")
  .update(`emulator-only\u0000${recipientPhone}`)
  .digest("hex");
// Generated per process. It exercises the bot-authenticated checkout branch
// without reading, storing, or passing any real credential.
const emulatorBotProof = randomBytes(32).toString("hex");
process.env.PASELLA_BOT_TOKEN = emulatorBotProof;
Object.assign(process.env, {
  SPAZAONE_ENVIRONMENT: "local",
  WHATSAPP_CATALOG_QUEUE_ENABLED: "true",
  WHATSAPP_CATALOG_SYNC_ENABLED: "true",
  META_CATALOG_PROVIDER_MODE: "stub",
  WHATSAPP_CATALOG_ID: catalogId,
  WHATSAPP_CATALOG_CANARY_MERCHANT_IDS: merchantId,
  WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED: "false",
  WHATSAPP_PRODUCT_LIST_ENABLED: "true",
  META_WHATSAPP_MESSAGE_PROVIDER_MODE: "stub",
  WHATSAPP_SENDER_NUMBER_ID: senderPhoneNumberId,
  WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: merchantId,
  WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED: "false",
  WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES:
    controlledWhatsAppRecipientDigest(
      recipientPhone,
      controlledRecipientHashKey,
    ),
  WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: controlledRecipientHashKey,
});

async function clear() {
  for (const collection of [
    "users",
    "whatsappCatalogMappings",
    "whatsappCatalogOutbox",
    "whatsappCatalogSyncState",
    "whatsappCatalogReconciliationRuns",
    "whatsappCatalogCartReplacements",
    "whatsappCatalogCartStates",
    "merchantCommerceSettings",
    "commerceListings",
  ]) {
    await admin.firestore().recursiveDelete(db.collection(collection));
  }
}

async function withEnvironment(values, run) {
  const previous = new Map();
  for (const [key, value] of Object.entries(values)) {
    previous.set(key, process.env[key]);
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  try {
    return await run();
  } finally {
    for (const [key, value] of previous) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

async function acceptAllSyntheticCatalogJobs() {
  const mappings = await db.collection("whatsappCatalogMappings").get();
  await Promise.all(
    mappings.docs.map((mapping) => {
      const value = mapping.data();
      if (!value.desiredAction || !value.desiredRevision) return undefined;
      return mapping.ref.update({
        status: value.desiredAction === "delete" ? "deleted" : "active",
        metaPolicyStatus:
          value.desiredAction === "delete" ? "removed" : "accepted",
        lastAppliedRevision: value.desiredRevision,
      });
    }),
  );
  const outbox = await db.collection("whatsappCatalogOutbox").get();
  await Promise.all(
    outbox.docs.map((job) => {
      const value = job.data();
      return job.ref.update({
        status: value.desiredAction === "delete" ? "deleted" : "active",
        lastAppliedRevision: value.desiredRevision,
        batchHandle: null,
        processingRevision: null,
        processingAction: null,
      });
    }),
  );
}

async function seed(count = 10) {
  const merchant = {
    name: "Synthetic Merchant",
    buildNumber: 88,
    whatsappOrdering: {
      orderingUrl: "https://shop.example.test/synthetic-merchant",
    },
  };
  await Promise.all([
    db.doc(`users/${merchantId}`).set(merchant),
    db.doc(`users/${merchantId}/customers/${customerId}`).set({
      number: "0821234567",
      name: "Synthetic Buyer",
    }),
  ]);
  const items = [];
  for (let index = 0; index < count; index += 1) {
    const productId = `product_${index + 1}`;
    const sellPriceMinor = 1_000 + index;
    const product = {
      name: `Synthetic Product ${index + 1}`,
      description: `Synthetic product ${index + 1}`,
      sellPriceMinor,
      sellingPrice: 999.99,
      imageUrl: `https://images.example.test/product-${index + 1}.jpg`,
      whatsappListed: true,
      quantity: 50,
    };
    const decision = buildMerchantCatalogDecision({
      merchantId,
      productId,
      product,
      merchant,
    });
    assert.equal(decision.action, "upsert");
    await Promise.all([
      db.doc(`users/${merchantId}/products/${productId}`).set(product),
      db.doc(`whatsappCatalogMappings/${decision.retailerId}`).set({
        status: "active",
        merchantId,
        productId,
        retailerId: decision.retailerId,
        lastAppliedRevision: decision.revision,
      }),
    ]);
    items.push({
      retailerId: decision.retailerId,
      quantity: (index % 3) + 1,
      expectedPriceMinor: sellPriceMinor,
    });
  }
  return { merchant, items };
}

function replacementBody(items, idempotencyKey) {
  return {
    merchantId,
    customerId,
    recipient: recipientPhone,
    senderPhoneNumberId,
    catalogId,
    idempotencyKey,
    items,
  };
}

async function replace(items, idempotencyKey) {
  return replaceWhatsAppCatalogCartAtomically({
    request: replacementBody(items, idempotencyKey),
    recipientHash,
  });
}

async function invokeCheckout(body) {
  let status = 200;
  let responseBody;
  const response = {
    status(code) {
      status = code;
      return this;
    },
    json(value) {
      responseBody = value;
      return this;
    },
    send(value) {
      responseBody = value;
      return this;
    },
  };
  const request = {
    method: "POST",
    body,
    get(name) {
      return name.toLowerCase() === "x-pasella-bot-token"
        ? emulatorBotProof
        : undefined;
    },
  };
  await nativeCatalogCheckoutHandler(request, response);
  return { status, body: responseBody };
}

async function invokeCatalogResolve(body, authenticated = true) {
  let status = 200;
  let responseBody;
  const response = {
    status(code) {
      status = code;
      return this;
    },
    json(value) {
      responseBody = value;
      return this;
    },
  };
  const request = {
    method: "POST",
    path: "/resolveMerchantWhatsAppCatalogProductBotHttp",
    body: {
      merchantId,
      recipientPhone,
      senderPhoneNumberId,
      catalogId,
      ...body,
    },
    get(name) {
      return authenticated && name.toLowerCase() === "x-pasella-bot-token"
        ? emulatorBotProof
        : undefined;
    },
  };
  await resolveMerchantWhatsAppCatalogProductBotHandler(request, response);
  return { status, body: responseBody };
}

async function invokeReconciliationOperator(body, authenticated = true) {
  let status = 200;
  let responseBody;
  const response = {
    status(code) {
      status = code;
      return this;
    },
    json(value) {
      responseBody = value;
      return this;
    },
  };
  const request = {
    method: "POST",
    path: "/runWhatsAppCatalogFullReconciliationBotHttp",
    body,
    get(name) {
      return authenticated && name.toLowerCase() === "x-pasella-bot-token"
        ? emulatorBotProof
        : undefined;
    },
  };
  await runWhatsAppCatalogFullReconciliationBotHttp(request, response);
  return { status, body: responseBody };
}

beforeEach(clear);

const stabilityAppCommit = "c".repeat(40);
const stabilityTargetEnvironment = Object.freeze({
  BUILD_COMMIT: stabilityAppCommit,
  WHATSAPP_CATALOG_MAX_BATCH_SIZE: "10",
  META_GRAPH_API_VERSION: "v25.0",
  WHATSAPP_PRODUCT_LIST_RECIPIENT_COOLDOWN_MS: "7000",
  WHATSAPP_PRODUCT_LIST_MAX_ATTEMPTS: "3",
  WHATSAPP_CATALOG_PAIR_LIMIT_PAUSE_MS: "86400000",
  WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED: "true",
  WHATSAPP_CATALOG_CANARY_MERCHANT_IDS: "",
  WHATSAPP_PRODUCT_LIST_ENABLED: "false",
});

async function completeBoundSyntheticReconciliation() {
  const binding = currentWhatsAppCatalogDeploymentBinding();
  assert.equal(
    binding.targetConfigurationDigestSha256,
    whatsappCatalogTargetConfigurationDigestSha256(),
  );
  let page = await runWhatsAppCatalogFullReconciliationPage({
    pageSize: 200,
    deploymentBinding: binding,
  });
  const cycleId = page.cycleId;
  let safety = 0;
  while (page.outcome !== "complete") {
    safety += 1;
    assert.ok(safety < 30, "bound reconciliation did not stabilize");
    if (page.outcome === "scan_complete") {
      await acceptAllSyntheticCatalogJobs();
    }
    page = await runWhatsAppCatalogFullReconciliationPage({
      cycleId,
      cursorPath: page.nextCursorPath ?? undefined,
      pageSize: 200,
      deploymentBinding: binding,
    });
  }
  assert.match(page.completionDigest, /^[a-f0-9]{64}$/);
  assert.match(page.mutationGenerationDigestSha256, /^[a-f0-9]{64}$/);
  return { binding, page };
}

async function firestoreWriteFingerprint() {
  const entries = [];
  async function visitCollection(collection) {
    const snapshot = await collection.get();
    for (const document of snapshot.docs) {
      entries.push(
        `${document.ref.path}:${document.updateTime.toMillis()}:${document.createTime.toMillis()}`,
      );
      const children = await document.ref.listCollections();
      for (const child of children) await visitCollection(child);
    }
  }
  const roots = await db.listCollections();
  for (const root of roots) await visitCollection(root);
  return entries.sort();
}

function currentStabilityRequest(binding, page) {
  return {
    operation: "inspect_current_stability",
    expectedAppCommit: binding.deployedAppCommit,
    expectedTargetConfigurationDigestSha256:
      binding.targetConfigurationDigestSha256,
    expectedCycleId: page.cycleId,
    expectedCompletionReceiptHashSha256: page.completionDigest,
    expectedMutationGenerationDigestSha256: page.mutationGenerationDigestSha256,
  };
}

async function seedReconciliationCleanupRun(
  cycleId,
  {
    status = "complete",
    phase = status === "complete" ? "complete" : "products",
    completedAtMs = Date.now() -
      WHATSAPP_CATALOG_RECONCILIATION_RUN_RETENTION_MS -
      60_000,
    markerCount = 0,
    includeCompletionTimestamp = true,
  } = {},
) {
  const runRef = db.doc(`whatsappCatalogReconciliationRuns/${cycleId}`);
  await runRef.set({
    cycleId,
    status,
    phase,
    cycleCompletedAtMs: completedAtMs,
    ...(includeCompletionTimestamp
      ? {
          cycleCompletedAt: admin.firestore.Timestamp.fromMillis(completedAtMs),
        }
      : {}),
    schemaVersion: 1,
  });
  await Promise.all(
    Array.from({ length: markerCount }, (_, index) =>
      runRef
        .collection("merchants")
        .doc(`merchant_${index}`)
        .set({
          complete: true,
          eligibleProducts: index + 1,
        }),
    ),
  );
  return runRef;
}

async function seedCurrentReconciliationCycle(cycleId) {
  await db.doc("whatsappCatalogSyncState/fullProductReconciliation").set({
    cycleId,
    status: "complete",
    phase: "complete",
    schemaVersion: 1,
  });
}

test("reconciliation cleanup deletes only old terminal non-current runs and stores aggregate evidence", async () => {
  const activeCycleId = "1".repeat(32);
  const currentCycleId = "2".repeat(32);
  const newTerminalCycleId = "3".repeat(32);
  const expiredTerminalCycleId = "4".repeat(32);
  const ambiguousCycleId = "5".repeat(32);
  await seedCurrentReconciliationCycle(currentCycleId);
  const [active, current, fresh, expired, ambiguous] = await Promise.all([
    seedReconciliationCleanupRun(activeCycleId, {
      status: "running",
      phase: "products",
      markerCount: 1,
    }),
    seedReconciliationCleanupRun(currentCycleId, { markerCount: 1 }),
    seedReconciliationCleanupRun(newTerminalCycleId, {
      completedAtMs: Date.now() - 60_000,
      markerCount: 1,
    }),
    seedReconciliationCleanupRun(expiredTerminalCycleId, { markerCount: 2 }),
    seedReconciliationCleanupRun(ambiguousCycleId, {
      includeCompletionTimestamp: false,
      markerCount: 1,
    }),
  ]);

  const result = await cleanupExpiredWhatsAppCatalogReconciliationRuns({
    maxRunInspections: 10,
    maxRunDeletes: 10,
    maxMerchantMarkerDeletes: 20,
  });
  assert.deepEqual(
    {
      outcome: result.outcome,
      inspectedRuns: result.inspectedRuns,
      deletedRuns: result.deletedRuns,
      deletedMerchantMarkers: result.deletedMerchantMarkers,
      skippedCurrentRuns: result.skippedCurrentRuns,
      skippedIneligibleRuns: result.skippedIneligibleRuns,
      skippedAmbiguousRuns: result.skippedAmbiguousRuns,
    },
    {
      outcome: "complete",
      inspectedRuns: 5,
      deletedRuns: 1,
      deletedMerchantMarkers: 2,
      skippedCurrentRuns: 1,
      skippedIneligibleRuns: 2,
      skippedAmbiguousRuns: 1,
    },
  );
  assert.equal((await active.get()).exists, true);
  assert.equal((await current.get()).exists, true);
  assert.equal((await fresh.get()).exists, true);
  assert.equal((await ambiguous.get()).exists, true);
  assert.equal((await expired.get()).exists, false);
  assert.equal((await active.collection("merchants").get()).size, 1);
  assert.equal((await current.collection("merchants").get()).size, 1);

  const cleanupState = await db
    .doc("whatsappCatalogSyncState/reconciliationRunCleanup")
    .get();
  const aggregate = cleanupState.get("lastCleanupEvidence");
  assert.deepEqual(Object.keys(aggregate).sort(), [
    "deletedMerchantMarkers",
    "deletedRuns",
    "inspectedRuns",
    "outcome",
    "retentionMs",
    "skippedAmbiguousRuns",
    "skippedCurrentRuns",
    "skippedIneligibleRuns",
  ]);
  assert.equal(
    cleanupState.get("lastCleanupEvidenceDigestSha256"),
    whatsappCatalogReconciliationCleanupEvidenceDigest(aggregate),
  );
  assert.equal(cleanupState.get("totalDeletedRuns"), 1);
  assert.equal(cleanupState.get("totalDeletedMerchantMarkers"), 2);
  assert.equal(cleanupState.get("activeCycleId"), null);
  assert.equal(cleanupState.get("cursorCycleId"), null);
  assert.match(result.evidenceDigestSha256, /^[a-f0-9]{64}$/);
});

test("reconciliation cleanup resumes partial marker deletion and honors every work bound", async () => {
  const expiredCycleId = "a".repeat(32);
  await seedCurrentReconciliationCycle("f".repeat(32));
  const expired = await seedReconciliationCleanupRun(expiredCycleId, {
    markerCount: 3,
  });
  const options = {
    maxRunInspections: 1,
    maxRunDeletes: 1,
    maxMerchantMarkerDeletes: 1,
  };

  for (const remaining of [2, 1, 0]) {
    const page = await cleanupExpiredWhatsAppCatalogReconciliationRuns(options);
    assert.equal(page.outcome, "partial");
    assert.equal(page.inspectedRuns, 1);
    assert.equal(page.deletedRuns, 0);
    assert.equal(page.deletedMerchantMarkers, 1);
    assert.equal((await expired.get()).exists, true);
    assert.equal((await expired.collection("merchants").get()).size, remaining);
  }
  const parentPage =
    await cleanupExpiredWhatsAppCatalogReconciliationRuns(options);
  assert.equal(parentPage.outcome, "partial");
  assert.equal(parentPage.deletedRuns, 1);
  assert.equal(parentPage.deletedMerchantMarkers, 0);
  assert.equal((await expired.get()).exists, false);
  const completed =
    await cleanupExpiredWhatsAppCatalogReconciliationRuns(options);
  assert.equal(completed.outcome, "complete");
  assert.equal(completed.deletedRuns, 0);
  const cleanupState = await db
    .doc("whatsappCatalogSyncState/reconciliationRunCleanup")
    .get();
  assert.equal(cleanupState.get("totalDeletedRuns"), 1);
  assert.equal(cleanupState.get("totalDeletedMerchantMarkers"), 3);
});

test("reconciliation cleanup rechecks the current cycle after selection before deleting", async () => {
  const candidateCycleId = "b".repeat(32);
  await seedCurrentReconciliationCycle("f".repeat(32));
  const candidate = await seedReconciliationCleanupRun(candidateCycleId, {
    markerCount: 1,
  });
  let hookCalls = 0;
  const result = await cleanupExpiredWhatsAppCatalogReconciliationRuns(
    {
      maxRunInspections: 10,
      maxRunDeletes: 10,
      maxMerchantMarkerDeletes: 10,
    },
    {
      beforeCandidateRecheck: async (cycleId) => {
        hookCalls += 1;
        await seedCurrentReconciliationCycle(cycleId);
      },
    },
  );
  assert.equal(hookCalls, 1);
  assert.equal(result.deletedRuns, 0);
  assert.equal(result.deletedMerchantMarkers, 0);
  assert.equal(result.skippedCurrentRuns, 1);
  assert.equal((await candidate.get()).exists, true);
  assert.equal((await candidate.collection("merchants").get()).size, 1);
});

test("reconciliation cleanup lease makes overlapping invocations idempotent", async () => {
  const candidateCycleId = "6".repeat(32);
  await seedCurrentReconciliationCycle("f".repeat(32));
  const candidate = await seedReconciliationCleanupRun(candidateCycleId);
  let releaseSelection;
  let selectionObserved;
  const selected = new Promise((resolve) => {
    selectionObserved = resolve;
  });
  const release = new Promise((resolve) => {
    releaseSelection = resolve;
  });
  const first = cleanupExpiredWhatsAppCatalogReconciliationRuns(
    {
      maxRunInspections: 10,
      maxRunDeletes: 10,
      maxMerchantMarkerDeletes: 10,
    },
    {
      beforeCandidateRecheck: async () => {
        selectionObserved();
        await release;
      },
    },
  );
  await selected;
  const overlap = await cleanupExpiredWhatsAppCatalogReconciliationRuns();
  assert.equal(overlap.outcome, "in_progress");
  assert.equal(overlap.inspectedRuns, 0);
  assert.equal(overlap.deletedRuns, 0);
  releaseSelection();
  const completed = await first;
  assert.equal(completed.deletedRuns, 1);
  assert.equal((await candidate.get()).exists, false);
  const cleanupState = await db
    .doc("whatsappCatalogSyncState/reconciliationRunCleanup")
    .get();
  assert.equal(cleanupState.get("totalDeletedRuns"), 1);
});

test("reconciliation cleanup never exceeds the run-deletion limit", async () => {
  await seedCurrentReconciliationCycle("f".repeat(32));
  const runs = await Promise.all(
    ["c", "d", "e"].map((character) =>
      seedReconciliationCleanupRun(character.repeat(32)),
    ),
  );
  const first = await cleanupExpiredWhatsAppCatalogReconciliationRuns({
    maxRunInspections: 2,
    maxRunDeletes: 1,
    maxMerchantMarkerDeletes: 10,
  });
  assert.equal(first.outcome, "partial");
  assert.equal(first.inspectedRuns, 1);
  assert.equal(first.deletedRuns, 1);
  assert.equal(first.deletedMerchantMarkers, 0);
  assert.equal(
    (await Promise.all(runs.map((run) => run.get()))).filter(
      (run) => run.exists,
    ).length,
    2,
  );
});

test("full reconciliation cycle creation has one transactional winner", async () => {
  await withEnvironment(
    {
      WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED: "true",
      WHATSAPP_CATALOG_CANARY_MERCHANT_IDS: "",
      WHATSAPP_PRODUCT_LIST_ENABLED: "false",
    },
    async () => {
      const attempts = await Promise.allSettled([
        runWhatsAppCatalogFullReconciliationPage({ pageSize: 1 }),
        runWhatsAppCatalogFullReconciliationPage({ pageSize: 1 }),
      ]);
      const fulfilled = attempts.filter(
        (attempt) => attempt.status === "fulfilled",
      );
      const rejected = attempts.filter(
        (attempt) => attempt.status === "rejected",
      );
      assert.equal(fulfilled.length, 1);
      assert.equal(rejected.length, 1);
      assert.equal(rejected[0].reason.code, "RECONCILIATION_IN_PROGRESS");

      const state = await db
        .doc("whatsappCatalogSyncState/fullProductReconciliation")
        .get();
      const runs = await db
        .collection("whatsappCatalogReconciliationRuns")
        .get();
      assert.equal(runs.size, 1);
      assert.equal(runs.docs[0].id, state.get("cycleId"));
      assert.equal(state.get("status"), "running");
    },
  );
});

test("full reconciliation resumes across products and mappings, then rechecks after drain", async () => {
  await withEnvironment(
    {
      WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED: "true",
      WHATSAPP_CATALOG_CANARY_MERCHANT_IDS: "",
      WHATSAPP_PRODUCT_LIST_ENABLED: "false",
    },
    async () => {
      const merchantIds = ["merchant_a", "merchant_b"];
      for (const [merchantIndex, currentMerchantId] of merchantIds.entries()) {
        await db.doc(`users/${currentMerchantId}`).set({
          name: `Pre-existing Merchant ${merchantIndex + 1}`,
          buildNumber: 88,
          whatsappOrdering: {
            orderingUrl: `https://shop.example.test/${currentMerchantId}`,
          },
        });
        const count = merchantIndex === 0 ? 3 : 2;
        for (let index = 0; index < count; index += 1) {
          await db
            .doc(`users/${currentMerchantId}/products/preexisting_${index + 1}`)
            .set({
              name: `Pre-existing ${currentMerchantId} ${index + 1}`,
              sellPriceMinor: 2_000 + index,
              imageUrl: `https://images.example.test/${currentMerchantId}-${index + 1}.jpg`,
              whatsappListed: true,
            });
        }
      }
      const staleRetailerId = catalogRetailerId(
        "merchant_c",
        "deleted_product",
      );
      const corruptRetailerId = `spz_${"e".repeat(32)}`;
      const invalidOwnerRetailerId = `spz_${"f".repeat(32)}`;
      await Promise.all([
        db.doc("users/merchant_c").set({
          name: "Mapping-only Merchant",
          buildNumber: 88,
          whatsappOrdering: {
            orderingUrl: "https://shop.example.test/merchant-c",
          },
        }),
        db.doc(`whatsappCatalogMappings/${staleRetailerId}`).set({
          merchantId: "merchant_c",
          productId: "deleted_product",
          retailerId: staleRetailerId,
          status: "active",
          metaPolicyStatus: "accepted",
          lastAppliedRevision: "a".repeat(64),
        }),
        db.doc(`whatsappCatalogMappings/${corruptRetailerId}`).set({
          merchantId: "merchant_d",
          productId: "",
          retailerId: corruptRetailerId,
          status: "active",
          metaPolicyStatus: "accepted",
          lastAppliedRevision: "b".repeat(64),
        }),
        db.doc(`whatsappCatalogMappings/${invalidOwnerRetailerId}`).set({
          merchantId: "",
          productId: "orphan_product",
          retailerId: invalidOwnerRetailerId,
          status: "active",
          metaPolicyStatus: "accepted",
          lastAppliedRevision: "c".repeat(64),
        }),
      ]);

      let page = await runWhatsAppCatalogFullReconciliationPage({
        pageSize: 2,
      });
      const cycleId = page.cycleId;
      assert.equal(page.phase, "products");
      assert.equal(page.inspected, 2);
      await assert.rejects(
        runWhatsAppCatalogFullReconciliationPage({
          cycleId,
          cursorPath: "stale-cursor",
          pageSize: 2,
        }),
        (error) => error.code === "RECONCILIATION_CURSOR_MISMATCH",
      );

      let inspected = page.inspected;
      let sawProductCompletion = false;
      while (page.outcome !== "scan_complete") {
        page = await runWhatsAppCatalogFullReconciliationPage({
          cycleId,
          cursorPath: page.nextCursorPath ?? undefined,
          pageSize: 2,
        });
        inspected += page.inspected;
        sawProductCompletion ||= page.outcome === "product_scan_complete";
      }
      assert.equal(sawProductCompletion, true);
      assert.equal(page.phase, "verify");
      assert.ok(inspected >= 7);
      assert.equal(
        (await db.collection("whatsappCatalogMappings").get()).size,
        8,
      );
      const staleOutbox = await db
        .doc(`whatsappCatalogOutbox/${staleRetailerId}`)
        .get();
      assert.equal(staleOutbox.get("desiredAction"), "delete");
      assert.equal(page.malformedMappings, 2);
      assert.match(page.malformedMappingDigest, /^[a-f0-9]{64}$/);
      assert.notEqual(page.malformedMappingDigest, "0".repeat(64));
      const malformedOwnerMarker = await db
        .doc(
          `whatsappCatalogReconciliationRuns/${cycleId}/merchants/merchant_d`,
        )
        .get();
      assert.equal(malformedOwnerMarker.exists, true);
      assert.equal(malformedOwnerMarker.get("lastSeenScanPass"), 1);

      do {
        page = await runWhatsAppCatalogFullReconciliationPage({
          cycleId,
          cursorPath: page.nextCursorPath ?? undefined,
          pageSize: 2,
        });
      } while (page.outcome === "page");
      assert.equal(page.outcome, "verification_incomplete");
      assert.equal(page.catalogComplete, false);
      assert.ok(page.incompleteMerchants >= 2);
      assert.equal(page.stabilityVerified, false);

      await Promise.all(
        [corruptRetailerId, invalidOwnerRetailerId].map((id) =>
          db.doc(`whatsappCatalogMappings/${id}`).delete(),
        ),
      );
      await acceptAllSyntheticCatalogJobs();

      let safety = 0;
      let insertedBehindCursor = false;
      let mutatedEarlyVerifiedMerchant = false;
      let sawRescanAfterConcurrentChange = false;
      let concurrentChangeScanPass = 0;
      let mutatedAfterStableBarrier = false;
      let stableMutationScanPass = 0;
      let sawRescanAfterStableMutation = false;
      let mutatedOutboxAfterStableBarrier = false;
      let sawVerificationAfterOutboxMutation = false;
      do {
        safety += 1;
        assert.ok(safety < 70, "reconciliation did not stabilize");
        page = await runWhatsAppCatalogFullReconciliationPage({
          cycleId,
          cursorPath: page.nextCursorPath ?? undefined,
          pageSize: 2,
        });
        if (
          !insertedBehindCursor &&
          page.scanPass >= 2 &&
          page.phase === "products" &&
          page.outcome === "page"
        ) {
          insertedBehindCursor = true;
          concurrentChangeScanPass = page.scanPass;
          await Promise.all([
            db.doc("users/aaa_inserted").set({
              name: "Inserted During Scan",
              buildNumber: 88,
              whatsappOrdering: {
                orderingUrl: "https://shop.example.test/aaa-inserted",
              },
            }),
            db.doc("users/aaa_inserted/products/inserted_product").set({
              name: "Inserted Behind Cursor",
              sellPriceMinor: 3_100,
              imageUrl: "https://images.example.test/inserted.jpg",
              whatsappListed: true,
            }),
          ]);
        }
        if (
          !mutatedEarlyVerifiedMerchant &&
          page.scanPass >= 2 &&
          page.phase === "verify" &&
          page.outcome === "page" &&
          page.merchantCompleteness.some(
            (summary) => summary.merchantId === "merchant_a",
          )
        ) {
          mutatedEarlyVerifiedMerchant = true;
          concurrentChangeScanPass = Math.max(
            concurrentChangeScanPass,
            page.scanPass,
          );
          await db
            .doc("users/merchant_a/products/preexisting_1")
            .update({ sellPriceMinor: 2_999 });
        }
        if (page.outcome === "scan_complete") {
          await acceptAllSyntheticCatalogJobs();
        }
        const reconciliationState = await db
          .doc("whatsappCatalogSyncState/fullProductReconciliation")
          .get();
        const stableMutationGeneration = String(
          reconciliationState.get("stableMutationGenerationDigestSha256") ?? "",
        );
        if (
          !mutatedAfterStableBarrier &&
          /^[a-f0-9]{64}$/.test(stableMutationGeneration)
        ) {
          mutatedAfterStableBarrier = true;
          stableMutationScanPass = page.scanPass;
          // This field is deliberately outside the catalogue projection. The
          // server-owned document update time must still invalidate the proof.
          await db
            .doc("users/merchant_a/products/preexisting_1")
            .update({ reconciliationAuditNote: "late-product-mutation" });
        }
        if (
          (insertedBehindCursor || mutatedEarlyVerifiedMerchant) &&
          page.phase === "products" &&
          page.scanPass > concurrentChangeScanPass
        ) {
          sawRescanAfterConcurrentChange = true;
        }
        if (
          mutatedAfterStableBarrier &&
          page.phase === "products" &&
          page.scanPass > stableMutationScanPass
        ) {
          sawRescanAfterStableMutation = true;
        }
        if (
          mutatedOutboxAfterStableBarrier &&
          page.outcome === "verification_incomplete" &&
          page.phase === "verify"
        ) {
          sawVerificationAfterOutboxMutation = true;
        }
        if (
          !mutatedOutboxAfterStableBarrier &&
          mutatedAfterStableBarrier &&
          sawRescanAfterStableMutation &&
          page.outcome === "verification_incomplete" &&
          page.phase === "verify" &&
          page.scanPass > stableMutationScanPass &&
          /^[a-f0-9]{64}$/.test(stableMutationGeneration)
        ) {
          const outbox = await db
            .collection("whatsappCatalogOutbox")
            .limit(1)
            .get();
          assert.equal(outbox.empty, false);
          mutatedOutboxAfterStableBarrier = true;
          // A terminal-row metadata update must force one more stable verify
          // pass even though its terminal status and aggregate counts match.
          await outbox.docs[0].ref.update({
            reconciliationAuditNote: "late-outbox-mutation",
          });
        }
      } while (page.outcome !== "complete");
      assert.equal(insertedBehindCursor, true);
      assert.equal(mutatedEarlyVerifiedMerchant, true);
      assert.equal(sawRescanAfterConcurrentChange, true);
      assert.equal(mutatedAfterStableBarrier, true);
      assert.equal(sawRescanAfterStableMutation, true);
      assert.equal(mutatedOutboxAfterStableBarrier, true);
      assert.equal(sawVerificationAfterOutboxMutation, true);
      assert.equal(page.outcome, "complete");
      assert.equal(page.phase, "complete");
      assert.equal(page.catalogComplete, true);
      assert.equal(page.cycleComplete, true);
      assert.equal(page.completeMerchants, 4);
      assert.equal(page.incompleteMerchants, 0);
      assert.equal(page.malformedMappings, 0);
      assert.equal(page.pendingOutboxJobs, 0);
      assert.equal(page.outboxCountsVerified, true);
      assert.equal(page.outboxStatusCounts?.unknown, 0);
      assert.equal(
        page.totalOutboxDocuments,
        Object.values(page.outboxStatusCounts ?? {}).reduce(
          (sum, count) => sum + count,
          0,
        ),
      );
      assert.ok((page.outboxStatusCounts?.active ?? 0) > 0);
      assert.equal(page.sourceCountsVerified, true);
      assert.equal(page.stabilityVerified, true);
      assert.match(page.completionDigest, /^[a-f0-9]{64}$/);

      const receipt = await db
        .doc(`whatsappCatalogReconciliationRuns/${cycleId}`)
        .get();
      assert.equal(receipt.get("setEqualityVerified"), true);
      assert.equal(receipt.get("eligibleProducts"), 6);
      assert.equal(receipt.get("activeAcceptedProducts"), 6);
      assert.equal(receipt.get("completionDigest"), page.completionDigest);
      assert.equal(receipt.get("outboxDrained"), true);
      assert.equal(receipt.get("outboxCountsVerified"), true);
      assert.equal(receipt.get("outboxStatusCounts.unknown"), 0);
      assert.equal(
        receipt.get("totalOutboxDocuments"),
        page.totalOutboxDocuments,
      );
      assert.equal(receipt.get("sourceCountsVerified"), true);
      assert.equal(receipt.get("stabilityVerified"), true);
      assert.match(
        receipt.get("mutationGenerationDigestSha256"),
        /^[a-f0-9]{64}$/,
      );
      assert.equal(
        page.mutationGenerationDigestSha256,
        receipt.get("mutationGenerationDigestSha256"),
      );

      const duplicate = await runWhatsAppCatalogFullReconciliationPage({
        cycleId,
        pageSize: 2,
      });
      assert.equal(duplicate.outcome, "complete");
      assert.equal(duplicate.completionDigest, page.completionDigest);
    },
  );
});

test("authenticated current-stability inspection is fresh, redacted, and performs zero writes", async () => {
  await withEnvironment(stabilityTargetEnvironment, async () => {
    await seed(2);
    const { binding, page } = await completeBoundSyntheticReconciliation();
    const request = currentStabilityRequest(binding, page);
    const before = await firestoreWriteFingerprint();

    const unauthenticated = await invokeReconciliationOperator(request, false);
    assert.equal(unauthenticated.status, 401);
    assert.equal(unauthenticated.body.code, "AUTHENTICATION_REQUIRED");

    const wrongBinding = await invokeReconciliationOperator({
      ...request,
      expectedAppCommit: "d".repeat(40),
    });
    assert.equal(wrongBinding.status, 409);
    assert.equal(
      wrongBinding.body.code,
      "WHATSAPP_CATALOG_DEPLOYMENT_BINDING_MISMATCH",
    );

    const response = await invokeReconciliationOperator(request);
    const after = await firestoreWriteFingerprint();
    assert.equal(response.status, 200, JSON.stringify(response.body));
    assert.equal(response.body.outcome, "current_stability");
    assert.equal(response.body.cycleId, page.cycleId);
    assert.equal(
      response.body.completionReceiptHashSha256,
      page.completionDigest,
    );
    assert.equal(
      response.body.mutationGenerationDigestSha256,
      page.mutationGenerationDigestSha256,
    );
    assert.ok(response.body.readAtMs >= response.body.cycleCompletedAtMs);
    assert.equal(response.body.pendingOutboxJobs, 0);
    assert.equal(response.body.nonterminalOutboxDocuments, 0);
    assert.equal(
      response.body.terminalOutboxDocuments,
      response.body.totalOutboxDocuments,
    );
    assert.deepEqual(after, before);
    assert.doesNotMatch(
      JSON.stringify(response.body),
      /merchant_a|customer_1|product_1|recipientPhone|users\//i,
    );
  });
});

test("current-stability proof fails closed after a live product change", async () => {
  await withEnvironment(stabilityTargetEnvironment, async () => {
    await seed(2);
    const { binding, page } = await completeBoundSyntheticReconciliation();
    await db.doc(`users/${merchantId}/products/product_1`).update({
      reconciliationAuditNote: "changed-after-completion",
    });
    const response = await invokeReconciliationOperator(
      currentStabilityRequest(binding, page),
    );
    assert.equal(response.status, 409);
    assert.equal(response.body.code, "RECONCILIATION_CURRENT_STABILITY_STALE");
  });
});

test("current-stability proof fails closed after a live mapping change", async () => {
  await withEnvironment(stabilityTargetEnvironment, async () => {
    const { items } = await seed(2);
    const { binding, page } = await completeBoundSyntheticReconciliation();
    await db.doc(`whatsappCatalogMappings/${items[0].retailerId}`).update({
      reconciliationAuditNote: "changed-after-completion",
    });
    const response = await invokeReconciliationOperator(
      currentStabilityRequest(binding, page),
    );
    assert.equal(response.status, 409);
    assert.equal(response.body.code, "RECONCILIATION_CURRENT_STABILITY_STALE");
  });
});

test("current-stability proof fails closed after terminal or nonterminal outbox changes", async () => {
  await withEnvironment(stabilityTargetEnvironment, async () => {
    await seed(2);
    const { binding, page } = await completeBoundSyntheticReconciliation();
    const outbox = await db.collection("whatsappCatalogOutbox").limit(1).get();
    assert.equal(outbox.empty, false);
    await outbox.docs[0].ref.update({
      reconciliationAuditNote: "changed-after-completion",
    });
    let response = await invokeReconciliationOperator(
      currentStabilityRequest(binding, page),
    );
    assert.equal(response.status, 409);
    assert.equal(response.body.code, "RECONCILIATION_CURRENT_STABILITY_STALE");

    await outbox.docs[0].ref.update({ status: "pending" });
    response = await invokeReconciliationOperator(
      currentStabilityRequest(binding, page),
    );
    assert.equal(response.status, 409);
    assert.equal(response.body.code, "RECONCILIATION_CURRENT_STABILITY_STALE");
  });
});

test("current-stability proof rejects a current-cycle swap", async () => {
  await withEnvironment(stabilityTargetEnvironment, async () => {
    await seed(1);
    const { binding, page } = await completeBoundSyntheticReconciliation();
    await db.doc("whatsappCatalogSyncState/fullProductReconciliation").update({
      cycleId: "f".repeat(32),
    });
    const response = await invokeReconciliationOperator(
      currentStabilityRequest(binding, page),
    );
    assert.equal(response.status, 409);
    assert.equal(response.body.code, "RECONCILIATION_CURRENT_STABILITY_STALE");
  });
});

test("current-stability proof rejects missing completion timestamp evidence without writing", async () => {
  await withEnvironment(stabilityTargetEnvironment, async () => {
    await seed(1);
    const { binding, page } = await completeBoundSyntheticReconciliation();
    await db
      .doc(`whatsappCatalogReconciliationRuns/${page.cycleId}`)
      .update({ cycleCompletedAt: admin.firestore.FieldValue.delete() });
    const before = await firestoreWriteFingerprint();
    const response = await invokeReconciliationOperator(
      currentStabilityRequest(binding, page),
    );
    const after = await firestoreWriteFingerprint();
    assert.equal(response.status, 409);
    assert.equal(
      response.body.code,
      "RECONCILIATION_CURRENT_STABILITY_NOT_AVAILABLE",
    );
    assert.deepEqual(after, before);
  });
});

test("current-stability proof rejects future-skewed completion timestamps without writing", async () => {
  await withEnvironment(stabilityTargetEnvironment, async () => {
    await seed(1);
    const { binding, page } = await completeBoundSyntheticReconciliation();
    const futureCompletedAtMs =
      Date.now() + WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS + 60_000;
    const futureCompletedAt =
      admin.firestore.Timestamp.fromMillis(futureCompletedAtMs);
    const batch = db.batch();
    for (const path of [
      "whatsappCatalogSyncState/fullProductReconciliation",
      `whatsappCatalogReconciliationRuns/${page.cycleId}`,
    ]) {
      batch.update(db.doc(path), {
        cycleCompletedAtMs: futureCompletedAtMs,
        cycleCompletedAt: futureCompletedAt,
      });
    }
    await batch.commit();
    const before = await firestoreWriteFingerprint();
    const response = await invokeReconciliationOperator(
      currentStabilityRequest(binding, page),
    );
    const after = await firestoreWriteFingerprint();
    assert.equal(response.status, 409);
    assert.equal(
      response.body.code,
      "RECONCILIATION_CURRENT_STABILITY_NOT_AVAILABLE",
    );
    assert.deepEqual(after, before);
  });
});

test("current-stability proof reads at most the evidence limit plus one sentinel", async () => {
  await withEnvironment(stabilityTargetEnvironment, async () => {
    await seed(1);
    const { binding, page } = await completeBoundSyntheticReconciliation();
    const bulkWriter = db.bulkWriter();
    for (let index = 0; index < 5_000; index += 1) {
      bulkWriter.set(
        db.doc(
          `users/evidence_limit/products/product_${String(index).padStart(5, "0")}`,
        ),
        { whatsappListed: true },
      );
    }
    await bulkWriter.close();

    const response = await invokeReconciliationOperator(
      currentStabilityRequest(binding, page),
    );
    assert.equal(response.status, 409);
    assert.equal(response.body.code, "RECONCILIATION_EVIDENCE_LIMIT_EXCEEDED");
  });
});

test("authenticated native resolve serializes the exact ordinary product contract", async () => {
  const { items } = await seed(1);
  const response = await invokeCatalogResolve({
    retailerId: items[0].retailerId,
  });

  assert.equal(response.status, 200);
  assert.deepEqual(response.body, {
    outcome: "found",
    product: {
      id: "product_1",
      retailerId: items[0].retailerId,
      name: "Synthetic Product 1",
      description: "Synthetic product 1",
      imageUrl: "https://images.example.test/product-1.jpg",
      price: 10,
      priceMinor: 1_000,
      currency: "ZAR",
      availability: "in stock",
      isDropshipListing: false,
    },
  });
});

test("authenticated native resolve exposes only a bound supplier listing ID", async () => {
  const { merchant, items } = await seed(1);
  const listingId = "supplier_listing_1";
  const productRef = db.doc(`users/${merchantId}/products/product_1`);
  const product = {
    ...(await productRef.get()).data(),
    isDropshipListing: true,
    commerceListingId: listingId,
    supplierSku: "must-not-cross-wire-boundary",
    supplierProductCostMinor: 123,
  };
  const decision = buildMerchantCatalogDecision({
    merchantId,
    productId: "product_1",
    product,
    merchant,
  });
  assert.equal(decision.action, "upsert");
  await Promise.all([
    productRef.set(product),
    db.doc(`whatsappCatalogMappings/${items[0].retailerId}`).update({
      lastAppliedRevision: decision.revision,
    }),
    db.doc(`commerceListings/${listingId}`).set({
      active: true,
      supplierId: "cj_dropshipping",
      sellerId: merchantId,
      sellerProductId: "product_1",
      sellPriceMinor: 1_000,
      supplierProductCostMinor: 123,
      supplierSku: "must-not-cross-wire-boundary",
    }),
  ]);

  const response = await invokeCatalogResolve({
    retailerId: items[0].retailerId,
  });
  assert.equal(response.status, 200);
  assert.deepEqual(response.body, {
    outcome: "found",
    product: {
      id: "product_1",
      retailerId: items[0].retailerId,
      name: "Synthetic Product 1",
      description: "Synthetic product 1",
      imageUrl: "https://images.example.test/product-1.jpg",
      price: 10,
      priceMinor: 1_000,
      currency: "ZAR",
      availability: "in stock",
      isDropshipListing: true,
      commerceListingId: listingId,
    },
  });
  assert.equal(JSON.stringify(response.body).includes("supplierSku"), false);
  assert.equal("supplierProductCostMinor" in response.body.product, false);

  await db.doc(`users/${merchantId}`).update({ buildNumber: 87 });
  const disabled = await invokeCatalogResolve({
    retailerId: items[0].retailerId,
  });
  assert.equal(disabled.status, 200);
  assert.deepEqual(disabled.body, {
    outcome: "unavailable",
    reason: "merchant_update_required",
  });
});

test("authenticated native resolve rejects a foreign mapping without leakage", async () => {
  const foreignMerchantId = "merchant_b";
  const foreignProductId = "private_product";
  const foreignMerchant = {
    name: "Foreign Merchant",
    whatsappOrdering: {
      orderingUrl: "https://shop.example.test/foreign-merchant",
    },
  };
  const foreignProduct = {
    name: "Must Not Leak",
    description: "foreign-private-description",
    sellPriceMinor: 7_777,
    imageUrl: "https://images.example.test/foreign-private.jpg",
    whatsappListed: true,
  };
  const decision = buildMerchantCatalogDecision({
    merchantId: foreignMerchantId,
    productId: foreignProductId,
    product: foreignProduct,
    merchant: foreignMerchant,
  });
  assert.equal(decision.action, "upsert");
  await Promise.all([
    db.doc(`users/${foreignMerchantId}`).set(foreignMerchant),
    db
      .doc(`users/${foreignMerchantId}/products/${foreignProductId}`)
      .set(foreignProduct),
    db.doc(`whatsappCatalogMappings/${decision.retailerId}`).set({
      status: "active",
      merchantId: foreignMerchantId,
      productId: foreignProductId,
      retailerId: decision.retailerId,
      lastAppliedRevision: decision.revision,
    }),
  ]);

  const response = await invokeCatalogResolve({
    retailerId: decision.retailerId,
  });
  assert.equal(response.status, 200);
  assert.deepEqual(response.body, {
    outcome: "unavailable",
    reason: "merchant_mismatch",
  });
  assert.equal(JSON.stringify(response.body).includes("Must Not Leak"), false);
  assert.equal(
    JSON.stringify(response.body).includes("foreign-private-description"),
    false,
  );
});

test("an unrelated pending product does not block exact-item resolve, replace, or checkout", async () => {
  const { items } = await seed(2);
  await Promise.all([
    db.doc(`whatsappCatalogMappings/${items[0].retailerId}`).update({
      metaPolicyStatus: "accepted",
    }),
    db.doc(`whatsappCatalogMappings/${items[1].retailerId}`).update({
      status: "pending",
      metaPolicyStatus: null,
    }),
  ]);
  const readiness =
    await reconcileMerchantWhatsAppCatalogCompleteness(merchantId);
  assert.equal(readiness.complete, false);
  assert.equal(readiness.activeAcceptedProducts, 1);
  assert.equal(readiness.missingProducts, 1);

  const resolved = await invokeCatalogResolve({
    retailerId: items[0].retailerId,
  });
  assert.equal(resolved.status, 200);
  assert.equal(resolved.body.outcome, "found");
  assert.equal(resolved.body.product.retailerId, items[0].retailerId);

  const idempotencyKey = "native-cart:unrelated-pending";
  const replaced = await replace([items[0]], idempotencyKey);
  assert.equal(replaced.outcome, "replaced");
  assert.equal(replaced.cart.lineCount, 1);
  const checkout = await invokeCheckout({
    merchantId,
    customerId,
    paymentType: "Cash",
    fulfillmentType: "pickup",
    idempotencyKey,
    nativeCartFingerprint: replaced.cart.nativeCartFingerprint,
  });
  assert.equal(checkout.status, 200);
  assert.equal(checkout.body.success, true);
});

test("ten-line replacement is idempotent and checks out at canonical prices", async () => {
  const { items } = await seed();
  const first = await replace(items, "native-cart:integration-1");
  assert.equal(first.outcome, "replaced");
  assert.equal(first.cart.lineCount, 10);
  assert.match(first.cart.nativeCartFingerprint, /^[a-f0-9]{64}$/);

  const duplicate = await replace(
    [...items].reverse(),
    "native-cart:integration-1",
  );
  assert.equal(duplicate.outcome, "duplicate");
  assert.equal(
    duplicate.cart.nativeCartFingerprint,
    first.cart.nativeCartFingerprint,
  );

  const checkout = await invokeCheckout({
    merchantId,
    customerId,
    paymentType: "Cash",
    fulfillmentType: "pickup",
    idempotencyKey: "native-cart:integration-1",
    nativeCartFingerprint: first.cart.nativeCartFingerprint,
  });
  assert.equal(checkout.status, 200);
  assert.equal(checkout.body.success, true);
  const sale = await db
    .doc(`users/${merchantId}/sales/${checkout.body.saleId}`)
    .get();
  assert.equal(sale.get("cartSource"), "whatsapp_native_catalog");
  assert.equal(
    sale.get("nativeCartFingerprint"),
    first.cart.nativeCartFingerprint,
  );
  assert.equal(sale.get("subtotalMinor"), first.cart.totalMinor);
  assert.equal(sale.get("items").length, 10);
  assert.equal(sale.get("items")[0].priceMinor, 1_000);
});

test("late tenth-item failure leaves every existing cart document unchanged", async () => {
  const { items } = await seed();
  const initial = await replace(items, "native-cart:integration-before");
  assert.equal(initial.outcome, "replaced");
  const cartRef = db.doc(`users/${merchantId}/carts/${customerId}`);
  const beforeSummary = (await cartRef.get()).data();
  const beforeItems = (await cartRef.collection("items").get()).docs.map(
    (document) => ({ id: document.id, data: document.data() }),
  );

  await db.doc(`users/${merchantId}/products/product_10`).update({
    sellPriceMinor: items[9].expectedPriceMinor + 100,
  });
  await assert.rejects(
    replace(items, "native-cart:integration-late-failure"),
    (error) =>
      error instanceof WhatsAppCatalogCartValidationError &&
      error.reason === "price_changed" &&
      error.failedItemIndex === 9,
  );

  const afterSummary = (await cartRef.get()).data();
  const afterItems = (await cartRef.collection("items").get()).docs.map(
    (document) => ({ id: document.id, data: document.data() }),
  );
  assert.equal(
    afterSummary.nativeCartFingerprint,
    beforeSummary.nativeCartFingerprint,
  );
  assert.deepEqual(
    afterItems.map(({ id, data }) => [id, data.quantity, data.catalogRevision]),
    beforeItems.map(({ id, data }) => [
      id,
      data.quantity,
      data.catalogRevision,
    ]),
  );
});

test("checkout rejects a cart mutation before creating a sale or lock", async () => {
  const { items } = await seed();
  const replaced = await replace(items, "native-cart:integration-guard");
  assert.equal(replaced.outcome, "replaced");
  await db
    .doc(`users/${merchantId}/carts/${customerId}/items/product_10`)
    .update({ quantity: 49 });

  const checkout = await invokeCheckout({
    merchantId,
    customerId,
    paymentType: "Cash",
    fulfillmentType: "pickup",
    idempotencyKey: "native-cart:integration-guard",
    nativeCartFingerprint: replaced.cart.nativeCartFingerprint,
  });
  assert.equal(checkout.status, 409);
  assert.equal(checkout.body.code, "NATIVE_CATALOG_CART_CHANGED");
  assert.equal(
    (await db.collection(`users/${merchantId}/sales`).get()).size,
    0,
  );
  assert.equal(
    (await db.doc(`users/${merchantId}/carts/${customerId}`).get()).get("lock"),
    undefined,
  );
});

test("concurrent native checkouts with distinct keys create exactly one sale", async () => {
  const { items } = await seed();
  const replaced = await replace(items, "native-cart:integration-race");
  assert.equal(replaced.outcome, "replaced");
  const request = (idempotencyKey) => ({
    merchantId,
    customerId,
    paymentType: "Cash",
    fulfillmentType: "pickup",
    idempotencyKey,
    nativeCartFingerprint: replaced.cart.nativeCartFingerprint,
  });

  const responses = await Promise.all([
    invokeCheckout(request("native-cart:integration-race-a")),
    invokeCheckout(request("native-cart:integration-race-b")),
  ]);
  assert.deepEqual(
    responses.map((response) => response.status).sort(),
    [200, 409],
  );
  assert.equal(
    responses.find((response) => response.status === 409).body.code,
    "NATIVE_CATALOG_CART_CHANGED",
  );
  assert.equal(
    (await db.collection(`users/${merchantId}/sales`).get()).size,
    1,
  );
});

test("a locked native checkout cannot be replaced by a later catalogue cart", async () => {
  const { items } = await seed();
  const first = await replace(items, "native-cart:integration-locked");
  assert.equal(first.outcome, "replaced");
  const checkout = await invokeCheckout({
    merchantId,
    customerId,
    paymentType: "Cash",
    fulfillmentType: "pickup",
    idempotencyKey: "native-cart:integration-locked",
    nativeCartFingerprint: first.cart.nativeCartFingerprint,
  });
  assert.equal(checkout.status, 200);

  await assert.rejects(
    replace(
      items.map((item, index) => ({
        ...item,
        quantity: index === 0 ? item.quantity + 1 : item.quantity,
      })),
      "native-cart:integration-locked-replace",
    ),
    (error) =>
      error instanceof WhatsAppCatalogCartValidationError &&
      error.reason === "cart_changed",
  );
  const cart = await db.doc(`users/${merchantId}/carts/${customerId}`).get();
  assert.equal(cart.get("lock").saleId, checkout.body.saleId);
  assert.equal(
    cart.get("nativeCartFingerprint"),
    first.cart.nativeCartFingerprint,
  );
});

test("native checkout rejects an idempotency receipt bound to another cart", async () => {
  const { items } = await seed(1);
  const replaced = await replace(items, "native-cart:integration-conflict");
  assert.equal(replaced.outcome, "replaced");
  await db
    .doc(
      `users/${merchantId}/checkoutIdempotency/${encodeURIComponent("native-cart:integration-conflict")}`,
    )
    .set({
      customerId: "another_customer",
      cartSig: "f".repeat(64),
      saleId: "another_sale",
    });

  const checkout = await invokeCheckout({
    merchantId,
    customerId,
    paymentType: "Cash",
    fulfillmentType: "pickup",
    idempotencyKey: "native-cart:integration-conflict",
    nativeCartFingerprint: replaced.cart.nativeCartFingerprint,
  });
  assert.equal(checkout.status, 409);
  assert.equal(checkout.body.code, "IDEMPOTENCY_CONFLICT");
  assert.equal(
    (await db.collection(`users/${merchantId}/sales`).get()).size,
    0,
  );
});

test("failed native inventory reservation cancels sale and releases receipt and lock atomically", async () => {
  const { items } = await seed(1);
  const idempotencyKey = "native-cart:integration-reservation-failure";
  const replaced = await replace(items, idempotencyKey);
  assert.equal(replaced.outcome, "replaced");
  const checkout = await invokeCheckout({
    merchantId,
    customerId,
    paymentType: "Cash",
    fulfillmentType: "pickup",
    idempotencyKey,
    nativeCartFingerprint: replaced.cart.nativeCartFingerprint,
  });
  assert.equal(checkout.status, 200);
  const saleRef = db.doc(`users/${merchantId}/sales/${checkout.body.saleId}`);
  const receiptRef = db.doc(
    `users/${merchantId}/checkoutIdempotency/${encodeURIComponent(idempotencyKey)}`,
  );
  const cartRef = db.doc(`users/${merchantId}/carts/${customerId}`);

  await cancelFailedNativeInventoryReservationAtomically({
    saleRef,
    idempotencyRef: receiptRef,
    cartRef,
    saleId: checkout.body.saleId,
    reason: "INVENTORY_PRICE_CHANGED",
  });

  assert.equal((await saleRef.get()).get("status"), "cancelled");
  assert.equal((await receiptRef.get()).exists, false);
  assert.equal((await cartRef.get()).get("lock"), undefined);
});
