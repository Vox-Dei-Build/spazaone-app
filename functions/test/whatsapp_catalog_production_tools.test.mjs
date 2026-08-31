import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { EventEmitter } from "node:events";
import {
  access,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";

import * as deploymentGuardModule from "../scripts/guard-whatsapp-catalog-functions-deploy.mjs";
import * as reconciliationRunnerModule from "../scripts/run-whatsapp-catalog-full-reconciliation.mjs";

import {
  FROZEN_APP_MAIN_COMMIT,
  PRODUCTION_FIREBASE_ACCOUNT,
  PRODUCTION_FIREBASE_PROJECT_ID,
  PRODUCTION_NATIVE_CATALOG_TARGET,
  RECONCILIATION_FUNCTION_URL,
  ReconciliationOperatorError,
  parseRunnerArguments,
  resolveAuthorityAppCommit,
  resolvePasellaBotToken,
} from "../scripts/run-whatsapp-catalog-full-reconciliation.mjs";
import { PRODUCTION_FIREBASE_PROJECT_NUMBER } from "../scripts/whatsapp-catalog-production-target.mjs";
import {
  CATALOG_POLICY_LANES,
  IMMUTABLE_TARGET_CONFIGURATION,
  NATIVE_CATALOG_DELIVERY_FUNCTIONS,
  NATIVE_CATALOG_EXISTING_FUNCTION_SECRET_REFS,
  NATIVE_CATALOG_EXISTING_FUNCTIONS,
  NATIVE_CATALOG_FUNCTION_SECRET_REFS,
  NATIVE_CATALOG_NEW_FUNCTIONS,
  NATIVE_CATALOG_SYNC_FUNCTIONS,
  PRODUCTION_FIRESTORE_DATABASE_ID,
  REQUIRED_CATALOG_TTL_FIELDS,
  assertNoSourceDeploymentDotenv,
  assertFirebaseCliEnvironmentPreservationSource,
  buildEphemeralFirebaseConfig,
  canonicalFunctionBuildIdentityDigest,
  catalogPolicySourceContract,
  catalogFunctionSelector,
  collectCatalogFunctionReadback,
  collectCatalogPolicyReadback,
  codexGuardDeployArguments,
  nativeCatalogTargetConfigurationDigestSha256,
  parseDeploymentGuardArguments,
  parseStrictDotenv,
  validateCatalogDeploymentDotenv,
  verifyExistingCodeEnvironmentBaseline,
  verifyExistingCodeEnvironmentTransition,
} from "../scripts/guard-whatsapp-catalog-functions-deploy.mjs";
import { firebaseEndpointHashSha1 } from "../scripts/firebase-function-source-binding.mjs";
import {
  assertWhatsAppCatalogDeploymentBinding,
  immutableWhatsAppCatalogTargetConfiguration,
} from "../lib/whatsapp/catalogProductionTarget.js";
import {
  WHATSAPP_CATALOG_MAX_GENERATION_DOCUMENTS,
  WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS,
  assertWhatsAppCatalogMutationEvidenceWithinLimit,
  continueBoundWhatsAppCatalogFullReconciliationPage,
  inspectBoundWhatsAppCatalogCurrentStability,
  inspectBoundWhatsAppCatalogReconciliationRecovery,
  runWhatsAppCatalogFullReconciliationBotHttp,
  runBoundWhatsAppCatalogFullReconciliationPage,
  summarizeWhatsAppCatalogOutboxEvidence,
  whatsappCatalogMutationGenerationDigest,
} from "../lib/whatsapp/catalogReconciliation.js";

const commit = "c".repeat(40);
const runGuardedCatalogDeployment =
  deploymentGuardModule.runGuardedCatalogDeployment;
const runGuardedCatalogPolicyDeployment =
  deploymentGuardModule.runGuardedCatalogPolicyDeployment;
const executorPath = path.resolve(
  "scripts/execute-whatsapp-catalog-production.mjs",
);

async function withPrivateReconciliationTransport(callback) {
  const root = await mkdtemp(
    path.join(os.tmpdir(), "private-reconciliation-transport-"),
  );
  const harnessPath = path.join(root, "executor-transport-harness.mjs");
  try {
    const scriptsRoot = path.dirname(executorPath);
    const source = (await readFile(executorPath, "utf8")).replace(
      /from "(\.\/[^"\n]+)"/g,
      (_, specifier) =>
        `from ${JSON.stringify(
          pathToFileURL(path.resolve(scriptsRoot, specifier)).href,
        )}`,
    );
    await writeFile(
      harnessPath,
      `${source}\nexport { runPrivateFullCatalogReconciliation };\n`,
      { flag: "wx", mode: 0o600 },
    );
    const harness = await import(pathToFileURL(harnessPath).href);
    return await callback(harness.runPrivateFullCatalogReconciliation);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

test("legacy production CLIs stay disabled while the high-level executor owns dispatch", async () => {
  assert.equal(
    reconciliationRunnerModule.runFullCatalogReconciliation,
    undefined,
  );
  assert.equal(
    reconciliationRunnerModule.finalizeRedactedReconciliationReceipt,
    undefined,
  );
  assert.equal(runGuardedCatalogDeployment, undefined);
  assert.equal(runGuardedCatalogPolicyDeployment, undefined);
});

function reconciliationClientOptions(overrides = {}) {
  return {
    ...reconciliationExecution,
    expectedAppCommit: commit,
    pageSize: 200,
    pollMs: 1,
    maxSteps: 10,
    maxElapsedMs: 60_000,
    requestTimeoutMs: 10_000,
    resolveSecret: async () => Buffer.from("test-bot-secret-value", "utf8"),
    resolveCommit: async () => commit,
    sleep: async () => {},
    clock: () => new Date(),
    ...overrides,
  };
}

function completedReconciliationPage() {
  return page({
    outcome: "complete",
    phase: "complete",
    continuationStateDigestSha256: "",
    cycleComplete: true,
    catalogComplete: true,
    stabilityVerified: true,
    sourceCountsVerified: true,
    mutationGenerationDigestSha256: mutationGenerationDigest,
    completionDigest,
  });
}

test("reconciliation transport calls its one-shot dispatch hook once and never blindly retries ambiguity", async () => {
  await withPrivateReconciliationTransport(async (runReconciliation) => {
    let dispatchCalls = 0;
    let requestCalls = 0;
    const responses = [
      page({ outcome: "product_scan_complete", phase: "mappings" }),
      page({ outcome: "scan_complete", phase: "verify" }),
      completedReconciliationPage(),
    ];
    const artifact = await runReconciliation(
      reconciliationClientOptions({
        fetchImpl: async () => {
          requestCalls += 1;
          return jsonResponse(responses.shift());
        },
        onBeforeFirstWrite: async () => {
          dispatchCalls += 1;
        },
      }),
    );
    assert.equal(dispatchCalls, 1);
    assert.equal(requestCalls, 3);
    assert.equal(artifact.kind, "spazaone_catalog_full_reconciliation");
    assert.equal(artifact.redactedReceiptSha256.length, 64);

    dispatchCalls = 0;
    requestCalls = 0;
    await assert.rejects(
      runReconciliation(
        reconciliationClientOptions({
          fetchImpl: async () => {
            requestCalls += 1;
            if (requestCalls === 1) {
              return jsonResponse(
                page({ outcome: "product_scan_complete", phase: "mappings" }),
              );
            }
            throw new Error("lost response");
          },
          onBeforeFirstWrite: async () => {
            dispatchCalls += 1;
          },
        }),
      ),
      (error) =>
        error.code === "RECONCILIATION_HTTP_AMBIGUOUS" &&
        error.needsReview === true,
    );
    assert.equal(dispatchCalls, 1);
    assert.equal(requestCalls, 2);
  });
});

test("reviewed reconciliation is inspection-only until exact continuation facts are authorized", async () => {
  await withPrivateReconciliationTransport(async (runReconciliation) => {
    let requestBody;
    const recovery = await runReconciliation(
      reconciliationClientOptions({
        reviewedResume: true,
        fetchImpl: async (_url, init) => {
          requestBody = JSON.parse(init.body);
          return jsonResponse({
            outcome: "recovery_state",
            phase: "mappings",
            cycleId,
            acknowledgedPages: 2,
            productScanComplete: true,
            mappingScanComplete: false,
            continuationStateDigestSha256: continuationDigest,
            deployedAppCommit: commit,
            targetConfigurationDigestSha256: targetDigest,
            firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
            catalogId: PRODUCTION_NATIVE_CATALOG_TARGET.catalogId,
            senderPhoneNumberId:
              PRODUCTION_NATIVE_CATALOG_TARGET.senderPhoneNumberId,
          });
        },
      }),
    );
    assert.equal(requestBody.operation, "inspect_recovery");
    assert.deepEqual(recovery, {
      outcome: "continuation_authorization_required",
      cycleId,
      continuationStateDigestSha256: continuationDigest,
      acknowledgedPages: 2,
      productScanComplete: true,
      mappingScanComplete: false,
    });

    let dispatchCalls = 0;
    const bodies = [];
    const responses = [
      page({ outcome: "scan_complete", phase: "verify" }),
      completedReconciliationPage(),
    ];
    const artifact = await runReconciliation(
      reconciliationClientOptions({
        reviewedResume: true,
        continuationState: {
          cycleId,
          continuationStateDigestSha256: continuationDigest,
          acknowledgedPages: 2,
          productScanComplete: true,
          mappingScanComplete: false,
        },
        fetchImpl: async (_url, init) => {
          bodies.push(JSON.parse(init.body));
          return jsonResponse(responses.shift());
        },
        onBeforeFirstWrite: async () => {
          dispatchCalls += 1;
        },
      }),
    );
    assert.equal(dispatchCalls, 1);
    assert.equal(bodies[0].operation, "continue");
    assert.equal(
      bodies[0].expectedContinuationStateDigestSha256,
      continuationDigest,
    );
    assert.equal(artifact.kind, "spazaone_catalog_full_reconciliation");
  });
});

const candidateManifestPath = "/tmp/spazaone-reviewed-candidate.json";
const candidateManifestSha256 = "d".repeat(64);
const reconciliationExecution = Object.freeze({
  execute: true,
  expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
  candidateManifestPath,
  expectedCandidateManifestSha256: candidateManifestSha256,
  verifyToolchain: async () => ({}),
  verifyCandidateManifest: async () => ({ appCommit: commit }),
});
const guardedTooling = Object.freeze({
  expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
  candidateManifestPath,
  expectedCandidateManifestSha256: candidateManifestSha256,
  verifyToolchain: async () => ({}),
  verifyCandidateManifest: async () => ({ appCommit: commit }),
});
const targetDigest = nativeCatalogTargetConfigurationDigestSha256();
const productionBinding = Object.freeze({
  deployedAppCommit: commit,
  targetConfigurationDigestSha256: targetDigest,
  firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
  catalogId: "9415654481779933",
  senderPhoneNumberId: "343481258858230",
});
const cycleId = "a".repeat(32);
const completionDigest = "b".repeat(64);
const mutationGenerationDigest = "a".repeat(64);
const continuationDigest = "9".repeat(64);
const cycleStartedAt = new Date(Date.now() - 2_000).toISOString();
const cycleCompletedAt = new Date(Date.now() - 1_000).toISOString();

function page(overrides) {
  return {
    outcome: "page",
    phase: "products",
    cycleId,
    inspected: 1,
    queued: 0,
    merchantCompleteness: [{ merchantId: "merchant-must-never-escape" }],
    nextCursorPath: "users/merchant-must-never-escape/products/product",
    cycleComplete: false,
    catalogComplete: false,
    completeMerchants: 0,
    incompleteMerchants: 0,
    verificationPass: 0,
    scanPass: 1,
    malformedMappings: 0,
    pendingOutboxJobs: 0,
    totalOutboxDocuments: 0,
    outboxCountsVerified: true,
    outboxStatusCounts: {
      pending: 0,
      retry: 0,
      processing: 0,
      submitted: 0,
      active: 0,
      deleted: 0,
      rejected: 0,
      unknown: 0,
    },
    stabilityVerified: false,
    sourceDigest: "e".repeat(64),
    sourceCountsVerified: false,
    malformedMappingDigest: "f".repeat(64),
    deployedAppCommit: commit,
    targetConfigurationDigestSha256: targetDigest,
    firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
    catalogId: "9415654481779933",
    senderPhoneNumberId: "343481258858230",
    continuationStateDigestSha256: continuationDigest,
    cycleStartedAt,
    cycleCompletedAt,
    ...overrides,
  };
}

function jsonResponse(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function validDotenv(lane, appCommit = commit) {
  const sync = new Set([
    "sync-enable",
    "controlled-delivery-enable",
    "all-eligible-delivery-enable",
    "delivery-disable",
  ]).has(lane);
  const delivery = new Set([
    "controlled-delivery-enable",
    "all-eligible-delivery-enable",
  ]).has(lane);
  const controlled = lane === "controlled-delivery-enable";
  const fullDelivery = lane === "all-eligible-delivery-enable";
  return [
    "SPAZAONE_ENVIRONMENT=production",
    `SPAZAONE_FIREBASE_PROJECT_ID=${PRODUCTION_FIREBASE_PROJECT_ID}`,
    `BUILD_COMMIT=${appCommit}`,
    `WHATSAPP_CATALOG_QUEUE_ENABLED=${sync}`,
    `WHATSAPP_CATALOG_SYNC_ENABLED=${sync}`,
    "WHATSAPP_CATALOG_ID=9415654481779933",
    "WHATSAPP_CATALOG_CANARY_MERCHANT_IDS=",
    `WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED=${sync}`,
    "WHATSAPP_CATALOG_MAX_BATCH_SIZE=10",
    `META_CATALOG_PROVIDER_MODE=${sync ? "live" : "disabled"}`,
    "META_GRAPH_API_VERSION=v25.0",
    "WHATSAPP_SENDER_NUMBER_ID=343481258858230",
    `WHATSAPP_PRODUCT_LIST_ENABLED=${delivery}`,
    `WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS=${controlled ? "merchant_alpha,merchant_beta" : ""}`,
    `WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED=${fullDelivery}`,
    `WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES=${controlled ? `${"1".repeat(64)},${"2".repeat(64)}` : ""}`,
    "WHATSAPP_PRODUCT_LIST_RECIPIENT_COOLDOWN_MS=7000",
    "WHATSAPP_PRODUCT_LIST_MAX_ATTEMPTS=3",
    "WHATSAPP_CATALOG_PAIR_LIMIT_PAUSE_MS=86400000",
    `META_WHATSAPP_MESSAGE_PROVIDER_MODE=${delivery ? "live" : "disabled"}`,
    "",
  ].join("\n");
}

function remoteBuildIdentity(id, generation = "gcfv2") {
  const common = {
    id,
    region: "us-central1",
    platform: generation,
    runtime: "nodejs20",
    entryPoint: id,
    codebase: "default",
    hash: createHash("sha1")
      .update(`firebase-functions:${generation}:${id}`)
      .digest("hex"),
    httpsTrigger: {},
  };
  return generation === "gcfv1"
    ? {
        ...common,
        sourceUploadUrl:
          "https://storage.googleapis.test/redacted-signed-source-upload-url",
      }
    : {
        ...common,
        source: {
          storageSource: {
            bucket: "gcf-v2-sources-test-us-central1",
            object: `catalog/${id}/function-source.zip`,
            generation: "1700000000000000",
          },
        },
        runServiceId: id,
      };
}

function candidateSourceContractFixture() {
  return {
    contractSha256: "d".repeat(64),
    packagedFileCount: 400,
    generatedFileCount: 324,
    firebaseParamsModuleReferenceCount: 0,
    sourceV1HashSha1: `${"a".repeat(40)}.${"b".repeat(40)}`,
    sourceV2HashSha1: "a".repeat(40),
  };
}

async function withProductionTargetEnvironment(overrides, callback) {
  const configured = Object.fromEntries(
    validDotenv("sync-enable", commit)
      .trim()
      .split("\n")
      .map((line) => line.split(/=(.*)/s).slice(0, 2)),
  );
  configured.GCLOUD_PROJECT = PRODUCTION_FIREBASE_PROJECT_ID;
  configured.GOOGLE_CLOUD_PROJECT = PRODUCTION_FIREBASE_PROJECT_ID;
  const names = new Set([
    ...Object.keys(configured),
    ...Object.keys(overrides),
  ]);
  const previous = new Map([...names].map((name) => [name, process.env[name]]));
  Object.assign(process.env, configured, overrides);
  try {
    return await callback();
  } finally {
    for (const [name, value] of previous) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  }
}

test("server binds reconciliation to the exact deployed commit and target before mutation", async () => {
  await withProductionTargetEnvironment({}, async () => {
    assert.deepEqual(immutableWhatsAppCatalogTargetConfiguration(), {
      ...IMMUTABLE_TARGET_CONFIGURATION,
    });
    let executions = 0;
    const result = await runBoundWhatsAppCatalogFullReconciliationPage(
      {
        expectedAppCommit: commit,
        expectedTargetConfigurationDigestSha256: targetDigest,
        pageSize: 10,
      },
      async (executeInput) => {
        executions += 1;
        assert.equal(executeInput.deploymentBinding.deployedAppCommit, commit);
        assert.equal(
          executeInput.deploymentBinding.targetConfigurationDigestSha256,
          targetDigest,
        );
        return page({});
      },
    );
    assert.equal(executions, 1);
    assert.equal(result.deployedAppCommit, commit);
    assert.equal(result.targetConfigurationDigestSha256, targetDigest);
    assert.equal(result.firebaseProjectId, PRODUCTION_FIREBASE_PROJECT_ID);
    assert.equal(result.catalogId, "9415654481779933");
    assert.equal(result.senderPhoneNumberId, "343481258858230");
  });
});

for (const [name, overrides, expectedCommit, expectedDigest] of [
  ["stale commit", {}, "d".repeat(40), targetDigest],
  ["wrong digest", {}, commit, "d".repeat(64)],
  ["wrong project", { GCLOUD_PROJECT: "wrong-project" }, commit, targetDigest],
  ["wrong catalog", { WHATSAPP_CATALOG_ID: "999999" }, commit, targetDigest],
  [
    "wrong sender",
    { WHATSAPP_SENDER_NUMBER_ID: "888888" },
    commit,
    targetDigest,
  ],
]) {
  test(`server rejects ${name} with zero reconciliation mutation`, async () => {
    await withProductionTargetEnvironment(overrides, async () => {
      let executions = 0;
      assert.throws(
        () =>
          assertWhatsAppCatalogDeploymentBinding({
            expectedAppCommit: expectedCommit,
            expectedTargetConfigurationDigestSha256: expectedDigest,
          }),
        /WHATSAPP_CATALOG_DEPLOYMENT_BINDING_MISMATCH/,
      );
      await assert.rejects(
        runBoundWhatsAppCatalogFullReconciliationPage(
          {
            expectedAppCommit: expectedCommit,
            expectedTargetConfigurationDigestSha256: expectedDigest,
          },
          async () => {
            executions += 1;
            return page({});
          },
        ),
        /WHATSAPP_CATALOG_DEPLOYMENT_BINDING_MISMATCH/,
      );
      assert.equal(executions, 0);
    });
  });
}

test("server recovery exposes only bound opaque state and accepts zero-page recovery", async () => {
  await withProductionTargetEnvironment({}, async () => {
    const privateCursor =
      "users/merchant-must-never-escape/products/product-must-never-escape";
    const recoveryState = {
      deploymentBinding: productionBinding,
      status: "running",
      cycleId,
      cursorPath: privateCursor,
      phase: "products",
      pages: 0,
      pageSize: 150,
      productScanComplete: false,
      mappingScanComplete: false,
      continuationStateDigestSha256: continuationDigest,
    };
    const result = await inspectBoundWhatsAppCatalogReconciliationRecovery(
      {
        expectedAppCommit: commit,
        expectedTargetConfigurationDigestSha256: targetDigest,
      },
      async (binding) => {
        assert.equal(binding.deployedAppCommit, commit);
        return recoveryState;
      },
    );
    assert.equal(result.acknowledgedPages, 0);
    assert.equal(result.continuationStateDigestSha256, continuationDigest);
    assert.equal(result.productScanComplete, false);
    assert.equal(result.mappingScanComplete, false);
    assert.doesNotMatch(JSON.stringify(result), /merchant-must-never-escape/);
    assert.doesNotMatch(JSON.stringify(result), /product-must-never-escape/);
    assert.equal(result.cycleId, undefined);
  });
});

test("server continuation uses only server-owned cursor and rejects forged digest", async () => {
  await withProductionTargetEnvironment({}, async () => {
    const privateCursor =
      "users/merchant-must-never-escape/products/product-must-never-escape";
    const initial = {
      deploymentBinding: productionBinding,
      status: "running",
      cycleId,
      cursorPath: privateCursor,
      phase: "mappings",
      pages: 2,
      pageSize: 125,
      productScanComplete: true,
      mappingScanComplete: false,
      continuationStateDigestSha256: continuationDigest,
    };
    const nextDigest = "8".repeat(64);
    let reads = 0;
    let executions = 0;
    const result = await continueBoundWhatsAppCatalogFullReconciliationPage(
      {
        expectedAppCommit: commit,
        expectedTargetConfigurationDigestSha256: targetDigest,
        expectedContinuationStateDigestSha256: continuationDigest,
      },
      async (input) => {
        executions += 1;
        assert.deepEqual(input, {
          cycleId,
          cursorPath: privateCursor,
          pageSize: 125,
          deploymentBinding: {
            deployedAppCommit: commit,
            targetConfigurationDigestSha256: targetDigest,
            firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
            catalogId: "9415654481779933",
            senderPhoneNumberId: "343481258858230",
          },
        });
        return page({ outcome: "scan_complete", phase: "verify" });
      },
      async () => {
        reads += 1;
        return reads === 1
          ? initial
          : {
              ...initial,
              phase: "verify",
              pages: 3,
              mappingScanComplete: true,
              continuationStateDigestSha256: nextDigest,
            };
      },
    );
    assert.equal(executions, 1);
    assert.equal(result.continuationStateDigestSha256, nextDigest);
    assert.doesNotMatch(JSON.stringify(result), /merchant-must-never-escape/);
    assert.doesNotMatch(JSON.stringify(result), /product-must-never-escape/);
    assert.equal(result.merchantCompleteness, undefined);
    assert.equal(result.nextCursorPath, undefined);

    executions = 0;
    await assert.rejects(
      continueBoundWhatsAppCatalogFullReconciliationPage(
        {
          expectedAppCommit: commit,
          expectedTargetConfigurationDigestSha256: targetDigest,
          expectedContinuationStateDigestSha256: "7".repeat(64),
        },
        async () => {
          executions += 1;
          return page({});
        },
        async () => initial,
      ),
      /RECONCILIATION_RECOVERY_DIGEST_MISMATCH/,
    );
    assert.equal(executions, 0);
  });
});

test("a new deployment cannot adopt a stranded cycle from an old binding", async () => {
  await withProductionTargetEnvironment({}, async () => {
    const stranded = {
      deploymentBinding: {
        ...productionBinding,
        deployedAppCommit: "d".repeat(40),
      },
      status: "running",
      cycleId,
      cursorPath: "users/private/products/private",
      phase: "products",
      pages: 1,
      pageSize: 100,
      productScanComplete: false,
      mappingScanComplete: false,
      continuationStateDigestSha256: continuationDigest,
    };
    await assert.rejects(
      inspectBoundWhatsAppCatalogReconciliationRecovery(
        {
          expectedAppCommit: commit,
          expectedTargetConfigurationDigestSha256: targetDigest,
        },
        async () => stranded,
      ),
      /RECONCILIATION_DEPLOYMENT_BINDING_MISMATCH/,
    );
  });
});

test("completed recovery returns only exact aggregate proof without another page", async () => {
  await withProductionTargetEnvironment({}, async () => {
    const completed = {
      deploymentBinding: productionBinding,
      status: "complete",
      cycleId,
      cursorPath: "",
      phase: "complete",
      pages: 9,
      pageSize: 100,
      productScanComplete: true,
      mappingScanComplete: true,
      completionProof: {
        cycleStartedAtMs: Date.parse(cycleStartedAt),
        cycleCompletedAtMs: Date.parse(cycleCompletedAt),
        completionDigest,
        mutationGenerationDigestSha256: mutationGenerationDigest,
        totalOutboxDocuments: 0,
        outboxCountsVerified: true,
        outboxStatusCounts: {
          pending: 0,
          retry: 0,
          processing: 0,
          submitted: 0,
          active: 0,
          deleted: 0,
          rejected: 0,
          unknown: 0,
        },
      },
      continuationStateDigestSha256: continuationDigest,
    };
    const result = await inspectBoundWhatsAppCatalogReconciliationRecovery(
      {
        expectedAppCommit: commit,
        expectedTargetConfigurationDigestSha256: targetDigest,
      },
      async () => completed,
    );
    assert.equal(result.phase, "complete");
    assert.equal(result.cycleId, cycleId);
    assert.equal(result.cycleStartedAt, cycleStartedAt);
    assert.equal(result.cycleCompletedAt, cycleCompletedAt);
    assert.equal(
      result.mutationGenerationDigestSha256,
      mutationGenerationDigest,
    );
    assert.equal(result.pendingOutboxJobs, 0);
    assert.equal(result.totalOutboxDocuments, 0);
    assert.equal(result.outboxCountsVerified, true);
    assert.deepEqual(result.outboxStatusCounts, {
      pending: 0,
      retry: 0,
      processing: 0,
      submitted: 0,
      active: 0,
      deleted: 0,
      rejected: 0,
      unknown: 0,
    });
    assert.doesNotMatch(
      JSON.stringify(result),
      /merchant-must-never|recipient-must-never|users\//i,
    );
  });
});

test("fresh current stability returns only exact redacted aggregate proof", async () => {
  await withProductionTargetEnvironment({}, async () => {
    const readAtMs = Date.now();
    const statusCounts = {
      pending: 0,
      retry: 0,
      processing: 0,
      submitted: 0,
      active: 7,
      deleted: 2,
      rejected: 1,
      unknown: 0,
    };
    const result = await inspectBoundWhatsAppCatalogCurrentStability(
      {
        expectedAppCommit: commit,
        expectedTargetConfigurationDigestSha256: targetDigest,
        expectedCycleId: cycleId,
        expectedCompletionReceiptHashSha256: completionDigest,
        expectedMutationGenerationDigestSha256: mutationGenerationDigest,
      },
      async (binding, expectation) => {
        assert.deepEqual(binding, productionBinding);
        assert.deepEqual(expectation, {
          cycleId,
          completionReceiptHashSha256: completionDigest,
          mutationGenerationDigestSha256: mutationGenerationDigest,
        });
        return {
          deploymentBinding: binding,
          readAtMs,
          cycleId,
          cycleStartedAtMs: readAtMs - 2_000,
          cycleCompletedAtMs: readAtMs - 1_000,
          completionReceiptHashSha256: completionDigest,
          mutationGenerationDigestSha256: mutationGenerationDigest,
          sourceDigestSha256: "d".repeat(64),
          productDocuments: 22,
          mappingDocuments: 22,
          pendingOutboxJobs: 0,
          terminalOutboxDocuments: 10,
          nonterminalOutboxDocuments: 0,
          totalOutboxDocuments: 10,
          outboxCountsVerified: true,
          outboxStatusCounts: statusCounts,
        };
      },
    );
    assert.deepEqual(result, {
      outcome: "current_stability",
      readAtMs,
      cycleId,
      cycleStartedAtMs: readAtMs - 2_000,
      cycleCompletedAtMs: readAtMs - 1_000,
      completionReceiptHashSha256: completionDigest,
      mutationGenerationDigestSha256: mutationGenerationDigest,
      sourceDigestSha256: "d".repeat(64),
      productDocuments: 22,
      mappingDocuments: 22,
      pendingOutboxJobs: 0,
      terminalOutboxDocuments: 10,
      nonterminalOutboxDocuments: 0,
      totalOutboxDocuments: 10,
      outboxCountsVerified: true,
      outboxStatusCounts: statusCounts,
      ...productionBinding,
    });
    assert.doesNotMatch(
      JSON.stringify(result),
      /merchant|product_[0-9]|recipient|users\//i,
    );
  });
});

test("current stability rejects invalid expectations and mismatched live proof before acceptance", async () => {
  await withProductionTargetEnvironment({}, async () => {
    let reads = 0;
    await assert.rejects(
      inspectBoundWhatsAppCatalogCurrentStability(
        {
          expectedAppCommit: commit,
          expectedTargetConfigurationDigestSha256: targetDigest,
          expectedCycleId: "not-a-cycle",
          expectedCompletionReceiptHashSha256: completionDigest,
          expectedMutationGenerationDigestSha256: mutationGenerationDigest,
        },
        async () => {
          reads += 1;
          throw new Error("must not read");
        },
      ),
      (error) =>
        error.code === "RECONCILIATION_CURRENT_STABILITY_EXPECTATION_INVALID",
    );
    assert.equal(reads, 0);

    await assert.rejects(
      inspectBoundWhatsAppCatalogCurrentStability(
        {
          expectedAppCommit: commit,
          expectedTargetConfigurationDigestSha256: targetDigest,
          expectedCycleId: cycleId,
          expectedCompletionReceiptHashSha256: completionDigest,
          expectedMutationGenerationDigestSha256: mutationGenerationDigest,
        },
        async (binding) => ({
          deploymentBinding: binding,
          readAtMs: Date.now(),
          cycleId: "f".repeat(32),
          cycleStartedAtMs: Date.now() - 2_000,
          cycleCompletedAtMs: Date.now() - 1_000,
          completionReceiptHashSha256: completionDigest,
          mutationGenerationDigestSha256: mutationGenerationDigest,
          sourceDigestSha256: "d".repeat(64),
          productDocuments: 22,
          mappingDocuments: 22,
          pendingOutboxJobs: 0,
          terminalOutboxDocuments: 0,
          nonterminalOutboxDocuments: 0,
          totalOutboxDocuments: 0,
          outboxCountsVerified: true,
          outboxStatusCounts: {
            pending: 0,
            retry: 0,
            processing: 0,
            submitted: 0,
            active: 0,
            deleted: 0,
            rejected: 0,
            unknown: 0,
          },
        }),
      ),
      (error) => error.code === "RECONCILIATION_CURRENT_STABILITY_STALE",
    );
  });
});

test("current stability HTTP operation is bot-authenticated before any read", async () => {
  await withProductionTargetEnvironment({}, async () => {
    let status = 200;
    let responseBody;
    await runWhatsAppCatalogFullReconciliationBotHttp(
      {
        method: "POST",
        path: "/runWhatsAppCatalogFullReconciliationBotHttp",
        body: {
          operation: "inspect_current_stability",
          expectedAppCommit: commit,
          expectedTargetConfigurationDigestSha256: targetDigest,
          expectedCycleId: cycleId,
          expectedCompletionReceiptHashSha256: completionDigest,
          expectedMutationGenerationDigestSha256: mutationGenerationDigest,
        },
        get() {
          return undefined;
        },
      },
      {
        status(value) {
          status = value;
          return this;
        },
        json(value) {
          responseBody = value;
          return this;
        },
      },
    );
    assert.equal(status, 401);
    assert.deepEqual(responseBody, {
      error: "Authentication required.",
      code: "AUTHENTICATION_REQUIRED",
    });
  });
});

test("outbox drain evidence exposes unknown statuses and fails equality", () => {
  const evidence = summarizeWhatsAppCatalogOutboxEvidence({
    total: 1,
    pending: 0,
    retry: 0,
    processing: 0,
    submitted: 0,
    active: 0,
    deleted: 0,
    rejected: 0,
  });
  assert.equal(evidence.pendingOutboxJobs, 0);
  assert.equal(evidence.totalOutboxDocuments, 1);
  assert.equal(evidence.outboxCountsVerified, false);
  assert.deepEqual(evidence.outboxStatusCounts, {
    pending: 0,
    retry: 0,
    processing: 0,
    submitted: 0,
    active: 0,
    deleted: 0,
    rejected: 0,
    unknown: 1,
  });
});

test("outbox drain evidence accounts for retained terminal audit rows", () => {
  const evidence = summarizeWhatsAppCatalogOutboxEvidence({
    total: 3,
    pending: 0,
    retry: 0,
    processing: 0,
    submitted: 0,
    active: 2,
    deleted: 1,
    rejected: 0,
  });
  assert.equal(evidence.pendingOutboxJobs, 0);
  assert.equal(evidence.totalOutboxDocuments, 3);
  assert.equal(evidence.outboxCountsVerified, true);
  assert.equal(evidence.outboxStatusCounts.unknown, 0);
});

test("mutation generation is order-independent and changes for every source or outbox mutation", () => {
  const entries = [
    {
      scope: "product",
      path: "users/merchant/products/product",
      updateTimeMs: 1_000,
    },
    {
      scope: "mapping",
      path: "whatsappCatalogMappings/spz_example",
      updateTimeMs: 2_000,
    },
    {
      scope: "outbox",
      path: "whatsappCatalogOutbox/spz_example",
      updateTimeMs: 3_000,
      status: "active",
    },
  ];
  const initial = whatsappCatalogMutationGenerationDigest({ entries });
  assert.equal(
    whatsappCatalogMutationGenerationDigest({
      entries: [...entries].reverse(),
    }),
    initial,
  );
  assert.notEqual(
    whatsappCatalogMutationGenerationDigest({
      entries: entries.map((entry, index) =>
        index === 0 ? { ...entry, updateTimeMs: 1_001 } : entry,
      ),
    }),
    initial,
  );
  assert.notEqual(
    whatsappCatalogMutationGenerationDigest({
      entries: entries.map((entry, index) =>
        index === 1 ? { ...entry, updateTimeMs: 2_001 } : entry,
      ),
    }),
    initial,
  );
  assert.notEqual(
    whatsappCatalogMutationGenerationDigest({
      entries: entries.map((entry, index) =>
        index === 2
          ? { ...entry, updateTimeMs: 3_001, status: "pending" }
          : entry,
      ),
    }),
    initial,
  );
  assert.equal(WHATSAPP_CATALOG_RECEIPT_MAX_FUTURE_SKEW_MS, 5 * 60 * 1000);
  assert.throws(
    () =>
      whatsappCatalogMutationGenerationDigest({
        entries: [{ scope: "outbox", path: "x", updateTimeMs: 1 }],
      }),
    /WHATSAPP_CATALOG_MUTATION_GENERATION_INVALID/,
  );
});

test("mutation evidence has an explicit fail-closed transaction read bound", () => {
  assert.equal(WHATSAPP_CATALOG_MAX_GENERATION_DOCUMENTS, 5_000);
  assert.doesNotThrow(() =>
    assertWhatsAppCatalogMutationEvidenceWithinLimit({
      productDocuments: 2_000,
      mappingDocuments: 1_500,
      outboxDocuments: 1_500,
    }),
  );
  assert.throws(
    () =>
      assertWhatsAppCatalogMutationEvidenceWithinLimit({
        productDocuments: 2_001,
        mappingDocuments: 1_500,
        outboxDocuments: 1_500,
      }),
    (error) => error.code === "RECONCILIATION_EVIDENCE_LIMIT_EXCEEDED",
  );
  assert.throws(
    () =>
      assertWhatsAppCatalogMutationEvidenceWithinLimit({
        productDocuments: -1,
        mappingDocuments: 0,
        outboxDocuments: 0,
      }),
    (error) => error.code === "RECONCILIATION_EVIDENCE_LIMIT_EXCEEDED",
  );
});

test("secret resolution pins Firebase project/account and scrubs ambient credentials", async () => {
  const childSecret = Buffer.from("resolved-test-secret\n");
  let invocation;
  const token = await resolvePasellaBotToken({
    environment: {
      PATH: process.env.PATH,
      HOME: process.env.HOME,
      PASELLA_BOT_TOKEN: "ambient-forbidden",
      FIREBASE_TOKEN: "ambient-forbidden",
      SOME_API_KEY: "ambient-forbidden",
    },
    execFileImpl: async (command, args, options) => {
      invocation = { command, args, options };
      return { stdout: childSecret };
    },
  });
  assert.equal(invocation.command, "/opt/homebrew/bin/firebase");
  assert.deepEqual(invocation.args, [
    "--project",
    PRODUCTION_FIREBASE_PROJECT_ID,
    "--account",
    PRODUCTION_FIREBASE_ACCOUNT,
    "--non-interactive",
    "functions:secrets:access",
    "PASELLA_BOT_TOKEN",
  ]);
  assert.equal(invocation.options.env.PASELLA_BOT_TOKEN, undefined);
  assert.equal(invocation.options.env.FIREBASE_TOKEN, undefined);
  assert.equal(invocation.options.env.SOME_API_KEY, undefined);
  assert.equal(token.toString("utf8"), "resolved-test-secret");
  assert.ok(childSecret.every((byte) => byte === 0));
  token.fill(0);

  const invalidSecret = Buffer.from("resolved-test-secret\nsecond-line\n");
  await assert.rejects(
    resolvePasellaBotToken({
      execFileImpl: async () => ({ stdout: invalidSecret }),
    }),
    (error) => error.code === "BOT_SECRET_RESOLUTION_INVALID",
  );
  assert.ok(invalidSecret.every((byte) => byte === 0));
});

test("authority resolver uses the guarded read-only ref for a clean exact Vox Dei checkout", async () => {
  const authorityInvocations = [];
  const outputs = [
    "",
    `${commit}\n`,
    JSON.stringify({
      project_id: "spaza-one",
      project: "Spaza One",
      component: "app",
      role: "authority",
      entity: "vox-dei",
      account: "github.tsepo-vox-dei",
      repository: "Vox-Dei-Build/spazaone-app",
      matched_by: "git_origin",
      origin: "https://github.com/Vox-Dei-Build/spazaone-app.git",
    }),
    `${FROZEN_APP_MAIN_COMMIT}\n`,
    `${FROZEN_APP_MAIN_COMMIT}\n`,
  ];
  const resolved = await resolveAuthorityAppCommit({
    expectedCandidateCommit: commit,
    expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
    environment: {
      PATH: process.env.PATH,
      PASELLA_BOT_TOKEN: "ambient-forbidden",
    },
    execFileImpl: async (command, args, options) => {
      authorityInvocations.push({ command, args, options });
      return { stdout: outputs.shift() };
    },
  });
  assert.equal(resolved, commit);
  assert.equal(authorityInvocations.length, 5);
  assert.deepEqual(authorityInvocations[3].args, [
    "gh",
    "--project",
    "spaza-one",
    "--component",
    "app",
    "--role",
    "authority",
    "--",
    "api",
    "repos/Vox-Dei-Build/spazaone-app/git/ref/heads/main",
    "--jq",
    ".object.sha",
  ]);
  assert.deepEqual(authorityInvocations[4].args, [
    "merge-base",
    commit,
    FROZEN_APP_MAIN_COMMIT,
  ]);
  assert.ok(
    authorityInvocations.every(
      (invocation) => invocation.options.env.PASELLA_BOT_TOKEN === undefined,
    ),
  );

  const dirtyOutputs = [
    " M unsafe-file\n",
    `${commit}\n`,
    JSON.stringify({
      project_id: "spaza-one",
      project: "Spaza One",
      component: "app",
      role: "authority",
      entity: "vox-dei",
      account: "github.tsepo-vox-dei",
      repository: "Vox-Dei-Build/spazaone-app",
      matched_by: "git_origin",
    }),
    `${FROZEN_APP_MAIN_COMMIT}\n`,
    `${FROZEN_APP_MAIN_COMMIT}\n`,
  ];
  await assert.rejects(
    resolveAuthorityAppCommit({
      expectedCandidateCommit: commit,
      expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
      execFileImpl: async () => ({ stdout: dirtyOutputs.shift() }),
    }),
    (error) => error.code === "APP_AUTHORITY_CHECKOUT_DIRTY",
  );

  const movedMainOutputs = [
    "",
    `${commit}\n`,
    JSON.stringify({
      project_id: "spaza-one",
      project: "Spaza One",
      component: "app",
      role: "authority",
      entity: "vox-dei",
      account: "github.tsepo-vox-dei",
      repository: "Vox-Dei-Build/spazaone-app",
      matched_by: "git_origin",
    }),
    `${"e".repeat(40)}\n`,
    `${FROZEN_APP_MAIN_COMMIT}\n`,
  ];
  await assert.rejects(
    resolveAuthorityAppCommit({
      expectedCandidateCommit: commit,
      expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
      execFileImpl: async () => ({ stdout: movedMainOutputs.shift() }),
    }),
    (error) => error.code === "APP_AUTHORITY_MAIN_MOVED",
  );
});

test("authority resolver permits only an allowlisted clean descendant for readback-first recovery", async () => {
  const recoveryRevision = "d".repeat(40);
  const authority = JSON.stringify({
    project_id: "spaza-one",
    project: "Spaza One",
    component: "app",
    role: "authority",
    entity: "vox-dei",
    account: "github.tsepo-vox-dei",
    repository: "Vox-Dei-Build/spazaone-app",
    matched_by: "git_origin",
  });
  const baseOutputs = (changedPaths) => [
    "",
    `${recoveryRevision}\n`,
    authority,
    `${FROZEN_APP_MAIN_COMMIT}\n`,
    `${FROZEN_APP_MAIN_COMMIT}\n`,
    `${commit}\n`,
    `${changedPaths.join("\n")}\n`,
  ];

  const directOutputs = baseOutputs([
    "functions/scripts/firebase-function-source-binding.mjs",
  ]);
  await assert.rejects(
    resolveAuthorityAppCommit({
      expectedCandidateCommit: commit,
      expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
      execFileImpl: async () => ({ stdout: directOutputs.shift() }),
    }),
    (error) => error.code === "APP_AUTHORITY_REVIEWED_CANDIDATE_MISMATCH",
  );
  assert.equal(directOutputs.length, 2);

  const recoveryOutputs = baseOutputs([
    "functions/scripts/execute-whatsapp-catalog-production.mjs",
    "functions/scripts/firebase-function-source-binding.mjs",
    "functions/scripts/run-whatsapp-catalog-full-reconciliation.mjs",
    "functions/test/whatsapp_catalog_production_tools.test.mjs",
  ]);
  const resolved = await resolveAuthorityAppCommit({
    expectedCandidateCommit: commit,
    expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
    allowRecoveryExecutorDescendant: true,
    execFileImpl: async () => ({ stdout: recoveryOutputs.shift() }),
  });
  assert.equal(resolved, commit);
  assert.equal(recoveryOutputs.length, 0);

  const unrelatedOutputs = baseOutputs([
    "functions/scripts/firebase-function-source-binding.mjs",
    "functions/src/index.ts",
  ]);
  await assert.rejects(
    resolveAuthorityAppCommit({
      expectedCandidateCommit: commit,
      expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
      allowRecoveryExecutorDescendant: true,
      execFileImpl: async () => ({ stdout: unrelatedOutputs.shift() }),
    }),
    (error) => error.code === "APP_AUTHORITY_REVIEWED_CANDIDATE_MISMATCH",
  );

  const nonDescendantOutputs = baseOutputs([
    "functions/scripts/firebase-function-source-binding.mjs",
  ]);
  nonDescendantOutputs[5] = `${"e".repeat(40)}\n`;
  await assert.rejects(
    resolveAuthorityAppCommit({
      expectedCandidateCommit: commit,
      expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
      allowRecoveryExecutorDescendant: true,
      execFileImpl: async () => ({ stdout: nonDescendantOutputs.shift() }),
    }),
    (error) => error.code === "APP_AUTHORITY_REVIEWED_CANDIDATE_MISMATCH",
  );
});

test("runner arguments expose only an explicit reviewed recovery switch", () => {
  assert.deepEqual(
    parseRunnerArguments([
      "--expected-app-commit",
      commit,
      "--expected-current-main-commit",
      FROZEN_APP_MAIN_COMMIT,
      "--page-size",
      "100",
    ]),
    {
      execute: false,
      dryRun: true,
      receiptPath: null,
      candidateManifestPath: null,
      expectedCandidateManifestSha256: null,
      expectedAppCommit: commit,
      expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
      reviewedResume: false,
      priorNeedsReviewReceiptPath: null,
      expectedPriorNeedsReviewReceiptSha256: null,
      pageSize: 100,
      pollMs: 65_000,
      maxSteps: 10_000,
      maxElapsedMs: 24 * 60 * 60_000,
      requestTimeoutMs: 570_000,
    },
  );
  assert.throws(
    () => parseRunnerArguments(["--token", "forbidden"]),
    (error) => error.code === "OPERATOR_ARGUMENT_FORBIDDEN",
  );
  assert.throws(
    () => parseRunnerArguments(["--cycle-id", cycleId]),
    (error) => error.code === "OPERATOR_ARGUMENT_FORBIDDEN",
  );
  assert.equal(
    parseRunnerArguments([
      "--expected-app-commit",
      commit,
      "--expected-current-main-commit",
      FROZEN_APP_MAIN_COMMIT,
      "--reviewed-resume",
      "--execute",
      "--receipt-path",
      "/tmp/test-reconciliation-receipt.json",
      "--candidate-manifest-path",
      candidateManifestPath,
      "--expected-candidate-manifest-sha256",
      candidateManifestSha256,
      "--prior-needs-review-receipt-path",
      "/tmp/prior-needs-review-reconciliation-receipt.json",
      "--expected-prior-needs-review-receipt-sha256",
      "9".repeat(64),
    ]).reviewedResume,
    true,
  );
  assert.throws(
    () =>
      parseRunnerArguments([
        "--expected-app-commit",
        commit,
        "--expected-current-main-commit",
        FROZEN_APP_MAIN_COMMIT,
        "--reviewed-resume",
        "--execute",
        "--receipt-path",
        "/tmp/test-reconciliation-receipt.json",
        "--candidate-manifest-path",
        candidateManifestPath,
        "--expected-candidate-manifest-sha256",
        candidateManifestSha256,
      ]),
    (error) => error.code === "OPERATOR_RECEIPT_EXECUTION_INVALID",
  );
  assert.throws(
    () =>
      parseRunnerArguments([
        "--expected-app-commit",
        commit,
        "--expected-current-main-commit",
        FROZEN_APP_MAIN_COMMIT,
        "--execute",
        "--receipt-path",
        "/tmp/test-reconciliation-receipt.json",
        "--candidate-manifest-path",
        candidateManifestPath,
        "--expected-candidate-manifest-sha256",
        candidateManifestSha256,
        "--prior-needs-review-receipt-path",
        "/tmp/prior-needs-review-reconciliation-receipt.json",
        "--expected-prior-needs-review-receipt-sha256",
        "9".repeat(64),
      ]),
    (error) => error.code === "OPERATOR_RECEIPT_EXECUTION_INVALID",
  );
  assert.throws(
    () =>
      parseRunnerArguments([
        "--expected-app-commit",
        commit,
        "--expected-current-main-commit",
        FROZEN_APP_MAIN_COMMIT,
        "--execute",
      ]),
    (error) => error.code === "OPERATOR_RECEIPT_EXECUTION_INVALID",
  );
  assert.throws(
    () =>
      parseRunnerArguments([
        "--expected-app-commit",
        commit,
        "--expected-current-main-commit",
        FROZEN_APP_MAIN_COMMIT,
        "--receipt-path",
        "/tmp/forbidden-dry-run-receipt.json",
      ]),
    (error) => error.code === "OPERATOR_RECEIPT_EXECUTION_INVALID",
  );
  assert.throws(
    () =>
      parseRunnerArguments([
        "--expected-app-commit",
        commit,
        "--reviewed-resume",
        "--reviewed-resume",
      ]),
    (error) => error.code === "OPERATOR_ARGUMENT_DUPLICATE",
  );
  assert.throws(
    () =>
      parseRunnerArguments([
        "--target-configuration-digest-sha256",
        "f".repeat(64),
      ]),
    (error) => error.code === "OPERATOR_ARGUMENT_FORBIDDEN",
  );
  assert.throws(
    () => parseRunnerArguments([]),
    (error) => error.code === "EXPECTED_APP_COMMIT_INVALID",
  );
});

test("production reconciliation CLI is dry-only and execute remains disabled", () => {
  const common = [
    "scripts/run-whatsapp-catalog-full-reconciliation.mjs",
    "--expected-app-commit",
    commit,
    "--expected-current-main-commit",
    FROZEN_APP_MAIN_COMMIT,
  ];
  const dry = spawnSync(process.execPath, common, {
    cwd: path.resolve("."),
    encoding: "utf8",
  });
  assert.equal(dry.status, 0);
  assert.deepEqual(JSON.parse(dry.stdout), {
    schemaVersion: 1,
    outcome: "dry_run_only",
    dryRun: true,
    remoteWriteAttempted: false,
    receiptPersisted: false,
    firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
    appCommit: commit,
    currentMainCommit: FROZEN_APP_MAIN_COMMIT,
    targetConfigurationDigestSha256: targetDigest,
    executeGate: "separate_production_sync_authorization_required",
  });

  const execute = spawnSync(
    process.execPath,
    [
      ...common,
      "--execute",
      "--receipt-path",
      "/tmp/never-created-reconciliation-receipt.json",
      "--candidate-manifest-path",
      candidateManifestPath,
      "--expected-candidate-manifest-sha256",
      candidateManifestSha256,
    ],
    { cwd: path.resolve("."), encoding: "utf8" },
  );
  assert.equal(execute.status, 1);
  assert.equal(
    JSON.parse(execute.stderr).code,
    "PRODUCTION_RECONCILIATION_EXECUTOR_NOT_ENABLED",
  );
});

test("catalog deployment dotenv is an exact non-secret dark or sync contract", () => {
  const dark = validateCatalogDeploymentDotenv({
    lane: "dark-new",
    text: validDotenv("dark-new"),
    appCommit: commit,
  });
  const sync = validateCatalogDeploymentDotenv({
    lane: "sync-enable",
    text: validDotenv("sync-enable"),
    appCommit: commit,
  });
  assert.match(dark.sha256, /^[a-f0-9]{64}$/);
  assert.match(sync.sha256, /^[a-f0-9]{64}$/);
  assert.notEqual(dark.sha256, sync.sha256);
  assert.equal(dark.targetConfigurationDigestSha256, targetDigest);
  assert.equal(sync.targetConfigurationDigestSha256, targetDigest);
  assert.equal(dark.keyNames.length, 20);
  assert.equal(sync.keyNames.length, 20);
  assert.ok(!dark.keyNames.some((key) => key.includes("TOKEN")));
  assert.doesNotMatch(dark.normalized, /ACCESS_TOKEN|RECIPIENT_HASH_KEY/);
});

test("immutable target digest excludes every runtime switch and build revision", () => {
  assert.deepEqual(Object.keys(IMMUTABLE_TARGET_CONFIGURATION), [
    "schemaVersion",
    "SPAZAONE_ENVIRONMENT",
    "SPAZAONE_FIREBASE_PROJECT_ID",
    "WHATSAPP_CATALOG_ID",
    "WHATSAPP_CATALOG_MAX_BATCH_SIZE",
    "META_GRAPH_API_VERSION",
    "WHATSAPP_SENDER_NUMBER_ID",
    "WHATSAPP_PRODUCT_LIST_RECIPIENT_COOLDOWN_MS",
    "WHATSAPP_PRODUCT_LIST_MAX_ATTEMPTS",
    "WHATSAPP_CATALOG_PAIR_LIMIT_PAUSE_MS",
  ]);
  assert.doesNotMatch(
    JSON.stringify(IMMUTABLE_TARGET_CONFIGURATION),
    /ENABLED|ROLLOUT|CANARY|RECIPIENT_HASHES|BUILD_COMMIT|PROVIDER_MODE/,
  );
  const dark = validateCatalogDeploymentDotenv({
    lane: "dark-new",
    text: validDotenv("dark-new", "1".repeat(40)),
    appCommit: "1".repeat(40),
  });
  const sync = validateCatalogDeploymentDotenv({
    lane: "sync-enable",
    text: validDotenv("sync-enable", "2".repeat(40)),
    appCommit: "2".repeat(40),
  });
  assert.notEqual(dark.sha256, sync.sha256);
  assert.equal(
    targetDigest,
    createHash("sha256")
      .update(JSON.stringify(IMMUTABLE_TARGET_CONFIGURATION))
      .digest("hex"),
  );
  assert.equal(dark.targetConfigurationDigestSha256, targetDigest);
  assert.equal(sync.targetConfigurationDigestSha256, targetDigest);
});

test("catalog deployment dotenv rejects secrets, extras, omissions, and unsafe activation", () => {
  assert.throws(
    () =>
      parseStrictDotenv(
        `${validDotenv("dark-new")}META_CATALOG_ACCESS_TOKEN=forbidden\n`,
      ),
    (error) => error.code === "CATALOG_DOTENV_SECRET_FORBIDDEN",
  );
  assert.throws(
    () =>
      validateCatalogDeploymentDotenv({
        lane: "dark-new",
        text: `${validDotenv("dark-new")}UNEXPECTED=value\n`,
        appCommit: commit,
      }),
    (error) => error.code === "CATALOG_DOTENV_KEYSET_INVALID",
  );
  assert.throws(
    () =>
      validateCatalogDeploymentDotenv({
        lane: "dark-new",
        text: validDotenv("dark-new").replace(
          "WHATSAPP_PRODUCT_LIST_ENABLED=false\n",
          "",
        ),
        appCommit: commit,
      }),
    (error) => error.code === "CATALOG_DOTENV_KEYSET_INVALID",
  );
  assert.throws(
    () =>
      validateCatalogDeploymentDotenv({
        lane: "sync-enable",
        text: validDotenv("sync-enable").replace(
          "WHATSAPP_PRODUCT_LIST_ENABLED=false",
          "WHATSAPP_PRODUCT_LIST_ENABLED=true",
        ),
        appCommit: commit,
      }),
    (error) =>
      error.code === "CATALOG_DOTENV_WHATSAPP_PRODUCT_LIST_ENABLED_INVALID",
  );
});

test("new and existing deployment selectors are exact and disjoint", () => {
  assert.deepEqual(NATIVE_CATALOG_NEW_FUNCTIONS, [
    "onMerchantProductCatalogChange",
    "syncWhatsAppMerchantCatalog",
    "reconcileWhatsAppMerchantCatalog",
    "runWhatsAppCatalogFullReconciliationBotHttp",
    "getMerchantWhatsAppCatalogCompletenessBotHttp",
    "getMerchantWhatsAppProductListBotHttp",
    "getWhatsAppCatalogSyncStatusV1",
    "resolveMerchantWhatsAppCatalogProductBotHttp",
    "sendMerchantWhatsAppCatalogBotHttp",
    "getWhatsAppProductListDeliveryStatusBotHttp",
    "monitorWhatsAppProductListDeliveries",
    "replaceWhatsAppCatalogCartBotHttp",
  ]);
  assert.deepEqual(NATIVE_CATALOG_EXISTING_FUNCTIONS, [
    "getMerchantCatalogBotHttp",
    "checkoutCart",
    "cancelOrder",
    "finalizeOnlinePaid",
    "updateOrderPayment",
  ]);
  assert.deepEqual(NATIVE_CATALOG_SYNC_FUNCTIONS, [
    "onMerchantProductCatalogChange",
    "syncWhatsAppMerchantCatalog",
    "reconcileWhatsAppMerchantCatalog",
    "runWhatsAppCatalogFullReconciliationBotHttp",
    "getMerchantWhatsAppCatalogCompletenessBotHttp",
    "getMerchantWhatsAppProductListBotHttp",
  ]);
  assert.deepEqual(NATIVE_CATALOG_DELIVERY_FUNCTIONS, [
    "resolveMerchantWhatsAppCatalogProductBotHttp",
    "sendMerchantWhatsAppCatalogBotHttp",
    "getWhatsAppProductListDeliveryStatusBotHttp",
    "monitorWhatsAppProductListDeliveries",
    "replaceWhatsAppCatalogCartBotHttp",
  ]);
  assert.deepEqual(
    Object.keys(NATIVE_CATALOG_FUNCTION_SECRET_REFS).sort(),
    [...NATIVE_CATALOG_NEW_FUNCTIONS].sort(),
  );
  assert.deepEqual(
    NATIVE_CATALOG_FUNCTION_SECRET_REFS.syncWhatsAppMerchantCatalog,
    ["META_CATALOG_ACCESS_TOKEN"],
  );
  assert.deepEqual(
    [
      ...NATIVE_CATALOG_FUNCTION_SECRET_REFS.sendMerchantWhatsAppCatalogBotHttp,
    ].sort(),
    [
      "META_WHATSAPP_ACCESS_TOKEN",
      "PASELLA_BOT_TOKEN",
      "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
    ].sort(),
  );
  assert.equal(
    new Set([
      ...NATIVE_CATALOG_NEW_FUNCTIONS,
      ...NATIVE_CATALOG_EXISTING_FUNCTIONS,
    ]).size,
    17,
  );
  assert.ok(
    NATIVE_CATALOG_EXISTING_FUNCTIONS.every(
      (name) => !NATIVE_CATALOG_NEW_FUNCTIONS.includes(name),
    ),
  );
  assert.ok(
    NATIVE_CATALOG_SYNC_FUNCTIONS.every((name) =>
      NATIVE_CATALOG_NEW_FUNCTIONS.includes(name),
    ),
  );
  assert.equal(
    catalogFunctionSelector("existing-code"),
    NATIVE_CATALOG_EXISTING_FUNCTIONS.map((name) => `functions:${name}`).join(
      ",",
    ),
  );
  assert.equal(
    catalogFunctionSelector("controlled-delivery-enable"),
    NATIVE_CATALOG_DELIVERY_FUNCTIONS.map((name) => `functions:${name}`).join(
      ",",
    ),
  );
  assert.equal(
    catalogFunctionSelector("all-eligible-delivery-enable"),
    catalogFunctionSelector("delivery-disable"),
  );
  assert.equal(
    catalogFunctionSelector("sync-enable"),
    catalogFunctionSelector("sync-disable"),
  );
  assert.ok(
    !NATIVE_CATALOG_DELIVERY_FUNCTIONS.includes("getMerchantCatalogBotHttp"),
  );
});

test("controlled, full, disable, and sync-disable lanes are exact and redacted", () => {
  const controlled = validateCatalogDeploymentDotenv({
    lane: "controlled-delivery-enable",
    text: validDotenv("controlled-delivery-enable"),
    appCommit: commit,
  });
  assert.deepEqual(controlled.rollout, {
    queueEnabled: true,
    syncEnabled: true,
    catalogFullRolloutEnabled: true,
    deliveryEnabled: true,
    deliveryFullRolloutEnabled: false,
    catalogProviderMode: "live",
    messageProviderMode: "live",
    merchantScopeCount: 2,
    merchantScopeDigestSha256: createHash("sha256")
      .update("merchant_alpha\nmerchant_beta")
      .digest("hex"),
    recipientScopeCount: 2,
    recipientScopeDigestSha256: createHash("sha256")
      .update(`${"1".repeat(64)}\n${"2".repeat(64)}`)
      .digest("hex"),
  });
  const redacted = JSON.stringify(controlled.rollout);
  assert.doesNotMatch(redacted, /merchant_alpha|merchant_beta/);
  assert.doesNotMatch(redacted, new RegExp("1{64}|2{64}"));

  const full = validateCatalogDeploymentDotenv({
    lane: "all-eligible-delivery-enable",
    text: validDotenv("all-eligible-delivery-enable"),
    appCommit: commit,
  });
  assert.equal(full.rollout.deliveryFullRolloutEnabled, true);
  assert.equal(full.rollout.merchantScopeCount, 0);
  assert.equal(full.rollout.recipientScopeCount, 0);

  const disabled = validateCatalogDeploymentDotenv({
    lane: "delivery-disable",
    text: validDotenv("delivery-disable"),
    appCommit: commit,
  });
  assert.equal(disabled.rollout.syncEnabled, true);
  assert.equal(disabled.rollout.deliveryEnabled, false);

  const syncDisabled = validateCatalogDeploymentDotenv({
    lane: "sync-disable",
    text: validDotenv("sync-disable"),
    appCommit: commit,
  });
  assert.equal(syncDisabled.rollout.syncEnabled, false);
  assert.equal(syncDisabled.rollout.deliveryEnabled, false);
});

test("existing-function lane cannot accept a dotenv or config override", () => {
  assert.deepEqual(
    parseDeploymentGuardArguments([
      "--lane",
      "existing-code",
      "--expected-app-commit",
      commit,
      "--expected-current-main-commit",
      FROZEN_APP_MAIN_COMMIT,
    ]),
    {
      lane: "existing-code",
      expectedAppCommit: commit,
      expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
      dryRun: true,
      execute: false,
      receiptPath: null,
      candidateManifestPath: null,
      expectedCandidateManifestSha256: null,
      readbackOnly: false,
    },
  );
  assert.deepEqual(
    parseDeploymentGuardArguments([
      "--lane",
      "dark-new",
      "--expected-app-commit",
      commit,
      "--expected-current-main-commit",
      FROZEN_APP_MAIN_COMMIT,
      "--execute",
      "--receipt-path",
      "/tmp/catalog-deploy-receipt.json",
      "--candidate-manifest-path",
      candidateManifestPath,
      "--expected-candidate-manifest-sha256",
      candidateManifestSha256,
    ]),
    {
      lane: "dark-new",
      expectedAppCommit: commit,
      expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
      dryRun: false,
      execute: true,
      receiptPath: "/tmp/catalog-deploy-receipt.json",
      candidateManifestPath,
      expectedCandidateManifestSha256: candidateManifestSha256,
      readbackOnly: false,
    },
  );
  assert.throws(
    () =>
      parseDeploymentGuardArguments([
        "--lane",
        "existing-code",
        "--expected-app-commit",
        commit,
        "--config",
        "/tmp/forbidden",
      ]),
    (error) => error.code === "CATALOG_DEPLOY_ARGUMENT_FORBIDDEN",
  );
  const args = codexGuardDeployArguments({
    lane: "existing-code",
    dryRun: true,
  });
  assert.deepEqual(args.slice(0, 5), [
    "firebase-deploy",
    "--project",
    "spaza-one",
    "--dry-run",
    "--",
  ]);
  assert.ok(!args.includes("--config"));
  assert.throws(
    () => parseDeploymentGuardArguments(["--lane", "dark-new"]),
    (error) => error.code === "EXPECTED_APP_COMMIT_INVALID",
  );
});

test("production deploy CLI requires receipt syntax but execute remains disabled", () => {
  assert.throws(
    () =>
      parseDeploymentGuardArguments([
        "--lane",
        "dark-new",
        "--expected-app-commit",
        commit,
        "--expected-current-main-commit",
        FROZEN_APP_MAIN_COMMIT,
        "--execute",
      ]),
    (error) => error.code === "CATALOG_DEPLOY_RECEIPT_EXECUTION_INVALID",
  );
  const result = spawnSync(
    process.execPath,
    [
      "scripts/guard-whatsapp-catalog-functions-deploy.mjs",
      "--lane",
      "dark-new",
      "--expected-app-commit",
      commit,
      "--expected-current-main-commit",
      FROZEN_APP_MAIN_COMMIT,
      "--execute",
      "--receipt-path",
      "/tmp/never-created-deploy-receipt.json",
      "--candidate-manifest-path",
      candidateManifestPath,
      "--expected-candidate-manifest-sha256",
      candidateManifestSha256,
    ],
    { cwd: path.resolve("."), encoding: "utf8" },
  );
  assert.equal(result.status, 1);
  assert.equal(
    JSON.parse(result.stderr).code,
    "PRODUCTION_CATALOG_DEPLOY_EXECUTOR_NOT_ENABLED",
  );
});

test("existing-function lane fails closed without pinned CLI remote-env merge", () => {
  assert.doesNotThrow(() =>
    assertFirebaseCliEnvironmentPreservationSource(`
      if (!usedDotenv) {
        wantE.environmentVariables = {
          ...haveE.environmentVariables,
          ...wantE.environmentVariables,
        };
      }
    `),
  );
  assert.throws(
    () =>
      assertFirebaseCliEnvironmentPreservationSource(`
        wantE.environmentVariables = { ...wantE.environmentVariables };
      `),
    (error) =>
      error.code === "FIREBASE_CLI_ENVIRONMENT_PRESERVATION_UNVERIFIED",
  );
});

test("function identity accepts only real normalized Gen 1 and Gen 2 endpoints", () => {
  const gen1 = remoteBuildIdentity(
    "sendMerchantWhatsAppCatalogBotHttp",
    "gcfv1",
  );
  const gen2 = remoteBuildIdentity(
    "replaceWhatsAppCatalogCartBotHttp",
    "gcfv2",
  );
  const gen1Digest = canonicalFunctionBuildIdentityDigest(gen1);
  const gen2Digest = canonicalFunctionBuildIdentityDigest(gen2);
  assert.match(gen1Digest, /^[a-f0-9]{64}$/);
  assert.match(gen2Digest, /^[a-f0-9]{64}$/);
  assert.notEqual(gen1Digest, gen2Digest);

  const gen1WithoutSignedSourceUrl = { ...gen1 };
  delete gen1WithoutSignedSourceUrl.sourceUploadUrl;
  assert.equal(
    canonicalFunctionBuildIdentityDigest(gen1WithoutSignedSourceUrl),
    gen1Digest,
  );
  assert.equal(
    canonicalFunctionBuildIdentityDigest({
      ...gen1,
      sourceUploadUrl:
        "https://storage.googleapis.test/a-different-signed-upload-url",
    }),
    gen1Digest,
  );
  assert.notEqual(
    canonicalFunctionBuildIdentityDigest({
      ...gen2,
      source: {
        storageSource: {
          ...gen2.source.storageSource,
          generation: "1700000000000001",
        },
      },
    }),
    gen2Digest,
  );

  const invalid = [
    { ...gen1, hash: undefined },
    { ...gen1, hash: "f".repeat(39) },
    { ...gen1, hash: "F".repeat(40) },
    { ...gen1, platform: "gen1" },
    { ...gen1, platform: "GCFV1" },
    { ...gen1, codebase: "catalog" },
    { ...gen1, region: "europe-west1" },
    { ...gen1, runtime: "nodejs18" },
    { ...gen1, entryPoint: "differentEntryPoint" },
    { ...gen2, source: undefined },
  ];
  for (const endpoint of invalid) {
    assert.equal(canonicalFunctionBuildIdentityDigest(endpoint), null);
  }
});

test("function readback closes configured receipts without exposing scope values", async () => {
  const validated = validateCatalogDeploymentDotenv({
    lane: "controlled-delivery-enable",
    text: validDotenv("controlled-delivery-enable"),
    appCommit: commit,
  });
  const environmentVariables = Object.fromEntries(
    parseStrictDotenv(validated.normalized),
  );
  const sourceContract = candidateSourceContractFixture();
  const firebaseConfig = JSON.stringify({
    projectId: PRODUCTION_FIREBASE_PROJECT_ID,
    storageBucket: "pasella-ledger.appspot.com",
  });
  const endpoints = NATIVE_CATALOG_DELIVERY_FUNCTIONS.map((id, index) => {
    const platform = index === 0 ? "gcfv1" : "gcfv2";
    const backendEnvironment = {
      ...environmentVariables,
      FIREBASE_CONFIG: firebaseConfig,
      GCLOUD_PROJECT: PRODUCTION_FIREBASE_PROJECT_ID,
    };
    const endpointEnvironment = {
      ...backendEnvironment,
      EVENTARC_CLOUD_EVENT_SOURCE: `projects/${PRODUCTION_FIREBASE_PROJECT_ID}/locations/us-central1/${platform === "gcfv1" ? "functions" : "services"}/${id}`,
    };
    const secretEnvironmentVariables = NATIVE_CATALOG_FUNCTION_SECRET_REFS[
      id
    ].map((key, secretIndex) => ({
      key,
      projectId: PRODUCTION_FIREBASE_PROJECT_NUMBER,
      secret: key,
      version: String(secretIndex + 1),
    }));
    const secretVersions = Object.fromEntries(
      secretEnvironmentVariables.map(({ key, version }) => [key, version]),
    );
    return {
      ...remoteBuildIdentity(id, platform),
      hash: firebaseEndpointHashSha1({
        sourceHashSha1:
          platform === "gcfv1"
            ? sourceContract.sourceV1HashSha1
            : sourceContract.sourceV2HashSha1,
        environmentVariables: backendEnvironment,
        secretVersions,
      }),
      environmentVariables: {
        ...endpointEnvironment,
        FUNCTION_TARGET: id,
      },
      secretEnvironmentVariables,
    };
  });
  let invocation;
  const readback = await collectCatalogFunctionReadback(
    {
      lane: "controlled-delivery-enable",
      validated,
      candidateSourceContract: sourceContract,
    },
    {
      execFileImpl: async (command, args, options) => {
        invocation = { command, args, options };
        return {
          stdout: JSON.stringify({ status: "success", result: endpoints }),
        };
      },
    },
  );
  assert.equal(readback.environmentMatches, true);
  assert.equal(readback.functionCount, 5);
  assert.equal(readback.region, "us-central1");
  assert.match(readback.environmentDigestSha256, /^[a-f0-9]{64}$/);
  assert.equal(
    readback.environmentDigestSha256,
    readback.expectedEnvironmentDigestSha256,
  );
  assert.equal(readback.secretReferencesMatch, true);
  assert.match(readback.buildIdentitySetSha256, /^[a-f0-9]{64}$/);
  assert.doesNotMatch(JSON.stringify(readback), /merchant_alpha|merchant_beta/);
  assert.doesNotMatch(JSON.stringify(readback), new RegExp("1{64}|2{64}"));
  assert.equal(
    endpoints.some((endpoint) =>
      JSON.stringify(readback).includes(endpoint.hash),
    ),
    false,
  );
  assert.doesNotMatch(
    JSON.stringify(readback),
    /sourceUploadUrl|signed-source/,
  );
  assert.deepEqual(invocation.args.slice(0, 6), [
    "--project",
    PRODUCTION_FIREBASE_PROJECT_ID,
    "--account",
    PRODUCTION_FIREBASE_ACCOUNT,
    "--non-interactive",
    "--json",
  ]);
  assert.equal(invocation.options.env.META_WHATSAPP_ACCESS_TOKEN, undefined);

  for (const mutate of [
    (entry) => {
      delete entry.projectId;
    },
    (entry) => {
      entry.projectId = PRODUCTION_FIREBASE_PROJECT_ID;
    },
    (entry) => {
      entry.projectId = "999999999999";
    },
    (entry) => {
      entry.secret = `projects/${PRODUCTION_FIREBASE_PROJECT_ID}/secrets/${entry.key}`;
    },
  ]) {
    const changed = structuredClone(endpoints);
    mutate(changed[0].secretEnvironmentVariables[0]);
    const rejectedSecretIdentity = await collectCatalogFunctionReadback(
      {
        lane: "controlled-delivery-enable",
        validated,
        candidateSourceContract: sourceContract,
      },
      {
        execFileImpl: async () => ({ stdout: JSON.stringify(changed) }),
      },
    );
    assert.equal(rejectedSecretIdentity.secretReferencesMatch, false);
    assert.equal(rejectedSecretIdentity.environmentMatches, false);
  }

  endpoints[0].environmentVariables.WHATSAPP_PRODUCT_LIST_ENABLED = "false";
  const drifted = await collectCatalogFunctionReadback(
    {
      lane: "controlled-delivery-enable",
      validated,
      candidateSourceContract: sourceContract,
    },
    {
      execFileImpl: async () => ({ stdout: JSON.stringify(endpoints) }),
    },
  );
  assert.equal(drifted.environmentMatches, false);

  endpoints[0].environmentVariables.WHATSAPP_PRODUCT_LIST_ENABLED = "true";
  endpoints[0].environmentVariables.UNEXPECTED_USER_ENV = "forbidden";
  endpoints[1].secretEnvironmentVariables.push({
    key: "UNEXPECTED_SECRET",
    secret: "UNEXPECTED_SECRET",
    version: "latest",
  });
  const unexpected = await collectCatalogFunctionReadback(
    {
      lane: "controlled-delivery-enable",
      validated,
      candidateSourceContract: sourceContract,
    },
    {
      execFileImpl: async () => ({ stdout: JSON.stringify(endpoints) }),
    },
  );
  assert.equal(unexpected.environmentMatches, false);

  delete endpoints[0].environmentVariables.UNEXPECTED_USER_ENV;
  endpoints[0].environmentVariables.MALFORMED_USER_ENV = 7;
  endpoints[1].secretEnvironmentVariables.pop();
  endpoints[1].secretEnvironmentVariables = { malformed: true };
  const malformed = await collectCatalogFunctionReadback(
    {
      lane: "controlled-delivery-enable",
      validated,
      candidateSourceContract: sourceContract,
    },
    {
      execFileImpl: async () => ({ stdout: JSON.stringify(endpoints) }),
    },
  );
  assert.equal(malformed.environmentShapesValid, false);
  assert.equal(malformed.environmentMatches, false);

  endpoints[0].environmentVariables.MALFORMED_USER_ENV = "restored";
  endpoints[1].secretEnvironmentVariables = NATIVE_CATALOG_FUNCTION_SECRET_REFS[
    endpoints[1].id
  ].map((key, secretIndex) => ({
    key,
    projectId: PRODUCTION_FIREBASE_PROJECT_NUMBER,
    secret: key,
    version: String(secretIndex + 1),
  }));
  delete endpoints[0].hash;
  const missingProviderBuildIdentity = await collectCatalogFunctionReadback(
    {
      lane: "controlled-delivery-enable",
      validated,
      candidateSourceContract: sourceContract,
    },
    { execFileImpl: async () => ({ stdout: JSON.stringify(endpoints) }) },
  );
  assert.equal(missingProviderBuildIdentity.buildIdentitiesComplete, false);
  assert.equal(missingProviderBuildIdentity.buildIdentitySetSha256, null);
  assert.equal(missingProviderBuildIdentity.environmentMatches, false);
});

test("function readback accepts Firebase's omitted empty secret list and still rejects missing required secrets", async () => {
  const validated = validateCatalogDeploymentDotenv({
    lane: "dark-new",
    text: validDotenv("dark-new"),
    appCommit: commit,
  });
  const environmentVariables = Object.fromEntries(
    parseStrictDotenv(validated.normalized),
  );
  const sourceContract = candidateSourceContractFixture();
  const firebaseConfig = JSON.stringify({
    projectId: PRODUCTION_FIREBASE_PROJECT_ID,
    storageBucket: "pasella-ledger.appspot.com",
  });
  const endpoints = NATIVE_CATALOG_NEW_FUNCTIONS.map((id) => {
    const backendEnvironment = {
      ...environmentVariables,
      FIREBASE_CONFIG: firebaseConfig,
      GCLOUD_PROJECT: PRODUCTION_FIREBASE_PROJECT_ID,
    };
    const secretEnvironmentVariables = NATIVE_CATALOG_FUNCTION_SECRET_REFS[
      id
    ].map((key, secretIndex) => ({
      key,
      projectId: PRODUCTION_FIREBASE_PROJECT_NUMBER,
      secret: key,
      version: String(secretIndex + 1),
    }));
    return {
      ...remoteBuildIdentity(id, "gcfv1"),
      hash: firebaseEndpointHashSha1({
        sourceHashSha1: sourceContract.sourceV1HashSha1,
        environmentVariables: backendEnvironment,
        secretVersions: Object.fromEntries(
          secretEnvironmentVariables.map(({ key, version }) => [key, version]),
        ),
      }),
      environmentVariables: {
        ...backendEnvironment,
        FUNCTION_TARGET: id,
        EVENTARC_CLOUD_EVENT_SOURCE: `projects/${PRODUCTION_FIREBASE_PROJECT_ID}/locations/us-central1/functions/${id}`,
      },
      ...(secretEnvironmentVariables.length === 0
        ? {}
        : { secretEnvironmentVariables }),
    };
  });

  const accepted = await collectCatalogFunctionReadback(
    {
      lane: "dark-new",
      validated,
      candidateSourceContract: sourceContract,
    },
    { execFileImpl: async () => ({ stdout: JSON.stringify(endpoints) }) },
  );
  assert.equal(accepted.secretReferencesMatch, true);
  assert.equal(accepted.environmentMatches, true);

  const missingRequired = structuredClone(endpoints);
  const requiresSecret = missingRequired.find(
    (endpoint) =>
      NATIVE_CATALOG_FUNCTION_SECRET_REFS[endpoint.id].length > 0,
  );
  delete requiresSecret.secretEnvironmentVariables;
  const rejectedRequired = await collectCatalogFunctionReadback(
    {
      lane: "dark-new",
      validated,
      candidateSourceContract: sourceContract,
    },
    { execFileImpl: async () => ({ stdout: JSON.stringify(missingRequired) }) },
  );
  assert.equal(rejectedRequired.secretReferencesMatch, false);
  assert.equal(rejectedRequired.environmentMatches, false);

  const malformedEmpty = structuredClone(endpoints);
  const expectsNoSecret = malformedEmpty.find(
    (endpoint) =>
      NATIVE_CATALOG_FUNCTION_SECRET_REFS[endpoint.id].length === 0,
  );
  expectsNoSecret.secretEnvironmentVariables = null;
  const rejectedMalformedEmpty = await collectCatalogFunctionReadback(
    {
      lane: "dark-new",
      validated,
      candidateSourceContract: sourceContract,
    },
    { execFileImpl: async () => ({ stdout: JSON.stringify(malformedEmpty) }) },
  );
  assert.equal(rejectedMalformedEmpty.environmentShapesValid, false);
  assert.equal(rejectedMalformedEmpty.environmentMatches, false);
});

test("existing-function readback permits only the exact catalog hash-key secret migration", async () => {
  const sourceContract = candidateSourceContractFixture();
  const firebaseConfig = JSON.stringify({
    projectId: PRODUCTION_FIREBASE_PROJECT_ID,
    storageBucket: "pasella-ledger.appspot.com",
  });
  const endpoints = NATIVE_CATALOG_EXISTING_FUNCTIONS.map((id) => {
    const platform = "gcfv1";
    const backendEnvironment = {
      FIREBASE_CONFIG: firebaseConfig,
      GCLOUD_PROJECT: PRODUCTION_FIREBASE_PROJECT_ID,
    };
    const environmentVariables = {
      EXISTING_NON_SECRET_SETTING: `value-${id}`,
      ...backendEnvironment,
      EVENTARC_CLOUD_EVENT_SOURCE: `projects/${PRODUCTION_FIREBASE_PROJECT_ID}/locations/us-central1/functions/${id}`,
    };
    const secretEnvironmentVariables =
      NATIVE_CATALOG_EXISTING_FUNCTION_SECRET_REFS[id].map(
        (key, secretIndex) => ({
          key,
          projectId: PRODUCTION_FIREBASE_PROJECT_NUMBER,
          secret: key,
          version: String(secretIndex + 1),
        }),
      );
    return {
      ...remoteBuildIdentity(id, platform),
      environmentVariables,
      secretEnvironmentVariables,
      hash: firebaseEndpointHashSha1({
        sourceHashSha1: sourceContract.sourceV1HashSha1,
        environmentVariables: backendEnvironment,
        secretVersions: Object.fromEntries(
          secretEnvironmentVariables.map(({ key, version }) => [key, version]),
        ),
      }),
    };
  });
  const preDeployEndpoints = structuredClone(endpoints);
  const migrationEndpoint = preDeployEndpoints.find(
    (endpoint) => endpoint.id === "getMerchantCatalogBotHttp",
  );
  migrationEndpoint.secretEnvironmentVariables =
    migrationEndpoint.secretEnvironmentVariables.filter(
      (entry) => entry.key !== "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
    );
  const existingEnvironmentBaselines = Object.fromEntries(
    preDeployEndpoints.map((endpoint) => [
      endpoint.id,
      {
        environmentVariables: { ...endpoint.environmentVariables },
        secretEnvironmentVariables: endpoint.secretEnvironmentVariables.map(
          (entry) => ({ ...entry }),
        ),
      },
    ]),
  );
  const preDeployExec = async () => ({
    stdout: JSON.stringify(preDeployEndpoints),
  });
  const before = await collectCatalogFunctionReadback(
    { lane: "existing-code", validated: null },
    { execFileImpl: preDeployExec },
  );
  const baseline = verifyExistingCodeEnvironmentBaseline({
    functionNames: NATIVE_CATALOG_EXISTING_FUNCTIONS,
    existingEnvironmentBaselines,
  });
  assert.equal(baseline.baselineMatches, true);
  assert.equal(
    baseline.transitionMode,
    "exact_catalog_recipient_hash_secret_addition",
  );
  assert.equal(
    baseline.preDeployEnvironmentDigestSha256,
    before.environmentDigestSha256,
  );
  for (const mutate of [
    (rows) => {
      delete rows.getMerchantCatalogBotHttp.secretEnvironmentVariables[0]
        .projectId;
    },
    (rows) => {
      rows.getMerchantCatalogBotHttp.secretEnvironmentVariables[0].projectId =
        PRODUCTION_FIREBASE_PROJECT_ID;
    },
    (rows) => {
      rows.getMerchantCatalogBotHttp.secretEnvironmentVariables[0].projectId =
        "999999999999";
    },
    (rows) => {
      rows.checkoutCart.secretEnvironmentVariables.push({
        key: "UNEXPECTED_SECRET",
        projectId: PRODUCTION_FIREBASE_PROJECT_NUMBER,
        secret: "UNEXPECTED_SECRET",
        version: "1",
      });
    },
  ]) {
    const changed = structuredClone(existingEnvironmentBaselines);
    mutate(changed);
    assert.equal(
      verifyExistingCodeEnvironmentBaseline({
        functionNames: NATIVE_CATALOG_EXISTING_FUNCTIONS,
        existingEnvironmentBaselines: changed,
      }).baselineMatches,
      false,
    );
  }
  const execFileImpl = async () => ({ stdout: JSON.stringify(endpoints) });
  const after = await collectCatalogFunctionReadback(
    {
      lane: "existing-code",
      validated: null,
      expectedPreservationDigestSha256: before.environmentDigestSha256,
      candidateSourceContract: sourceContract,
      existingEnvironmentBaselines,
    },
    { execFileImpl },
  );
  assert.equal(after.environmentMatches, true);
  assert.equal(
    after.environmentTransitionMode,
    "exact_catalog_recipient_hash_secret_addition",
  );
  assert.match(after.environmentTransitionDigestSha256, /^[a-f0-9]{64}$/);
  assert.notEqual(after.environmentDigestSha256, before.environmentDigestSha256);
  assert.equal(
    after.expectedEnvironmentDigestSha256,
    after.environmentDigestSha256,
  );
  assert.doesNotMatch(JSON.stringify(after), /value-getMerchantCatalogBotHttp/);
  assert.doesNotMatch(JSON.stringify(after), /existing-secret-resource/);

  const preservedBaselines = Object.fromEntries(
    endpoints.map((endpoint) => [
      endpoint.id,
      {
        environmentVariables: { ...endpoint.environmentVariables },
        secretEnvironmentVariables: endpoint.secretEnvironmentVariables.map(
          (entry) => ({ ...entry }),
        ),
      },
    ]),
  );
  const preservedBefore = await collectCatalogFunctionReadback(
    { lane: "existing-code", validated: null },
    { execFileImpl },
  );
  const preserved = verifyExistingCodeEnvironmentTransition({
    functionNames: NATIVE_CATALOG_EXISTING_FUNCTIONS,
    existingEnvironmentBaselines: preservedBaselines,
    endpoints,
    expectedPreDeployEnvironmentDigestSha256:
      preservedBefore.environmentDigestSha256,
  });
  assert.equal(preserved.transitionMatches, true);
  assert.equal(preserved.transitionMode, "exact_environment_preservation");

  for (const mutate of [
    (rows) => {
      rows.find(
        (endpoint) => endpoint.id === "getMerchantCatalogBotHttp",
      ).environmentVariables.UNEXPECTED_USER_ENV = "changed";
    },
    (rows) => {
      rows.find(
        (endpoint) => endpoint.id === "getMerchantCatalogBotHttp",
      ).secretEnvironmentVariables.find(
        (entry) => entry.key === "PASELLA_BOT_TOKEN",
      ).version = "99";
    },
    (rows) => {
      rows.find(
        (endpoint) => endpoint.id === "checkoutCart",
      ).secretEnvironmentVariables.push({
        key: "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
        projectId: PRODUCTION_FIREBASE_PROJECT_NUMBER,
        secret: "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
        version: "1",
      });
    },
    (rows) => {
      rows.find(
        (endpoint) => endpoint.id === "getMerchantCatalogBotHttp",
      ).secretEnvironmentVariables.find(
        (entry) => entry.key === "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
      ).secret = "projects/pasella-ledger/secrets/WRONG_SECRET";
    },
    (rows) => {
      rows.find(
        (endpoint) => endpoint.id === "getMerchantCatalogBotHttp",
      ).secretEnvironmentVariables.find(
        (entry) => entry.key === "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
      ).projectId = "999999999999";
    },
    (rows) => {
      const endpoint = rows.find(
        (candidate) => candidate.id === "getMerchantCatalogBotHttp",
      );
      endpoint.secretEnvironmentVariables =
        endpoint.secretEnvironmentVariables.filter(
          (entry) => entry.key !== "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
        );
    },
  ]) {
    const changed = structuredClone(endpoints);
    mutate(changed);
    const rejected = verifyExistingCodeEnvironmentTransition({
      functionNames: NATIVE_CATALOG_EXISTING_FUNCTIONS,
      existingEnvironmentBaselines,
      endpoints: changed,
      expectedPreDeployEnvironmentDigestSha256:
        before.environmentDigestSha256,
    });
    assert.equal(rejected.transitionMatches, false);
  }
});

test("source dotenv guard permits only the checked example", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "catalog-env-guard-"));
  try {
    await writeFile(path.join(directory, ".env.example"), "example=true\n");
    await assertNoSourceDeploymentDotenv(directory);
    await writeFile(
      path.join(directory, ".env.pasella-ledger"),
      "unsafe=true\n",
    );
    await assert.rejects(
      assertNoSourceDeploymentDotenv(directory),
      (error) => error.code === "SOURCE_DEPLOYMENT_DOTENV_PRESENT",
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("ephemeral Firebase config preserves the checked predeploy gates", () => {
  const config = buildEphemeralFirebaseConfig({
    functionsDirectory: "/authority/functions",
    configDir: "/private/tmp/catalog-config",
  });
  assert.deepEqual(config.functions[0].predeploy, [
    'npm --prefix "$RESOURCE_DIR" run lint',
    'npm --prefix "$RESOURCE_DIR" run build',
  ]);
  assert.equal(config.functions[0].source, "/authority/functions");
  assert.equal(config.functions[0].configDir, "/private/tmp/catalog-config");
});

test("Firestore policy source contracts pin exact rules and TTL selectors", async () => {
  assert.deepEqual(CATALOG_POLICY_LANES, [
    "firestore-rules",
    "firestore-indexes",
  ]);
  const rules = await catalogPolicySourceContract("firestore-rules");
  assert.equal(rules.selector, "firestore:rules");
  assert.equal(rules.sourcePath, "firestore.rules");
  assert.match(rules.sourceSha256, /^[a-f0-9]{64}$/);

  const indexes = await catalogPolicySourceContract("firestore-indexes");
  assert.equal(indexes.selector, "firestore:indexes");
  assert.equal(indexes.databaseId, PRODUCTION_FIRESTORE_DATABASE_ID);
  assert.equal(indexes.ttlFieldCount, REQUIRED_CATALOG_TTL_FIELDS.length);
  assert.ok(indexes.indexCount > 0);
  assert.ok(indexes.fieldOverrideCount >= REQUIRED_CATALOG_TTL_FIELDS.length);
  assert.match(indexes.fullIndexConfigurationDigestSha256, /^[a-f0-9]{64}$/);
  assert.equal(
    indexes.ttlContractDigestSha256,
    createHash("sha256")
      .update([...REQUIRED_CATALOG_TTL_FIELDS].sort().join("\n"))
      .digest("hex"),
  );
  assert.deepEqual(
    codexGuardDeployArguments({ lane: "firestore-rules", dryRun: true }).slice(
      -2,
    ),
    ["--only", "firestore:rules"],
  );
  assert.deepEqual(
    parseDeploymentGuardArguments([
      "--lane",
      "firestore-indexes",
      "--expected-app-commit",
      commit,
      "--expected-current-main-commit",
      FROZEN_APP_MAIN_COMMIT,
      "--readback-only",
    ]),
    {
      lane: "firestore-indexes",
      expectedAppCommit: commit,
      expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
      dryRun: true,
      execute: false,
      receiptPath: null,
      candidateManifestPath: null,
      expectedCandidateManifestSha256: null,
      readbackOnly: true,
    },
  );
});

test("Firestore index readback verifies exact project, database, and active TTLs", async () => {
  const calls = [];
  const remoteIndexDocument = JSON.parse(
    await readFile(path.resolve("../firestore.indexes.json"), "utf8"),
  );
  const ttlRows = REQUIRED_CATALOG_TTL_FIELDS.map((field) => {
    const [collectionGroup, fieldPath] = field.split("/");
    return {
      name: `projects/${PRODUCTION_FIREBASE_PROJECT_ID}/databases/${PRODUCTION_FIRESTORE_DATABASE_ID}/collectionGroups/${collectionGroup}/fields/${fieldPath}`,
      ttlConfig: { state: "ACTIVE" },
    };
  });
  const result = await collectCatalogPolicyReadback("firestore-indexes", {
    execFileImpl: async (command, args, options) => {
      calls.push({ command, args, options });
      if (command === "/opt/homebrew/bin/firebase") {
        return {
          stdout: JSON.stringify(remoteIndexDocument),
        };
      }
      return { stdout: JSON.stringify(ttlRows) };
    },
  });
  assert.equal(result.databaseId, PRODUCTION_FIRESTORE_DATABASE_ID);
  assert.equal(result.remoteTtlFieldCount, 3);
  assert.equal(result.remoteIndexCount, remoteIndexDocument.indexes.length);
  assert.equal(
    result.remoteFieldOverrideCount,
    remoteIndexDocument.fieldOverrides.length,
  );
  assert.equal(result.ttlActive, true);
  assert.equal(result.ttlActiveCount, 3);
  assert.deepEqual(calls[0].args.slice(0, 4), [
    "--project",
    PRODUCTION_FIREBASE_PROJECT_ID,
    "--account",
    PRODUCTION_FIREBASE_ACCOUNT,
  ]);
  assert.ok(calls[0].args.includes(PRODUCTION_FIRESTORE_DATABASE_ID));
  assert.ok(
    calls[1].args.includes(`--database=${PRODUCTION_FIRESTORE_DATABASE_ID}`),
  );
  assert.ok(
    calls.every(
      (call) => call.options.env.META_CATALOG_ACCESS_TOKEN === undefined,
    ),
  );
});
