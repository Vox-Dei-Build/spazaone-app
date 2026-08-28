#!/usr/bin/env node

import {
  execFile as nodeExecFile,
  spawn as nodeSpawn,
} from "node:child_process";
import { createHash } from "node:crypto";
import { fstatSync, readFileSync } from "node:fs";
import { lstat, readFile, realpath } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { promisify } from "node:util";

import {
  CATALOG_FUNCTION_LANES,
  CATALOG_POLICY_LANES,
  NATIVE_CATALOG_EXISTING_FUNCTIONS,
  PRODUCTION_FIREBASE_FUNCTION_REGION,
  PRODUCTION_FIRESTORE_DATABASE_ID,
  REQUIRED_CATALOG_TTL_FIELDS,
  assertNoSourceDeploymentDotenv,
  assertPinnedFirebaseCliEnvironmentPreservation,
  catalogFunctionSelector,
  catalogPolicySourceContract,
  codexGuardDeployArguments,
  collectCatalogFunctionReadback,
  collectCatalogPolicyReadback,
  parseDeploymentGuardArguments,
  validateCatalogDeploymentDotenv,
} from "./guard-whatsapp-catalog-functions-deploy.mjs";
import {
  APP_REPOSITORY_ROOT,
  ReconciliationOperatorError,
  parseRunnerArguments,
  resolveAuthorityAppCommit,
  scrubCredentialEnvironment,
} from "./run-whatsapp-catalog-full-reconciliation.mjs";
import {
  PINNED_FIREBASE_CLI,
  PINNED_NODE_RUNTIME,
  PRODUCTION_WRITE_AUTHORITY,
  PRODUCTION_WRITE_TARGET,
  appCommitSourceSha256,
  assertPinnedProductionToolchain,
  canonicalJson,
  canonicalSha256,
  productionReceiptToolchain,
  validateProductionWriteReceipt,
} from "./production-write-receipt.mjs";
import {
  canonicalProductionCandidateManifestBytes,
  loadAndValidateProductionCandidateManifest,
} from "./production-candidate-manifest.mjs";
import {
  collectFirebaseGen1RuntimeConfigHashSha1,
  computeCandidateFirebaseSourceContract,
} from "./firebase-function-source-binding.mjs";
import { createDurableArtifactTransaction } from "./durable-artifact-transaction.mjs";
import {
  claimProductionActionAuthorization,
  loadProductionActionAuthorization,
} from "./production-action-authorization.mjs";
import {
  createImmutableDeploymentSnapshotBuilder,
  immutableDeploymentSnapshotPath,
  removeImmutableDeploymentSnapshot,
  verifyImmutableDeploymentSnapshot,
} from "./immutable-deployment-snapshot.mjs";
import {
  PRODUCTION_FIREBASE_ACCOUNT,
  PRODUCTION_FIREBASE_PROJECT_ID,
  nativeCatalogTargetConfigurationDigestSha256,
} from "./whatsapp-catalog-production-target.mjs";

const execFile = promisify(nodeExecFile);
const CODEX_GUARD = "/Users/admin/.codex/identity-governance/bin/codex-guard";
const FUNCTIONS_DIRECTORY = path.join(APP_REPOSITORY_ROOT, "functions");
const LEGACY_DEPLOYMENT_SCRIPT = path.join(
  FUNCTIONS_DIRECTORY,
  "scripts/guard-whatsapp-catalog-functions-deploy.mjs",
);
const LEGACY_RECONCILIATION_SCRIPT = path.join(
  FUNCTIONS_DIRECTORY,
  "scripts/run-whatsapp-catalog-full-reconciliation.mjs",
);
const MAX_DOTENV_BYTES = 16 * 1024;
const MAX_READBACK_BYTES = 10 * 1024 * 1024;
const SHA256 = /^[a-f0-9]{64}$/;
const authorityAttestations = new WeakMap();
const CLEAN_LAUNCHER = Object.freeze({
  path: path.join(
    FUNCTIONS_DIRECTORY,
    "scripts/launch-whatsapp-catalog-production.sh",
  ),
  sha256: "c8b035e9da2d88ba7486ab879e2b7077e06b9865b534db800f1f321be04608c3",
  fd: 3,
});

class ProductionExecutorError extends Error {
  constructor(
    code,
    { needsReview = false, targetMayExist = false, cause } = {},
  ) {
    super(code, cause === undefined ? undefined : { cause });
    this.name = "ProductionExecutorError";
    this.code = code;
    this.needsReview = needsReview;
    this.targetMayExist = targetMayExist;
    this.retryAllowed = false;
  }
}

function fail(code, details) {
  throw new ProductionExecutorError(code, details);
}

function assertExecutorActivationAuthorized() {
  // Credential provisioning did not authorize enabling a production write
  // transport. Keep the reviewed body unreachable until a separate change
  // explicitly replaces this hard stop after adversarial review.
  fail("PRODUCTION_EXECUTOR_ACTIVATION_NOT_AUTHORIZED");
}

function assertLiveSessionCapabilityAuthorized() {
  // File hashes and same-owner claim files cannot establish a trusted action
  // origin. Only a separately user-approved, zero-export same-process session
  // launched from the exact reviewed archive may replace this hard stop.
  fail("PRODUCTION_LIVE_SESSION_CAPABILITY_NOT_AUTHORIZED");
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function extractActionAuthorizationArguments(argv) {
  const remaining = [];
  let authorizationPath = "";
  let expectedAuthorizationReceiptSha256 = "";
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const authorizationArgument =
      argument === "--action-authorization-receipt-path" ||
      argument === "--expected-action-authorization-receipt-sha256";
    if (!authorizationArgument) {
      remaining.push(argument);
      continue;
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      fail("PRODUCTION_ACTION_AUTHORIZATION_ARGUMENT_INVALID");
    }
    if (argument === "--action-authorization-receipt-path") {
      if (authorizationPath) {
        fail("PRODUCTION_ACTION_AUTHORIZATION_ARGUMENT_DUPLICATE");
      }
      authorizationPath = value;
    } else {
      if (expectedAuthorizationReceiptSha256) {
        fail("PRODUCTION_ACTION_AUTHORIZATION_ARGUMENT_DUPLICATE");
      }
      expectedAuthorizationReceiptSha256 = value;
    }
    index += 1;
  }
  const execute = remaining.includes("--execute");
  if (
    (!execute && (authorizationPath || expectedAuthorizationReceiptSha256)) ||
    Boolean(authorizationPath) !==
      Boolean(expectedAuthorizationReceiptSha256) ||
    (authorizationPath &&
      (!path.isAbsolute(authorizationPath) ||
        path.resolve(authorizationPath) !== authorizationPath)) ||
    (expectedAuthorizationReceiptSha256 &&
      !SHA256.test(expectedAuthorizationReceiptSha256))
  ) {
    fail("PRODUCTION_ACTION_AUTHORIZATION_ARGUMENT_INVALID");
  }
  return {
    remaining,
    authorizationPath: authorizationPath || null,
    expectedAuthorizationReceiptSha256:
      expectedAuthorizationReceiptSha256 || null,
  };
}

function now() {
  return new Date().toISOString();
}

async function assertCleanLauncherOrigin() {
  let pathBytes;
  let inheritedBytes;
  try {
    const uid = process.geteuid?.();
    const pathStat = await lstat(CLEAN_LAUNCHER.path);
    const resolved = await realpath(CLEAN_LAUNCHER.path);
    const inheritedStat = fstatSync(CLEAN_LAUNCHER.fd);
    pathBytes = await readFile(CLEAN_LAUNCHER.path);
    inheritedBytes = readFileSync(CLEAN_LAUNCHER.fd);
    if (
      process.env.SPAZAONE_PRODUCTION_EXECUTOR_LAUNCHER_PATH !==
        CLEAN_LAUNCHER.path ||
      process.env.SPAZAONE_PRODUCTION_EXECUTOR_LAUNCHER_FD !==
        String(CLEAN_LAUNCHER.fd) ||
      resolved !== CLEAN_LAUNCHER.path ||
      !Number.isSafeInteger(uid) ||
      !pathStat.isFile() ||
      pathStat.isSymbolicLink() ||
      pathStat.uid !== uid ||
      pathStat.nlink !== 1 ||
      (pathStat.mode & 0o022) !== 0 ||
      (pathStat.mode & 0o111) !== 0o111 ||
      inheritedStat.dev !== pathStat.dev ||
      inheritedStat.ino !== pathStat.ino ||
      inheritedStat.uid !== pathStat.uid ||
      !pathBytes.equals(inheritedBytes) ||
      sha256(pathBytes) !== CLEAN_LAUNCHER.sha256
    ) {
      fail("PRODUCTION_EXECUTOR_LAUNCHER_MISMATCH");
    }
  } catch (error) {
    if (error instanceof ProductionExecutorError) throw error;
    fail("PRODUCTION_EXECUTOR_LAUNCHER_REQUIRED");
  } finally {
    pathBytes?.fill?.(0);
    inheritedBytes?.fill?.(0);
  }
}

function cleanExecutorEnvironment() {
  const expected = {
    HOME: "/Users/admin",
    USER: "admin",
    LOGNAME: "admin",
    TMPDIR: "/private/tmp",
    LANG: "C",
    LC_ALL: "C",
    PATH: "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    SPAZAONE_PRODUCTION_EXECUTOR_LAUNCHER_PATH: CLEAN_LAUNCHER.path,
    SPAZAONE_PRODUCTION_EXECUTOR_LAUNCHER_FD: String(CLEAN_LAUNCHER.fd),
  };
  const actualNames = Object.keys(process.env).sort();
  const expectedNames = Object.keys(expected).sort();
  const optionalMacEncoding = "__CF_USER_TEXT_ENCODING";
  const filteredActualNames = actualNames.filter(
    (name) => name !== optionalMacEncoding,
  );
  if (
    canonicalJson(filteredActualNames) !== canonicalJson(expectedNames) ||
    expectedNames.some((name) => process.env[name] !== expected[name]) ||
    (Object.hasOwn(process.env, optionalMacEncoding) &&
      !/^0x[0-9A-F]+:0x[0-9A-F]+:0x[0-9A-F]+$/i.test(
        process.env[optionalMacEncoding],
      ))
  ) {
    fail("PRODUCTION_EXECUTOR_CLEAN_LAUNCH_REQUIRED");
  }
}

async function assertPinnedNodeProcess() {
  let resolved;
  let bytes;
  try {
    resolved = await realpath(PINNED_NODE_RUNTIME.executablePath);
    bytes = await readFile(resolved);
  } catch (_) {
    fail("PRODUCTION_EXECUTOR_NODE_UNVERIFIED");
  }
  try {
    if (
      resolved !== PINNED_NODE_RUNTIME.executableRealpath ||
      (await realpath(process.execPath)) !==
        PINNED_NODE_RUNTIME.executableRealpath ||
      process.version !== PINNED_NODE_RUNTIME.version ||
      sha256(bytes) !== PINNED_NODE_RUNTIME.executableSha256
    ) {
      fail("PRODUCTION_EXECUTOR_NODE_MISMATCH");
    }
  } finally {
    bytes?.fill?.(0);
  }
}

async function readStandardInput() {
  const chunks = [];
  let length = 0;
  for await (const chunk of process.stdin) {
    length += chunk.length;
    if (length > MAX_DOTENV_BYTES) {
      chunks.forEach((item) => item.fill(0));
      fail("CATALOG_DOTENV_SIZE_INVALID");
    }
    chunks.push(Buffer.from(chunk));
  }
  const bytes = Buffer.concat(chunks);
  chunks.forEach((item) => item.fill(0));
  const result = bytes.toString("utf8");
  bytes.fill(0);
  return result;
}

function waitForSpawn(command, args, options) {
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = nodeSpawn(command, args, options);
    } catch (error) {
      reject(error);
      return;
    }
    child.once("error", reject);
    child.once("exit", (code, signal) => {
      if (code === 0 && signal === null) resolve();
      else reject(new Error("child_exit"));
    });
  });
}

async function runLegacyReadOnly(script, args) {
  await waitForSpawn(PINNED_NODE_RUNTIME.executablePath, [script, ...args], {
    cwd: FUNCTIONS_DIRECTORY,
    env: scrubCredentialEnvironment(),
    stdio: "inherit",
  });
}

function operationKindForLane(lane) {
  return CATALOG_POLICY_LANES.includes(lane)
    ? "spazaone_catalog_policy_deployment"
    : "spazaone_catalog_function_deployment";
}

function manifestOperationKind(kind) {
  if (kind === "spazaone_catalog_function_deployment") {
    return "function_deployment";
  }
  if (kind === "spazaone_catalog_policy_deployment") {
    return "policy_deployment";
  }
  return "full_reconciliation";
}

function manifestSelectorForLane(lane) {
  if (lane === "firestore-rules") return "firestore:rules";
  if (lane === "firestore-indexes") return "firestore:indexes";
  return catalogFunctionSelector(lane);
}

async function authenticateCandidate(input) {
  let candidate;
  try {
    candidate = await loadAndValidateProductionCandidateManifest({
      manifestPath: input.candidateManifestPath,
      expectedManifestSha256: input.expectedCandidateManifestSha256,
      expectedAppCommit: input.expectedAppCommit,
      expectedCurrentMainCommit: input.expectedCurrentMainCommit,
      expectedOperation: {
        kind: manifestOperationKind(input.kind),
        lane: input.lane,
        selector: input.selector,
        inputSha256: input.operationInputSha256,
      },
    });
  } catch (_) {
    fail("PRODUCTION_CANDIDATE_MANIFEST_INVALID");
  }
  if (
    !Object.isFrozen(candidate.authenticatedManifest) ||
    !Object.isFrozen(candidate.authenticatedManifest.operation) ||
    canonicalSha256(candidate.authenticatedManifest) !==
      canonicalSha256(structuredClone(candidate.authenticatedManifest))
  ) {
    fail("PRODUCTION_CANDIDATE_SNAPSHOT_INVALID");
  }
  return candidate;
}

async function revalidateAuthorityAndCandidate(input) {
  let commit;
  try {
    commit = await resolveAuthorityAppCommit({
      expectedCandidateCommit: input.expectedAppCommit,
      expectedCurrentMainCommit: input.expectedCurrentMainCommit,
    });
  } catch (_) {
    fail("PRODUCTION_AUTHORITY_RECHECK_FAILED");
  }
  if (commit !== input.expectedAppCommit) {
    fail("PRODUCTION_AUTHORITY_RECHECK_FAILED");
  }
  return authenticateCandidate(input);
}

function storedRemoteEvidence(raw) {
  const { kind, ...summary } = structuredClone(raw);
  if (kind === "full_reconciliation") {
    const artifact = summary.artifact;
    return {
      kind,
      evidenceSha256: canonicalSha256(raw),
      summary: {
        artifactReceiptSha256: artifact.redactedReceiptSha256,
        completionDigestSha256: artifact.completionDigest,
        artifact,
      },
    };
  }
  return { kind, evidenceSha256: canonicalSha256(raw), summary };
}

function receiptRecord(input) {
  const record = {
    schemaVersion: 4,
    kind: input.kind,
    outcome: input.outcome,
    actionStartedAt: input.actionStartedAt,
    dispatchStartedAt: input.dispatchStartedAt,
    actionCompletedAt: input.actionCompletedAt,
    verifiedAt: input.verifiedAt,
    authority: { ...PRODUCTION_WRITE_AUTHORITY },
    target: { ...PRODUCTION_WRITE_TARGET },
    toolchain: productionReceiptToolchain(),
    appCommit: input.expectedAppCommit,
    operation: {
      lane: input.lane,
      selector: input.selector,
      sourceSha256: input.sourceSha256,
      configurationSha256: nativeCatalogTargetConfigurationDigestSha256(),
      candidateManifestSha256: input.expectedCandidateManifestSha256,
      operationInputSha256: input.operationInputSha256,
      actionAuthorizationSha256: input.actionAuthorizationSha256,
      actionAuthorizationClaimSha256: input.actionAuthorizationClaimSha256,
      operatorAuditOnly: true,
    },
    lineage: {
      mode: input.lineageMode,
      priorReceiptSha256: input.priorReceiptSha256,
    },
    result: {
      commandExitZero: input.commandExitZero,
      readbackStatus: input.readbackStatus,
      cleanupStatus: input.cleanupStatus,
      remoteEvidence: input.remoteEvidence
        ? storedRemoteEvidence(input.remoteEvidence)
        : null,
      errorCode: input.errorCode,
    },
    remoteWriteAttempted: input.remoteWriteAttempted,
    needsReview: input.outcome === "needs_review",
    retryAllowed: false,
  };
  const sealed = {
    ...record,
    redactedReceiptSha256: canonicalSha256(record),
  };
  validateProductionWriteReceipt(sealed);
  return sealed;
}

function manifestSnapshotBindsReceipt(candidate, receipt) {
  const document = candidate?.authenticatedManifest;
  return (
    Object.isFrozen(document) &&
    Object.isFrozen(document.operation) &&
    candidate.manifestSha256 === receipt.operation.candidateManifestSha256 &&
    sha256(canonicalProductionCandidateManifestBytes(document)) ===
      candidate.manifestSha256 &&
    document.appCommit === receipt.appCommit &&
    document.operation.kind === manifestOperationKind(receipt.kind) &&
    document.operation.lane === receipt.operation.lane &&
    document.operation.selector === receipt.operation.selector &&
    document.operation.inputSha256 === receipt.operation.operationInputSha256
  );
}

function issueAuthorityAttestation(receipt, candidate, transaction) {
  validateProductionWriteReceipt(receipt);
  if (
    receipt.outcome === "needs_review" ||
    !manifestSnapshotBindsReceipt(candidate, receipt) ||
    transaction.state !== "dispatch_started"
  ) {
    fail("PRODUCTION_EXECUTOR_ATTESTATION_INVALID", { needsReview: true });
  }
  const token = Object.freeze(Object.create(null));
  authorityAttestations.set(token, {
    receiptSha256: receipt.redactedReceiptSha256,
    candidateManifestSha256: candidate.manifestSha256,
    transaction,
  });
  return token;
}

async function persistWithPrivateAttestation(token, receipt, transaction) {
  const attestation = authorityAttestations.get(token);
  authorityAttestations.delete(token);
  if (
    !attestation ||
    attestation.transaction !== transaction ||
    attestation.receiptSha256 !== receipt.redactedReceiptSha256 ||
    attestation.candidateManifestSha256 !==
      receipt.operation.candidateManifestSha256 ||
    transaction.state !== "dispatch_started"
  ) {
    fail("PRODUCTION_EXECUTOR_ATTESTATION_CONSUMED", { needsReview: true });
  }
  validateProductionWriteReceipt(receipt);
  const bytes = Buffer.from(`${canonicalJson(receipt)}\n`, "utf8");
  try {
    return await transaction.persistFinal(bytes);
  } finally {
    bytes.fill(0);
  }
}

async function persistNeedsReview(receipt, transaction) {
  if (
    receipt.outcome !== "needs_review" ||
    transaction.state !== "dispatch_started"
  ) {
    fail("PRODUCTION_EXECUTOR_REVIEW_RECEIPT_INVALID", { needsReview: true });
  }
  validateProductionWriteReceipt(receipt);
  const bytes = Buffer.from(`${canonicalJson(receipt)}\n`, "utf8");
  try {
    return await transaction.persistFinal(bytes);
  } finally {
    bytes.fill(0);
  }
}

function intentBytes(input) {
  return Buffer.from(
    `${canonicalJson({
      schemaVersion: 1,
      kind: "spazaone_production_write_intent",
      operationKind: input.kind,
      appCommit: input.expectedAppCommit,
      lane: input.lane,
      selector: input.selector,
      sourceSha256: input.sourceSha256,
      configurationSha256: nativeCatalogTargetConfigurationDigestSha256(),
      candidateManifestSha256: input.expectedCandidateManifestSha256,
      operationInputSha256: input.operationInputSha256,
      actionAuthorizationSha256: input.actionAuthorizationSha256,
      actionAuthorizationClaimSha256: input.actionAuthorizationClaimSha256,
      actionAuthorizationId: input.actionAuthorizationId,
      actionAuthorizationExpiresAt: input.actionAuthorizationExpiresAt,
      actionAuthorizationIntentBindingSha256:
        input.actionAuthorizationIntentBindingSha256,
      priorReceiptSha256: input.priorReceiptSha256,
      receiptPathSha256: sha256(input.receiptPath),
      actionStartedAt: input.actionStartedAt,
      remoteWritePlanned: true,
      retryAllowed: false,
    })}\n`,
    "utf8",
  );
}

async function beginIntent(input) {
  const bytes = intentBytes(input);
  try {
    return await createDurableArtifactTransaction({
      targetPath: input.receiptPath,
      redactedIntentBytes: bytes,
    });
  } finally {
    bytes.fill(0);
  }
}

async function collectExistingEnvironmentBaselines(lane) {
  let parsed;
  try {
    const result = await execFile(
      PINNED_FIREBASE_CLI.executablePath,
      [
        "--project",
        PRODUCTION_FIREBASE_PROJECT_ID,
        "--account",
        PRODUCTION_FIREBASE_ACCOUNT,
        "--non-interactive",
        "--json",
        "functions:list",
      ],
      {
        cwd: APP_REPOSITORY_ROOT,
        encoding: "utf8",
        maxBuffer: MAX_READBACK_BYTES,
        env: scrubCredentialEnvironment(),
      },
    );
    parsed = JSON.parse(String(result.stdout ?? ""));
  } catch (_) {
    fail("CATALOG_FUNCTION_BASELINE_READBACK_FAILED");
  }
  const rows = Array.isArray(parsed)
    ? parsed
    : Array.isArray(parsed?.result)
      ? parsed.result
      : null;
  const names = catalogFunctionSelector(lane)
    .split(",")
    .map((value) => value.replace(/^functions:/, ""))
    .sort();
  const selected = rows?.filter((row) => names.includes(String(row?.id ?? "")));
  if (
    !selected ||
    selected.length !== names.length ||
    new Set(selected.map((row) => String(row.id))).size !== names.length
  ) {
    fail("CATALOG_FUNCTION_BASELINE_READBACK_FAILED");
  }
  return Object.fromEntries(
    selected.map((row) => [
      String(row.id),
      { environmentVariables: { ...(row.environmentVariables ?? {}) } },
    ]),
  );
}

async function candidateSourceContract(expectedAppCommit) {
  try {
    const runtimeConfigHashSha1 =
      await collectFirebaseGen1RuntimeConfigHashSha1({
        firebaseCliPath: PINNED_FIREBASE_CLI.executablePath,
        projectId: PRODUCTION_FIREBASE_PROJECT_ID,
        account: PRODUCTION_FIREBASE_ACCOUNT,
        anchorFunctionId: NATIVE_CATALOG_EXISTING_FUNCTIONS[0],
        environment: scrubCredentialEnvironment(),
      });
    return await computeCandidateFirebaseSourceContract({
      repositoryRoot: APP_REPOSITORY_ROOT,
      functionsDirectory: FUNCTIONS_DIRECTORY,
      expectedAppCommit,
      runtimeConfigHashSha1,
      environment: scrubCredentialEnvironment(),
    });
  } catch (_) {
    fail("CANDIDATE_FUNCTION_SOURCE_BINDING_FAILED");
  }
}

async function reviewedGitBlob(expectedAppCommit, relativePath) {
  if (
    !new Set(["firestore.rules", "firestore.indexes.json"]).has(relativePath)
  ) {
    fail("CANDIDATE_POLICY_SNAPSHOT_PATH_INVALID");
  }
  let bytes;
  try {
    const result = await execFile(
      "/usr/bin/git",
      [
        "-C",
        APP_REPOSITORY_ROOT,
        "show",
        `${expectedAppCommit}:${relativePath}`,
      ],
      {
        encoding: null,
        maxBuffer: MAX_READBACK_BYTES,
        env: scrubCredentialEnvironment(),
      },
    );
    bytes = Buffer.isBuffer(result.stdout)
      ? Buffer.from(result.stdout)
      : Buffer.from(String(result.stdout ?? ""), "utf8");
    if (bytes.length < 1 || bytes.length > MAX_READBACK_BYTES) {
      fail("CANDIDATE_POLICY_SNAPSHOT_UNREADABLE");
    }
    return bytes;
  } catch (error) {
    bytes?.fill?.(0);
    if (error instanceof ProductionExecutorError) throw error;
    fail("CANDIDATE_POLICY_SNAPSHOT_UNREADABLE");
  }
}

async function createAuthenticatedDeploymentSnapshot({
  policyLane,
  lane,
  expectedAppCommit,
  source,
  sourceContract,
  validated,
}) {
  const builder = await createImmutableDeploymentSnapshotBuilder();
  let sealed = false;
  let snapshot;
  try {
    let config;
    if (policyLane) {
      for (const relativePath of [
        "firestore.rules",
        "firestore.indexes.json",
      ]) {
        const bytes = await reviewedGitBlob(expectedAppCommit, relativePath);
        try {
          const digest = sha256(bytes);
          if (
            relativePath === source.sourcePath &&
            digest !== source.sourceSha256
          ) {
            fail("CANDIDATE_POLICY_SNAPSHOT_MISMATCH");
          }
          await builder.addBytes({
            relativePath,
            bytes,
            expectedSha256: digest,
          });
        } finally {
          bytes.fill(0);
        }
      }
      config = {
        firestore: {
          rules: path.join(builder.rootPath, "firestore.rules"),
          indexes: path.join(builder.rootPath, "firestore.indexes.json"),
        },
      };
    } else {
      const evidence = sourceContract?.packageFileEvidence;
      if (
        !Array.isArray(evidence) ||
        evidence.length !== sourceContract.packagedFileCount ||
        evidence.some(
          (entry) =>
            !entry ||
            typeof entry.relativePath !== "string" ||
            !SHA256.test(String(entry.sha256 ?? "")),
        )
      ) {
        fail("CANDIDATE_FUNCTION_SNAPSHOT_EVIDENCE_INVALID");
      }
      for (const entry of evidence) {
        await builder.addSourceFile({
          relativePath: `functions/${entry.relativePath}`,
          sourcePath: path.join(
            FUNCTIONS_DIRECTORY,
            ...entry.relativePath.split("/"),
          ),
          expectedSha256: entry.sha256,
        });
      }
      if (validated) {
        const dotenvBytes = Buffer.from(validated.normalized, "utf8");
        try {
          await builder.addBytes({
            relativePath: `config/.env.${PRODUCTION_FIREBASE_PROJECT_ID}`,
            bytes: dotenvBytes,
            expectedSha256: sha256(dotenvBytes),
          });
        } finally {
          dotenvBytes.fill(0);
        }
      }
      config = {
        functions: [
          {
            source: path.join(builder.rootPath, "functions"),
            codebase: "default",
            ignore: [
              "node_modules",
              ".git",
              "firebase-debug.log",
              "firebase-debug.*.log",
            ],
            ...(validated
              ? { configDir: path.join(builder.rootPath, "config") }
              : {}),
          },
        ],
      };
    }
    const configBytes = Buffer.from(`${JSON.stringify(config, null, 2)}\n`);
    try {
      await builder.addBytes({
        relativePath: "firebase.json",
        bytes: configBytes,
        expectedSha256: sha256(configBytes),
      });
    } finally {
      configBytes.fill(0);
    }
    snapshot = await builder.seal();
    sealed = true;
    await verifyImmutableDeploymentSnapshot(snapshot);
    return snapshot;
  } catch (error) {
    if (!sealed) {
      try {
        await builder.discard();
      } catch (_) {
        // The original pre-dispatch validation error remains authoritative.
      }
    } else if (snapshot) {
      try {
        await removeImmutableDeploymentSnapshot(snapshot);
      } catch (_) {
        // The original pre-dispatch validation error remains authoritative.
      }
    }
    throw error;
  }
}

function functionRemoteEvidence(lane, selector, readback) {
  return {
    kind: "function_deployment",
    lane,
    selector,
    firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
    region: PRODUCTION_FIREBASE_FUNCTION_REGION,
    functionCount: readback.functionCount,
    buildIdentitiesComplete: readback.buildIdentitiesComplete,
    buildIdentitySetSha256: readback.buildIdentitySetSha256,
    environmentShapesValid: readback.environmentShapesValid,
    environmentMatches: readback.environmentMatches,
    secretReferencesMatch: readback.secretReferencesMatch,
    environmentDigestSha256: readback.environmentDigestSha256,
    expectedEnvironmentDigestSha256: readback.expectedEnvironmentDigestSha256,
    candidateSourceBindingMatches: readback.candidateSourceBindingMatches,
    candidateSourceContractSha256: readback.candidateSourceContractSha256,
    candidateSourceFileCount: readback.candidateSourceFileCount,
    candidateGeneratedFileCount: readback.candidateGeneratedFileCount,
    candidateProviderBindingSetSha256:
      readback.candidateProviderBindingSetSha256,
  };
}

function policyReadbackMatches(lane, source, readback) {
  if (lane === "firestore-rules") {
    return readback.activeSourceSha256 === source.sourceSha256;
  }
  return (
    readback.databaseId === PRODUCTION_FIRESTORE_DATABASE_ID &&
    readback.remoteIndexCount === source.indexCount &&
    readback.remoteFieldOverrideCount === source.fieldOverrideCount &&
    readback.remoteFullIndexConfigurationDigestSha256 ===
      source.fullIndexConfigurationDigestSha256 &&
    readback.remoteTtlFieldCount === REQUIRED_CATALOG_TTL_FIELDS.length &&
    readback.remoteTtlContractDigestSha256 === source.ttlContractDigestSha256 &&
    readback.ttlActive === true &&
    readback.ttlActiveCount === REQUIRED_CATALOG_TTL_FIELDS.length
  );
}

function policyRemoteEvidence(lane, source, readback) {
  if (lane === "firestore-rules") {
    return {
      kind: "firestore_rules",
      lane,
      selector: source.selector,
      firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
      databaseId: PRODUCTION_FIRESTORE_DATABASE_ID,
      sourceSha256: source.sourceSha256,
      activeSourceSha256: readback.activeSourceSha256,
      activeRulesetName: readback.activeRulesetName,
    };
  }
  return {
    kind: "firestore_indexes",
    lane,
    selector: source.selector,
    firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
    databaseId: PRODUCTION_FIRESTORE_DATABASE_ID,
    sourceSha256: source.sourceSha256,
    expectedFullIndexConfigurationDigestSha256:
      source.fullIndexConfigurationDigestSha256,
    remoteFullIndexConfigurationDigestSha256:
      readback.remoteFullIndexConfigurationDigestSha256,
    expectedIndexCount: source.indexCount,
    remoteIndexCount: readback.remoteIndexCount,
    expectedFieldOverrideCount: source.fieldOverrideCount,
    remoteFieldOverrideCount: readback.remoteFieldOverrideCount,
    expectedTtlContractDigestSha256: source.ttlContractDigestSha256,
    remoteTtlContractDigestSha256: readback.remoteTtlContractDigestSha256,
    expectedTtlFieldCount: REQUIRED_CATALOG_TTL_FIELDS.length,
    remoteTtlFieldCount: readback.remoteTtlFieldCount,
    ttlActive: readback.ttlActive,
    ttlActiveCount: readback.ttlActiveCount,
  };
}

async function executeDeployment(options, dotenvText) {
  assertLiveSessionCapabilityAuthorized();
  const kind = operationKindForLane(options.lane);
  const selector = manifestSelectorForLane(options.lane);
  const policyLane = CATALOG_POLICY_LANES.includes(options.lane);
  await assertPinnedProductionToolchain();
  let validated = null;
  let source;
  let operationInputSha256;
  if (policyLane) {
    source = await catalogPolicySourceContract(options.lane);
    operationInputSha256 = source.sourceSha256;
  } else if (options.lane === "existing-code") {
    if (dotenvText.trim()) fail("EXISTING_FUNCTION_DOTENV_FORBIDDEN");
    await assertNoSourceDeploymentDotenv(FUNCTIONS_DIRECTORY);
    await assertPinnedFirebaseCliEnvironmentPreservation();
    operationInputSha256 = sha256(JSON.stringify({ dotenvSha256: null }));
    source = { sourceSha256: appCommitSourceSha256(options.expectedAppCommit) };
  } else {
    await assertNoSourceDeploymentDotenv(FUNCTIONS_DIRECTORY);
    validated = validateCatalogDeploymentDotenv({
      lane: options.lane,
      text: dotenvText,
      appCommit: options.expectedAppCommit,
    });
    operationInputSha256 = validated.sha256;
    source = { sourceSha256: appCommitSourceSha256(options.expectedAppCommit) };
  }
  const context = {
    ...options,
    kind,
    selector,
    operationInputSha256,
    sourceSha256: source.sourceSha256,
    priorReceiptSha256: null,
  };
  await revalidateAuthorityAndCandidate(context);
  const authorizationOperation = {
    kind,
    lane: options.lane,
    selector,
    sourceSha256: source.sourceSha256,
    configurationSha256: nativeCatalogTargetConfigurationDigestSha256(),
    candidateManifestSha256: options.expectedCandidateManifestSha256,
    operationInputSha256,
  };
  const authorization = await loadProductionActionAuthorization({
    authorizationPath: options.authorizationPath,
    expectedAuthorizationReceiptSha256:
      options.expectedAuthorizationReceiptSha256,
    expectedAppCommit: options.expectedAppCommit,
    expectedOperation: authorizationOperation,
    expectedReceiptPath: options.receiptPath,
    expectedPriorReceiptSha256: null,
  });
  context.actionAuthorizationSha256 = authorization.authorizationReceiptSha256;
  context.actionAuthorizationId = authorization.authorizationId;
  context.actionAuthorizationExpiresAt = authorization.expiresAt;
  context.actionAuthorizationIntentBindingSha256 =
    authorization.intentBindingSha256;
  const initialSourceContract = policyLane
    ? null
    : await candidateSourceContract(options.expectedAppCommit);
  const existingEnvironmentBaselines =
    options.lane === "existing-code"
      ? await collectExistingEnvironmentBaselines(options.lane)
      : null;
  const before =
    options.lane === "existing-code"
      ? await collectCatalogFunctionReadback({
          lane: options.lane,
          validated: null,
          candidateSourceContract: initialSourceContract,
          existingEnvironmentBaselines,
        })
      : null;
  if (
    before &&
    (!SHA256.test(String(before.environmentDigestSha256 ?? "")) ||
      before.environmentShapesValid !== true)
  ) {
    fail("CATALOG_FUNCTION_READBACK_FAILED");
  }

  const deploymentSnapshot = await createAuthenticatedDeploymentSnapshot({
    policyLane,
    expectedAppCommit: options.expectedAppCommit,
    source,
    sourceContract: initialSourceContract,
    validated,
  });
  const configPath = immutableDeploymentSnapshotPath(
    deploymentSnapshot,
    "firebase.json",
  );

  const actionStartedAt = now();
  context.actionStartedAt = actionStartedAt;
  let transaction;
  let dispatchStartedAt;
  let commandExitZero = false;
  let cleanupStatus = "deleted";
  let snapshotRemoved = false;
  try {
    const authorizationClaim =
      await claimProductionActionAuthorization(authorization);
    context.actionAuthorizationClaimSha256 = authorizationClaim.claimSha256;
    transaction = await beginIntent(context);
    await transaction.verifyReadyForDispatch();
    await revalidateAuthorityAndCandidate(context);
    const dispatchAuthorization = await loadProductionActionAuthorization({
      authorizationPath: options.authorizationPath,
      expectedAuthorizationReceiptSha256:
        options.expectedAuthorizationReceiptSha256,
      expectedAppCommit: options.expectedAppCommit,
      expectedOperation: authorizationOperation,
      expectedReceiptPath: options.receiptPath,
      expectedPriorReceiptSha256: null,
    });
    if (
      dispatchAuthorization.intentBindingSha256 !==
        context.actionAuthorizationIntentBindingSha256 ||
      dispatchAuthorization.authorizationId !== context.actionAuthorizationId
    ) {
      fail("PRODUCTION_ACTION_AUTHORIZATION_CHANGED");
    }
    await verifyImmutableDeploymentSnapshot(deploymentSnapshot);
    dispatchStartedAt = now();
    transaction.markDispatchStarted();
    try {
      await waitForSpawn(
        CODEX_GUARD,
        codexGuardDeployArguments({
          lane: options.lane,
          dryRun: false,
          configPath,
        }),
        {
          cwd: APP_REPOSITORY_ROOT,
          env: scrubCredentialEnvironment(),
          stdio: "inherit",
        },
      );
      commandExitZero = true;
    } catch (_) {
      commandExitZero = false;
    }
    let snapshotIntegrityVerified = false;
    try {
      await verifyImmutableDeploymentSnapshot(deploymentSnapshot);
      snapshotIntegrityVerified = true;
    } catch (_) {
      snapshotIntegrityVerified = false;
    }
    try {
      await removeImmutableDeploymentSnapshot(deploymentSnapshot);
      snapshotRemoved = true;
    } catch (_) {
      cleanupStatus = "needs_review";
    }
    if (!commandExitZero) {
      throw new ProductionExecutorError(
        "CATALOG_DEPLOY_EXECUTION_NEEDS_REVIEW",
        { needsReview: true },
      );
    }
    if (!snapshotIntegrityVerified) {
      throw new ProductionExecutorError(
        "CATALOG_DEPLOY_SNAPSHOT_INTEGRITY_NEEDS_REVIEW",
        { needsReview: true },
      );
    }

    let rawEvidence;
    if (policyLane) {
      const readback = await collectCatalogPolicyReadback(options.lane);
      if (!policyReadbackMatches(options.lane, source, readback)) {
        fail("CATALOG_POLICY_READBACK_NEEDS_REVIEW", { needsReview: true });
      }
      rawEvidence = policyRemoteEvidence(options.lane, source, readback);
    } else {
      const readback = await collectCatalogFunctionReadback({
        lane: options.lane,
        validated,
        ...(before
          ? {
              expectedPreservationDigestSha256: before.environmentDigestSha256,
              existingEnvironmentBaselines,
            }
          : {}),
        candidateSourceContract: initialSourceContract,
      });
      if (readback.environmentMatches !== true) {
        fail("CATALOG_FUNCTION_READBACK_NEEDS_REVIEW", { needsReview: true });
      }
      rawEvidence = functionRemoteEvidence(options.lane, selector, readback);
    }
    if (cleanupStatus !== "deleted") {
      fail("CATALOG_DEPLOY_CLEANUP_NEEDS_REVIEW", { needsReview: true });
    }
    const actionCompletedAt = now();
    const verifiedAt = now();
    const receipt = receiptRecord({
      ...context,
      outcome: "verified",
      actionStartedAt,
      dispatchStartedAt,
      actionCompletedAt,
      verifiedAt,
      lineageMode: "direct_write",
      commandExitZero: true,
      readbackStatus: "verified",
      cleanupStatus,
      remoteEvidence: rawEvidence,
      errorCode: null,
      remoteWriteAttempted: true,
    });
    const finalCandidate = await authenticateCandidate(context);
    const attestation = issueAuthorityAttestation(
      receipt,
      finalCandidate,
      transaction,
    );
    const persisted = await persistWithPrivateAttestation(
      attestation,
      receipt,
      transaction,
    );
    return {
      outcome: "verified",
      kind,
      lane: options.lane,
      receiptPath: persisted.path,
      receiptSha256: receipt.redactedReceiptSha256,
      retryAllowed: false,
    };
  } catch (error) {
    if (!dispatchStartedAt) {
      try {
        await transaction?.cancelBeforeDispatch();
      } catch (_) {
        fail("PRODUCTION_WRITE_INTENT_CANCELLATION_UNCERTAIN");
      }
      try {
        if (!snapshotRemoved) {
          await removeImmutableDeploymentSnapshot(deploymentSnapshot);
          snapshotRemoved = true;
        }
      } catch (_) {
        fail("PRODUCTION_DEPLOY_SNAPSHOT_CLEANUP_UNCERTAIN");
      }
      throw error;
    }
    if (transaction?.state === "dispatch_started") {
      const completedAt = now();
      const safeCode = /^[A-Z][A-Z0-9_]{0,95}$/.test(String(error?.code ?? ""))
        ? error.code
        : "CATALOG_DEPLOY_EXECUTION_NEEDS_REVIEW";
      const receipt = receiptRecord({
        ...context,
        outcome: "needs_review",
        actionStartedAt,
        dispatchStartedAt,
        actionCompletedAt: completedAt,
        verifiedAt: completedAt,
        lineageMode: "direct_write",
        commandExitZero,
        readbackStatus: "needs_review",
        cleanupStatus,
        remoteEvidence: null,
        errorCode: safeCode,
        remoteWriteAttempted: true,
      });
      try {
        await persistNeedsReview(receipt, transaction);
      } catch (persistError) {
        throw new ProductionExecutorError(
          "PRODUCTION_RECEIPT_PERSISTENCE_UNCERTAIN",
          {
            needsReview: true,
            targetMayExist: persistError?.targetMayExist === true,
            cause: persistError,
          },
        );
      }
      throw new ProductionExecutorError(safeCode, { needsReview: true });
    }
    throw error;
  }
}

async function executeReconciliation() {
  // Enabling the write-capable reconciliation transport requires an explicit
  // implementation authorization separate from credential provisioning.
  fail("PRODUCTION_RECONCILIATION_EXECUTOR_NOT_ENABLED");
}

async function main() {
  try {
    await assertCleanLauncherOrigin();
    cleanExecutorEnvironment();
    await assertPinnedNodeProcess();
    const [mode, ...args] = process.argv.slice(2);
    const authorizationArguments = extractActionAuthorizationArguments(args);
    if (mode === "deployment") {
      const options = {
        ...parseDeploymentGuardArguments(authorizationArguments.remaining),
        authorizationPath: authorizationArguments.authorizationPath,
        expectedAuthorizationReceiptSha256:
          authorizationArguments.expectedAuthorizationReceiptSha256,
      };
      if (!options.execute) {
        await runLegacyReadOnly(LEGACY_DEPLOYMENT_SCRIPT, args);
        return;
      }
      assertExecutorActivationAuthorized();
      const policyLane = CATALOG_POLICY_LANES.includes(options.lane);
      if (
        !policyLane &&
        process.stdin.isTTY &&
        options.lane !== "existing-code"
      ) {
        fail("CATALOG_DOTENV_STDIN_REQUIRED");
      }
      const dotenvText =
        policyLane || process.stdin.isTTY ? "" : await readStandardInput();
      const result = await executeDeployment(options, dotenvText);
      process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
      return;
    }
    if (mode === "reconciliation") {
      const options = {
        ...parseRunnerArguments(authorizationArguments.remaining),
        authorizationPath: authorizationArguments.authorizationPath,
        expectedAuthorizationReceiptSha256:
          authorizationArguments.expectedAuthorizationReceiptSha256,
      };
      if (!options.execute) {
        await runLegacyReadOnly(LEGACY_RECONCILIATION_SCRIPT, args);
        return;
      }
      // The reconciliation loop is defined below in the same zero-export
      // module so no importer can reach its write-capable transport.
      const result = await executeReconciliation(options);
      process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
      return;
    }
    fail("PRODUCTION_EXECUTOR_MODE_INVALID");
  } catch (error) {
    const safe =
      error instanceof ProductionExecutorError
        ? error
        : new ProductionExecutorError(
            error instanceof ReconciliationOperatorError
              ? error.code
              : "PRODUCTION_EXECUTOR_FAILED",
            { needsReview: error?.needsReview === true, cause: error },
          );
    process.stderr.write(
      `${JSON.stringify({
        outcome: safe.needsReview ? "needs_review" : "blocked",
        code: safe.code,
        retryAllowed: false,
        ...(safe.targetMayExist ? { targetMayExist: true } : {}),
      })}\n`,
    );
    process.exitCode = 1;
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
) {
  await main();
}
