import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  link,
  lstat,
  mkdtemp,
  open,
  readFile,
  realpath,
  rm,
  unlink,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import * as receiptModule from "../scripts/production-write-receipt.mjs";
import {
  PINNED_NODE_RUNTIME,
  PINNED_FIREBASE_CLI,
  PINNED_GCLOUD_CLI,
  ProductionReceiptError,
  appCommitSourceSha256,
  assertPinnedProductionToolchain,
  buildNeedsReviewProductionWriteReceipt,
  canonicalJson,
  canonicalSha256,
  persistNeedsReviewProductionWriteReceipt,
  validateProductionWriteReceipt,
} from "../scripts/production-write-receipt.mjs";
import {
  FROZEN_APP_MAIN_COMMIT,
  canonicalProductionCandidateManifestBytes,
} from "../scripts/production-candidate-manifest.mjs";
import {
  PRODUCTION_NATIVE_CATALOG_TARGET,
  nativeCatalogTargetConfigurationDigestSha256,
} from "../scripts/whatsapp-catalog-production-target.mjs";

const commit = "c".repeat(40);
const sourceSha256 = appCommitSourceSha256(commit);
const operationInputSha256 = "4".repeat(64);
const actionAuthorizationSha256 = "5".repeat(64);
const actionAuthorizationClaimSha256 = "6".repeat(64);
const selector = [
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
]
  .map((name) => `functions:${name}`)
  .join(",");

function candidateManifest(input) {
  return {
    schemaVersion: 1,
    kind: "spazaone_native_catalog_production_candidate",
    appCommit: input.appCommit,
    governedMainCommit: FROZEN_APP_MAIN_COMMIT,
    gitTreeSha1: "e".repeat(40),
    immutableTargetConfigurationSha256:
      nativeCatalogTargetConfigurationDigestSha256(),
    operation: {
      kind: "function_deployment",
      lane: input.lane,
      selector: input.selector,
      inputSha256: input.operationInputSha256,
    },
    receipts: {
      appBuildLintReceiptSha256: "1".repeat(64),
      appWhatsAppCatalogTestsReceiptSha256: "2".repeat(64),
      independentProductionReviewReceiptSha256: "3".repeat(64),
    },
  };
}

function manifestDigest(document) {
  return createHash("sha256")
    .update(canonicalProductionCandidateManifestBytes(document))
    .digest("hex");
}

function rawFunctionEvidence() {
  const environmentDigestSha256 = "6".repeat(64);
  const environmentTransitionMode = "configured_exact";
  return {
    kind: "function_deployment",
    lane: "dark-new",
    selector,
    firebaseProjectId: "pasella-ledger",
    region: "us-central1",
    functionCount: selector.split(",").length,
    buildIdentitiesComplete: true,
    buildIdentitySetSha256: "f".repeat(64),
    environmentShapesValid: true,
    environmentMatches: true,
    secretReferencesMatch: true,
    environmentDigestSha256,
    expectedEnvironmentDigestSha256: environmentDigestSha256,
    environmentTransitionMode,
    preDeployEnvironmentDigestSha256: null,
    environmentTransitionDigestSha256: createHash("sha256")
      .update(
        JSON.stringify([
          environmentTransitionMode,
          null,
          environmentDigestSha256,
        ]),
      )
      .digest("hex"),
    candidateSourceBindingMatches: true,
    candidateSourceContractSha256: "7".repeat(64),
    candidateSourceFileCount: 400,
    candidateGeneratedFileCount: 324,
    candidateProviderBindingSetSha256: "8".repeat(64),
  };
}

function finalizedReconciliationArtifact() {
  const artifact = {
    schemaVersion: 1,
    kind: "spazaone_catalog_full_reconciliation",
    verifiedAt: "2026-08-28T09:30:00.000Z",
    startedAt: "2026-08-28T09:00:00.000Z",
    completedAt: "2026-08-28T09:29:00.000Z",
    firebaseProjectId: "pasella-ledger",
    catalogId: PRODUCTION_NATIVE_CATALOG_TARGET.catalogId,
    senderPhoneNumberId: PRODUCTION_NATIVE_CATALOG_TARGET.senderPhoneNumberId,
    appCommit: commit,
    targetConfigurationDigestSha256:
      nativeCatalogTargetConfigurationDigestSha256(),
    cycleId: "a".repeat(32),
    deliveryEnabled: false,
    syncEnabled: true,
    scanScope: "all_eligible_merchants",
    cycleComplete: true,
    productScanComplete: true,
    mappingScanComplete: true,
    stabilityVerified: true,
    sourceCountsVerified: true,
    outboxDrained: true,
    outboxPendingCount: 0,
    outboxRetryCount: 0,
    outboxProcessingCount: 0,
    outboxSubmittedCount: 0,
    outboxActiveCount: 7,
    outboxDeletedCount: 2,
    outboxRejectedCount: 0,
    outboxUnknownCount: 0,
    outboxTotalCount: 9,
    outboxCountsVerified: true,
    catalogComplete: true,
    setEqualityVerified: true,
    mutationGenerationDigestSha256: "a".repeat(64),
    completionDigest: "b".repeat(64),
    incompleteMerchantCount: 0,
    malformedMappingCount: 0,
  };
  return {
    ...artifact,
    redactedReceiptSha256: canonicalSha256(artifact),
  };
}

function reconciliationNeedsReviewInput() {
  const input = needsReviewInput({
    kind: "spazaone_catalog_full_reconciliation",
    lane: "full-reconciliation",
    selector: "functions:runWhatsAppCatalogFullReconciliationBotHttp",
    cleanupStatus: "not_applicable",
    remoteEvidence: {
      kind: "full_reconciliation",
      artifact: finalizedReconciliationArtifact(),
    },
  });
  input.candidateManifest.operation = {
    kind: "full_reconciliation",
    lane: input.lane,
    selector: input.selector,
    inputSha256: input.operationInputSha256,
  };
  input.candidateManifestSha256 = manifestDigest(input.candidateManifest);
  return input;
}

function needsReviewInput(overrides = {}) {
  const input = {
    kind: "spazaone_catalog_function_deployment",
    outcome: "needs_review",
    actionStartedAt: "2026-08-28T10:00:00.000Z",
    dispatchStartedAt: "2026-08-28T10:00:01.000Z",
    actionCompletedAt: "2026-08-28T10:00:02.000Z",
    verifiedAt: "2026-08-28T10:00:03.000Z",
    appCommit: commit,
    lane: "dark-new",
    selector,
    sourceSha256,
    configurationSha256: nativeCatalogTargetConfigurationDigestSha256(),
    operationInputSha256,
    actionAuthorizationSha256,
    actionAuthorizationClaimSha256,
    commandExitZero: false,
    readbackStatus: "needs_review",
    cleanupStatus: "deleted",
    remoteEvidence: null,
    errorCode: "CATALOG_DEPLOY_EXECUTION_NEEDS_REVIEW",
    ...overrides,
  };
  if (!Object.hasOwn(overrides, "candidateManifest")) {
    input.candidateManifest = candidateManifest(input);
  }
  if (!Object.hasOwn(overrides, "candidateManifestSha256")) {
    input.candidateManifestSha256 = manifestDigest(input.candidateManifest);
  }
  return input;
}

function structurallyValidButUnattestedVerifiedReceipt() {
  const receipt = buildNeedsReviewProductionWriteReceipt(
    needsReviewInput({ remoteEvidence: rawFunctionEvidence() }),
  );
  const forged = structuredClone(receipt);
  forged.outcome = "verified";
  forged.needsReview = false;
  forged.result.commandExitZero = true;
  forged.result.readbackStatus = "verified";
  forged.result.providerScratchEvidence = {
    inventorySha256: "f".repeat(64),
    entryCount: 3,
    totalBytes: 4_096,
  };
  forged.result.errorCode = null;
  delete forged.redactedReceiptSha256;
  forged.redactedReceiptSha256 = canonicalSha256(forged);
  return forged;
}

test("disabled executors expose no verified receipt constructor or persister", () => {
  assert.equal(receiptModule.buildProductionWriteReceipt, undefined);
  assert.equal(receiptModule.sealProductionWriteReceipt, undefined);
  assert.equal(receiptModule.persistProductionWriteReceipt, undefined);
  assert.equal(
    typeof receiptModule.buildNeedsReviewProductionWriteReceipt,
    "function",
  );
  assert.equal(
    typeof receiptModule.persistNeedsReviewProductionWriteReceipt,
    "function",
  );

  assert.throws(
    () =>
      buildNeedsReviewProductionWriteReceipt(
        needsReviewInput({ outcome: "verified" }),
      ),
    (error) =>
      error instanceof ProductionReceiptError &&
      error.code === "PRODUCTION_RECEIPT_ATTESTATION_REQUIRED",
  );
});

test("needs-review receipt is closed, redacted, sealed, and never retryable", () => {
  const receipt = buildNeedsReviewProductionWriteReceipt(needsReviewInput());
  assert.deepEqual(validateProductionWriteReceipt(receipt), {
    structurallyValid: true,
    outcome: "needs_review",
  });
  assert.equal(receipt.remoteWriteAttempted, true);
  assert.deepEqual(receipt.lineage, {
    mode: "direct_write",
    priorReceiptSha256: null,
  });
  assert.equal(receipt.needsReview, true);
  assert.equal(receipt.retryAllowed, false);
  assert.equal(receipt.result.remoteEvidence, null);
  assert.equal(receipt.result.providerScratchEvidence, null);
  assert.equal(receipt.target.firebaseProjectId, "pasella-ledger");
  assert.equal(receipt.authority.repository, "Vox-Dei-Build/spazaone-app");
  assert.equal(
    receipt.operation.actionAuthorizationSha256,
    actionAuthorizationSha256,
  );
  assert.equal(
    receipt.operation.actionAuthorizationClaimSha256,
    actionAuthorizationClaimSha256,
  );
  assert.equal(receipt.operation.operatorAuditOnly, true);
  assert.match(receipt.redactedReceiptSha256, /^[a-f0-9]{64}$/);
});

test("provider scratch audit evidence is redacted and bounded", () => {
  const receipt = structurallyValidButUnattestedVerifiedReceipt();
  assert.deepEqual(receipt.result.providerScratchEvidence, {
    inventorySha256: "f".repeat(64),
    entryCount: 3,
    totalBytes: 4_096,
  });

  for (const providerScratchEvidence of [
    {
      inventorySha256: "invalid",
      entryCount: 3,
      totalBytes: 4_096,
    },
    {
      inventorySha256: "f".repeat(64),
      entryCount: 2_049,
      totalBytes: 4_096,
    },
    {
      inventorySha256: "f".repeat(64),
      entryCount: 3,
      totalBytes: 256 * 1024 * 1024 + 1,
    },
  ]) {
    const invalid = structuredClone(receipt);
    invalid.result.providerScratchEvidence = providerScratchEvidence;
    delete invalid.redactedReceiptSha256;
    invalid.redactedReceiptSha256 = canonicalSha256(invalid);
    assert.throws(() => validateProductionWriteReceipt(invalid));
  }
});

test("caller action receipt digests remain operator audit only", () => {
  const missing = needsReviewInput();
  delete missing.actionAuthorizationSha256;
  assert.throws(
    () => buildNeedsReviewProductionWriteReceipt(missing),
    (error) =>
      error instanceof ProductionReceiptError &&
      error.code === "PRODUCTION_RECEIPT_INPUT_KEYSET_INVALID",
  );
  const missingClaim = needsReviewInput();
  delete missingClaim.actionAuthorizationClaimSha256;
  assert.throws(
    () => buildNeedsReviewProductionWriteReceipt(missingClaim),
    (error) =>
      error instanceof ProductionReceiptError &&
      error.code === "PRODUCTION_RECEIPT_INPUT_KEYSET_INVALID",
  );
  assert.throws(
    () =>
      buildNeedsReviewProductionWriteReceipt(
        needsReviewInput({ actionAuthorizationSha256: "invalid" }),
      ),
    (error) =>
      error instanceof ProductionReceiptError &&
      error.code === "ACTION_AUTHORIZATION_SHA256_INVALID",
  );
});

test("structural validation is not production attestation", async () => {
  const forged = structurallyValidButUnattestedVerifiedReceipt();
  assert.deepEqual(validateProductionWriteReceipt(forged), {
    structurallyValid: true,
    outcome: "verified",
  });
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "unattested-receipt-")),
  );
  const receiptPath = path.join(root, "receipt.json");
  try {
    await assert.rejects(
      persistNeedsReviewProductionWriteReceipt(forged, receiptPath),
      (error) =>
        error instanceof ProductionReceiptError &&
        error.code === "PRODUCTION_RECEIPT_ATTESTATION_REQUIRED",
    );
    await assert.rejects(lstat(receiptPath), { code: "ENOENT" });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("receipt persistence snapshots input and rejects proxy/getter time-of-check drift", async () => {
  const receipt = buildNeedsReviewProductionWriteReceipt(needsReviewInput());
  const proxy = new Proxy(receipt, {
    get(target, property, receiver) {
      return Reflect.get(target, property, receiver);
    },
  });
  await assert.rejects(
    persistNeedsReviewProductionWriteReceipt(proxy, "/tmp/must-not-exist.json"),
    (error) =>
      error instanceof ProductionReceiptError &&
      error.code === "PRODUCTION_RECEIPT_SNAPSHOT_INVALID",
  );
});

test("candidate manifest and operation binding are still fail-closed", () => {
  const wrongManifest = needsReviewInput();
  wrongManifest.candidateManifest.operation.inputSha256 = "5".repeat(64);
  wrongManifest.candidateManifestSha256 = manifestDigest(
    wrongManifest.candidateManifest,
  );
  assert.throws(
    () => buildNeedsReviewProductionWriteReceipt(wrongManifest),
    (error) =>
      error instanceof ProductionReceiptError &&
      error.code === "PRODUCTION_RECEIPT_CANDIDATE_BINDING_INVALID",
  );
});

test("function receipt evidence cannot omit reviewed candidate source binding", () => {
  const evidence = rawFunctionEvidence();
  delete evidence.candidateSourceContractSha256;
  assert.throws(
    () =>
      buildNeedsReviewProductionWriteReceipt(
        needsReviewInput({ remoteEvidence: evidence }),
      ),
    (error) =>
      error instanceof ProductionReceiptError &&
      error.code === "FUNCTION_REMOTE_EVIDENCE_KEYSET_INVALID",
  );
});

test("existing-code receipt binds the exact pre-to-post secret migration", () => {
  const existingSelector = [
    "getMerchantCatalogBotHttp",
    "checkoutCart",
    "cancelOrder",
    "finalizeOnlinePaid",
    "updateOrderPayment",
  ]
    .map((name) => `functions:${name}`)
    .join(",");
  const preDeployEnvironmentDigestSha256 = "9".repeat(64);
  const postDeployEnvironmentDigestSha256 = "a".repeat(64);
  const environmentTransitionMode =
    "exact_catalog_recipient_hash_secret_addition";
  const evidence = {
    ...rawFunctionEvidence(),
    lane: "existing-code",
    selector: existingSelector,
    functionCount: 5,
    environmentDigestSha256: postDeployEnvironmentDigestSha256,
    expectedEnvironmentDigestSha256: postDeployEnvironmentDigestSha256,
    environmentTransitionMode,
    preDeployEnvironmentDigestSha256,
    environmentTransitionDigestSha256: createHash("sha256")
      .update(
        JSON.stringify([
          environmentTransitionMode,
          preDeployEnvironmentDigestSha256,
          postDeployEnvironmentDigestSha256,
        ]),
      )
      .digest("hex"),
  };
  assert.doesNotThrow(() =>
    buildNeedsReviewProductionWriteReceipt(
      needsReviewInput({
        lane: "existing-code",
        selector: existingSelector,
        remoteEvidence: evidence,
      }),
    ),
  );

  for (const mutation of [
    (value) => {
      value.environmentTransitionMode = "configured_exact";
    },
    (value) => {
      value.preDeployEnvironmentDigestSha256 = null;
    },
    (value) => {
      value.environmentTransitionDigestSha256 = "b".repeat(64);
    },
  ]) {
    const changed = structuredClone(evidence);
    mutation(changed);
    assert.throws(() =>
      buildNeedsReviewProductionWriteReceipt(
        needsReviewInput({
          lane: "existing-code",
          selector: existingSelector,
          remoteEvidence: changed,
        }),
      ),
    );
  }
});

test("needs-review receipt persists with atomic no-replace inode and mode 0600", async () => {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "needs-review-receipt-")),
  );
  try {
    const receipt = buildNeedsReviewProductionWriteReceipt(needsReviewInput());
    const receiptPath = path.join(root, "receipt.json");
    const result = await persistNeedsReviewProductionWriteReceipt(
      receipt,
      receiptPath,
      { uuid: () => "fixed" },
    );
    assert.equal(result.persisted, true);
    assert.equal(result.mode, "0600");
    const stat = await lstat(receiptPath);
    assert.equal(stat.isFile(), true);
    assert.equal(stat.isSymbolicLink(), false);
    assert.equal(stat.mode & 0o777, 0o600);
    assert.equal(stat.nlink, 1);
    assert.equal(
      await readFile(receiptPath, "utf8"),
      `${canonicalJson(receipt)}\n`,
    );
    await assert.rejects(
      persistNeedsReviewProductionWriteReceipt(receipt, receiptPath),
      (error) =>
        error instanceof ProductionReceiptError &&
        error.code === "PRODUCTION_RECEIPT_TARGET_UNSAFE" &&
        error.retryAllowed === false,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("post-link uncertainty remains needs-review and non-retryable", async () => {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "needs-review-uncertain-")),
  );
  try {
    const receipt = buildNeedsReviewProductionWriteReceipt(needsReviewInput());
    const receiptPath = path.join(root, "receipt.json");
    let linked = false;
    await assert.rejects(
      persistNeedsReviewProductionWriteReceipt(receipt, receiptPath, {
        uuid: () => "fixed",
        fsImpl: {
          link: async (...args) => {
            await link(...args);
            linked = true;
          },
          lstat: async (...args) => {
            if (linked && args[0] === receiptPath) {
              throw new Error("simulated post-link uncertainty");
            }
            return lstat(...args);
          },
          open,
          readFile,
          realpath,
          unlink,
        },
      }),
      (error) =>
        error instanceof ProductionReceiptError &&
        error.code === "PRODUCTION_RECEIPT_PERSISTENCE_UNCERTAIN" &&
        error.needsReview === true &&
        error.targetMayExist === true &&
        error.retryAllowed === false,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("production toolchain pins executable identities and explicit account/project", async () => {
  const calls = [];
  const toolchain = await assertPinnedProductionToolchain({
    environment: {
      HOME: process.env.HOME,
      PATH: "/attacker/bin",
      NODE_OPTIONS: "--require=/tmp/forbidden.cjs",
      FIREBASE_TOKEN: "forbidden",
    },
    execFileImpl: async (command, args, options) => {
      calls.push({ command, args, options });
      if (command === PINNED_FIREBASE_CLI.executablePath) {
        if (args[0] === "--version") return { stdout: "15.21.0\n" };
        return {
          stdout: JSON.stringify({ result: [{ projectId: "pasella-ledger" }] }),
        };
      }
      if (args[0] === "version") {
        return { stdout: JSON.stringify({ "Google Cloud SDK": "576.0.0" }) };
      }
      return { stdout: "tsepo.ntsaba@thedelta.io\n" };
    },
  });
  assert.equal(toolchain.firebaseCliVersion, PINNED_FIREBASE_CLI.version);
  assert.equal(toolchain.gcloudCliVersion, PINNED_GCLOUD_CLI.version);
  assert.equal(toolchain.nodeVersion, PINNED_NODE_RUNTIME.version);
  assert.equal(calls.length, 4);
  assert.ok(calls.every((call) => path.isAbsolute(call.command)));
  assert.ok(
    calls.every(
      (call) =>
        call.options.env.NODE_OPTIONS === undefined &&
        call.options.env.FIREBASE_TOKEN === undefined,
    ),
  );
});

test("receipt operation stays bound to the immutable native catalogue target", () => {
  const receipt = buildNeedsReviewProductionWriteReceipt(needsReviewInput());
  assert.equal(
    receipt.operation.configurationSha256,
    nativeCatalogTargetConfigurationDigestSha256(),
  );
  assert.match(PRODUCTION_NATIVE_CATALOG_TARGET.catalogId, /^\d+$/);
  assert.match(PRODUCTION_NATIVE_CATALOG_TARGET.senderPhoneNumberId, /^\d+$/);
});

test("reconciliation provider timestamps are independent from local executor timestamps", () => {
  const receipt = buildNeedsReviewProductionWriteReceipt(
    reconciliationNeedsReviewInput(),
  );
  assert.equal(receipt.actionStartedAt, "2026-08-28T10:00:00.000Z");
  assert.equal(
    receipt.result.remoteEvidence.summary.artifact.startedAt,
    "2026-08-28T09:00:00.000Z",
  );
  assert.deepEqual(validateProductionWriteReceipt(receipt), {
    structurallyValid: true,
    outcome: "needs_review",
  });
});

test("a recovered read-only closure must carry prior ambiguous receipt lineage", () => {
  const base = buildNeedsReviewProductionWriteReceipt(
    reconciliationNeedsReviewInput(),
  );
  const recovered = structuredClone(base);
  recovered.outcome = "recovered_verified";
  recovered.remoteWriteAttempted = false;
  recovered.needsReview = false;
  recovered.lineage = {
    mode: "recovered_readback",
    priorReceiptSha256: "9".repeat(64),
  };
  recovered.result.commandExitZero = null;
  recovered.result.readbackStatus = "verified";
  recovered.result.errorCode = null;
  delete recovered.redactedReceiptSha256;
  recovered.redactedReceiptSha256 = canonicalSha256(recovered);
  assert.deepEqual(validateProductionWriteReceipt(recovered), {
    structurallyValid: true,
    outcome: "recovered_verified",
  });

  const unlinked = structuredClone(recovered);
  unlinked.lineage.priorReceiptSha256 = null;
  delete unlinked.redactedReceiptSha256;
  unlinked.redactedReceiptSha256 = canonicalSha256(unlinked);
  assert.throws(
    () => validateProductionWriteReceipt(unlinked),
    (error) =>
      error instanceof ProductionReceiptError &&
      error.code === "PRODUCTION_RECEIPT_PRIOR_RECEIPT_SHA256_INVALID",
  );
});

test("deployment recovery can close only from exact remote readback with prior lineage", () => {
  const recovered = buildNeedsReviewProductionWriteReceipt(
    needsReviewInput({ remoteEvidence: rawFunctionEvidence() }),
  );
  recovered.outcome = "recovered_verified";
  recovered.remoteWriteAttempted = false;
  recovered.needsReview = false;
  recovered.lineage = {
    mode: "recovered_readback",
    priorReceiptSha256: "a".repeat(64),
  };
  recovered.result.commandExitZero = null;
  recovered.result.readbackStatus = "verified";
  recovered.result.cleanupStatus = "not_applicable";
  recovered.result.errorCode = null;
  delete recovered.redactedReceiptSha256;
  recovered.redactedReceiptSha256 = canonicalSha256(recovered);
  assert.deepEqual(validateProductionWriteReceipt(recovered), {
    structurallyValid: true,
    outcome: "recovered_verified",
  });

  for (const mutation of [
    (receipt) => {
      receipt.lineage.priorReceiptSha256 = null;
    },
    (receipt) => {
      receipt.result.remoteEvidence = null;
    },
    (receipt) => {
      receipt.remoteWriteAttempted = true;
    },
  ]) {
    const invalid = structuredClone(recovered);
    mutation(invalid);
    delete invalid.redactedReceiptSha256;
    invalid.redactedReceiptSha256 = canonicalSha256(invalid);
    assert.throws(() => validateProductionWriteReceipt(invalid));
  }
});
