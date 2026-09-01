#!/usr/bin/env node

import {
  execFile as nodeExecFile,
  spawn as nodeSpawn,
} from "node:child_process";
import { createHash } from "node:crypto";
import {
  closeSync,
  constants as fsConstants,
  fstatSync,
  openSync,
  readFileSync,
  readSync,
  writeSync,
} from "node:fs";
import { lstat, readFile, realpath } from "node:fs/promises";
import path from "node:path";
import { isatty } from "node:tty";
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
  verifyExistingCodeEnvironmentBaseline,
} from "./guard-whatsapp-catalog-functions-deploy.mjs";
import {
  APP_REPOSITORY_ROOT,
  FROZEN_APP_MAIN_COMMIT,
  ReconciliationOperatorError,
  parseRunnerArguments,
  reconciliationOperationInputSha256,
  resolveAuthorityAppCommit,
  resolvePasellaBotToken,
  scrubCredentialEnvironment,
} from "./run-whatsapp-catalog-full-reconciliation.mjs";
import {
  FINALIZED_RECONCILIATION_ARTIFACT_KEYS,
  PINNED_FIREBASE_CLI,
  PINNED_NODE_RUNTIME,
  PRODUCTION_WRITE_AUTHORITY,
  PRODUCTION_WRITE_TARGET,
  appCommitSourceSha256,
  assertPinnedProductionToolchain,
  canonicalJson,
  canonicalSha256,
  productionReceiptToolchain,
  validateFinalizedReconciliationArtifact,
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
  loadPriorNeedsReviewReceipt,
  revalidateLoadedPriorNeedsReviewReceipt,
} from "./prior-needs-review-receipt.mjs";
import {
  cleanupExactCommitFirebasePackage,
  cleanupFirebaseProviderWorkspace,
  createFirebaseProductionSessionWorkspace,
  firebaseProviderWorkspacePath,
  inspectFirebaseProviderWorkspace,
  mountExactCommitFirebasePackageReadOnly,
  mountedExactCommitFirebasePackagePath,
  prepareExactCommitFirebasePackage,
  verifyFirebaseProductionSessionWorkspace,
  verifyMountedExactCommitFirebasePackage,
} from "./exact-commit-firebase-package.mjs";
import {
  PRODUCTION_FIREBASE_ACCOUNT,
  PRODUCTION_FIREBASE_PROJECT_ID,
  PRODUCTION_NATIVE_CATALOG_TARGET,
  RECONCILIATION_FUNCTION_URL,
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
const MAX_RECONCILIATION_RESPONSE_BYTES = 5 * 1024 * 1024;
const MAX_TTY_RESPONSE_BYTES = 512;
const ACTION_AUTHORIZATION_WINDOW_MS = 5 * 60 * 1000;
const CONTROLLING_TTY_PATH = "/dev/tty";
const SHA256 = /^[a-f0-9]{64}$/;
const authorityAttestations = new WeakMap();
const preparedLiveSessions = new WeakMap();
const liveSessionCapabilities = new WeakMap();
const recoveryInspectionCapabilities = new WeakMap();
const consumedLiveSessions = new WeakSet();
const LIVE_SESSION_MAX_AGE_MS = 10 * 60 * 1000;
const CLEAN_LAUNCHER = Object.freeze({
  path: path.join(
    FUNCTIONS_DIRECTORY,
    "scripts/launch-whatsapp-catalog-production.sh",
  ),
  sha256: "a1dd74131ca74bcbebac23cba2c24b1efbaf0bb6619f8f7cdac5aae3d1cf8e80",
  fd: 3,
});

class ProductionExecutorError extends Error {
  constructor(
    code,
    {
      needsReview = false,
      targetMayExist = false,
      recovery = null,
      cause,
    } = {},
  ) {
    super(code, cause === undefined ? undefined : { cause });
    this.name = "ProductionExecutorError";
    this.code = code;
    this.needsReview = needsReview;
    this.targetMayExist = targetMayExist;
    this.recovery = recovery;
    this.retryAllowed = false;
  }
}

function fail(code, details) {
  throw new ProductionExecutorError(code, details);
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}

function liveSessionRecoveryBinding(value = {}) {
  const mode = value.mode ?? "direct";
  if (!new Set(["direct", "readback_first", "continuation"]).has(mode)) {
    fail("PRODUCTION_LIVE_SESSION_RECOVERY_MODE_INVALID");
  }
  const priorReceiptSha256 = value.priorReceiptSha256 ?? null;
  const cycleId = value.cycleId ?? null;
  const continuationStateDigestSha256 =
    value.continuationStateDigestSha256 ?? null;
  const recoveryReadbackSha256 = value.recoveryReadbackSha256 ?? null;
  if (
    (mode === "direct" &&
      [
        priorReceiptSha256,
        cycleId,
        continuationStateDigestSha256,
        recoveryReadbackSha256,
      ].some((entry) => entry !== null)) ||
    (mode !== "direct" && !SHA256.test(String(priorReceiptSha256 ?? ""))) ||
    (mode === "readback_first" &&
      [cycleId, continuationStateDigestSha256, recoveryReadbackSha256].some(
        (entry) => entry !== null,
      )) ||
    (mode === "continuation" &&
      ((cycleId !== null && !/^[a-f0-9]{32}$/.test(String(cycleId))) ||
        !SHA256.test(String(continuationStateDigestSha256 ?? "")) ||
        !SHA256.test(String(recoveryReadbackSha256 ?? ""))))
  ) {
    fail("PRODUCTION_LIVE_SESSION_RECOVERY_BINDING_INVALID");
  }
  return {
    mode,
    priorReceiptSha256,
    cycleId,
    continuationStateDigestSha256,
    recoveryReadbackSha256,
  };
}

async function cleanupLiveSessionState(state) {
  if (!state || state.cleaned === true) return;
  if (state.cleanupPromise) return state.cleanupPromise;
  state.cleanupPromise = (async () => {
    if (state.expiryTimer) {
      clearTimeout(state.expiryTimer);
      state.expiryTimer = undefined;
    }
    let cleanupError = null;
    try {
      if (state.workspace && state.workspaceCleaned !== true) {
        await cleanupFirebaseProviderWorkspace(state.workspace);
        state.workspaceCleaned = true;
      }
    } catch (error) {
      cleanupError = error;
    }
    try {
      if (
        (state.mountedPackage || state.packageDescriptor) &&
        state.packageCleaned !== true
      ) {
        await cleanupExactCommitFirebasePackage({
          mountedPackage: state.mountedPackage,
          packageDescriptor: state.packageDescriptor,
        });
        state.packageCleaned = true;
      }
    } catch (error) {
      cleanupError ??= error;
    }
    if (cleanupError) throw cleanupError;
    state.cleaned = true;
  })();
  return state.cleanupPromise;
}

function detachLiveSessionCapability(registry, capability, state) {
  if (state?.expiryTimer) {
    clearTimeout(state.expiryTimer);
    state.expiryTimer = undefined;
  }
  if (registry.get(capability) === state) registry.delete(capability);
}

function registerLiveSessionCapability(registry, capability, state) {
  const expiresAtMs = Date.parse(state?.binding?.expiresAt ?? "");
  if (!Number.isFinite(expiresAtMs)) {
    fail("PRODUCTION_LIVE_SESSION_EXPIRY_INVALID");
  }
  registry.set(capability, state);
  const expiryTimer = setTimeout(
    () => {
      if (registry.get(capability) !== state) return;
      registry.delete(capability);
      state.expiryTimer = undefined;
      state.consumed = true;
      void cleanupLiveSessionState(state).catch(() => {
        state.cleanupFailed = true;
      });
    },
    Math.max(0, expiresAtMs - Date.now()),
  );
  expiryTimer.unref?.();
  state.expiryTimer = expiryTimer;
}

async function rejectAndCleanupExpiredLiveSession({
  registry,
  capability,
  state,
  currentMs,
  code,
}) {
  if (
    !state ||
    !Number.isFinite(currentMs) ||
    currentMs < Date.parse(state.binding.expiresAt)
  ) {
    return false;
  }
  detachLiveSessionCapability(registry, capability, state);
  state.consumed = true;
  try {
    await cleanupLiveSessionState(state);
  } catch (error) {
    fail("PRODUCTION_LIVE_SESSION_EXPIRY_CLEANUP_FAILED", { cause: error });
  }
  fail(code);
}

async function disposeActiveLiveSession({
  registry,
  capability,
  inactiveCode,
}) {
  const state = registry.get(capability);
  if (!state || state.consumed) fail(inactiveCode);
  detachLiveSessionCapability(registry, capability, state);
  state.consumed = true;
  try {
    await cleanupLiveSessionState(state);
  } catch (error) {
    fail("PRODUCTION_LIVE_SESSION_DISPOSAL_FAILED", { cause: error });
  }
  return Object.freeze({
    outcome: "disposed",
    bindingSha256: state.bindingSha256,
    remoteWriteAttempted: false,
  });
}

async function invalidateLiveSessionCapability({
  registry,
  capability,
  state,
}) {
  detachLiveSessionCapability(registry, capability, state);
  state.consumed = true;
  try {
    await cleanupLiveSessionState(state);
  } catch (error) {
    fail("PRODUCTION_LIVE_SESSION_DISPOSAL_FAILED", { cause: error });
  }
}

async function prepareProductionLiveSession({
  context,
  candidate,
  dotenvText,
  recovery,
  recoveryReadbackProvider,
  clock = () => new Date(),
}) {
  if (
    !candidate ||
    !Object.isFrozen(candidate.authenticatedManifest) ||
    candidate.appCommit !== context.expectedAppCommit ||
    candidate.governedMainCommit !== context.expectedCurrentMainCommit ||
    candidate.manifestSha256 !== context.expectedCandidateManifestSha256 ||
    candidate.operation?.kind !== manifestOperationKind(context.kind) ||
    candidate.operation?.lane !== context.lane ||
    candidate.operation?.selector !== context.selector ||
    candidate.operation?.inputSha256 !== context.operationInputSha256
  ) {
    fail("PRODUCTION_LIVE_SESSION_CANDIDATE_INVALID");
  }
  const recoveryBinding = liveSessionRecoveryBinding(recovery);
  const recoveryInspection = recoveryBinding.mode === "readback_first";
  if (
    recoveryBinding.mode === "continuation" ||
    (recoveryInspection && typeof recoveryReadbackProvider !== "function") ||
    (!recoveryInspection && recoveryReadbackProvider !== undefined)
  ) {
    fail("PRODUCTION_RECOVERY_READBACK_PROVIDER_INVALID");
  }
  const policyLane = CATALOG_POLICY_LANES.includes(context.lane);
  if (
    policyLane ||
    context.lane === "existing-code" ||
    context.lane === "full-reconciliation"
  ) {
    if (dotenvText !== "") fail("PRODUCTION_LIVE_SESSION_DOTENV_INVALID");
  } else {
    let validatedDotenv;
    try {
      validatedDotenv = validateCatalogDeploymentDotenv({
        lane: context.lane,
        text: dotenvText,
        appCommit: context.expectedAppCommit,
      });
    } catch (_) {
      fail("PRODUCTION_LIVE_SESSION_DOTENV_INVALID");
    }
    if (validatedDotenv.sha256 !== context.operationInputSha256) {
      fail("PRODUCTION_LIVE_SESSION_DOTENV_BINDING_MISMATCH");
    }
  }
  const preparedAt = clock();
  if (!(preparedAt instanceof Date) || !Number.isFinite(preparedAt.getTime())) {
    fail("PRODUCTION_LIVE_SESSION_CLOCK_INVALID");
  }
  let packageDescriptor;
  let mountedPackage;
  let workspace;
  try {
    packageDescriptor = await prepareExactCommitFirebasePackage({
      repositoryRoot: APP_REPOSITORY_ROOT,
      expectedAppCommit: context.expectedAppCommit,
      temporaryRoot: "/private/tmp",
    });
    if (packageDescriptor.gitTreeSha1 !== candidate.gitTreeSha1) {
      fail("PRODUCTION_LIVE_SESSION_GIT_TREE_MISMATCH");
    }
    mountedPackage =
      await mountExactCommitFirebasePackageReadOnly(packageDescriptor);
    const mountEvidence =
      await verifyMountedExactCommitFirebasePackage(mountedPackage);
    workspace = await createFirebaseProductionSessionWorkspace({
      mountedPackage,
      projectId: PRODUCTION_FIREBASE_PROJECT_ID,
      lane: context.lane,
      dotenvText,
      temporaryRoot: "/private/tmp",
    });
    const scratchEvidence =
      await verifyFirebaseProductionSessionWorkspace(workspace);
    const expiresAt = new Date(
      preparedAt.getTime() + LIVE_SESSION_MAX_AGE_MS,
    ).toISOString();
    const binding = deepFreeze({
      schemaVersion: 1,
      kind: "spazaone_production_live_session",
      preparedAt: preparedAt.toISOString(),
      expiresAt,
      authority: { ...PRODUCTION_WRITE_AUTHORITY },
      target: { ...PRODUCTION_WRITE_TARGET },
      candidate: {
        appCommit: context.expectedAppCommit,
        governedMainCommit: context.expectedCurrentMainCommit,
        gitTreeSha1: candidate.gitTreeSha1,
        gitArchiveSha256: packageDescriptor.gitArchiveSha256,
        reviewedArchiveInventorySha256:
          packageDescriptor.reviewedArchiveInventorySha256,
        packageInventorySha256: packageDescriptor.packageInventorySha256,
        packageJsonSha256: packageDescriptor.packageJsonSha256,
        packageLockSha256: packageDescriptor.packageLockSha256,
        dependencyClosureSha256: packageDescriptor.dependencyClosureSha256,
        generatedLibInventorySha256:
          packageDescriptor.generatedLibInventorySha256,
        candidateManifestSha256: candidate.manifestSha256,
        reviewedEvidenceReceiptSetSha256: candidate.receiptSetSha256,
      },
      operation: {
        kind: context.kind,
        lane: context.lane,
        selector: context.selector,
        sourceSha256: context.sourceSha256,
        configurationSha256: nativeCatalogTargetConfigurationDigestSha256(),
        operationInputSha256: context.operationInputSha256,
      },
      receiptPathSha256: sha256(context.receiptPath),
      recovery: recoveryBinding,
      scratch: {
        workspaceConfigSha256: workspace.configSha256,
        dotenvSha256: workspace.dotenvSha256,
        sourcePackageInventorySha256:
          scratchEvidence.sourcePackageInventorySha256,
        providerScratchInventorySha256:
          scratchEvidence.providerScratchInventorySha256,
        providerScratchEntryCount: scratchEvidence.providerScratchEntryCount,
        sourceKernelReadOnly:
          mountEvidence.kernelReadOnly === true &&
          scratchEvidence.sourceKernelReadOnly === true &&
          scratchEvidence.providerInputKernelReadOnly === true,
        providerInputInventorySha256:
          scratchEvidence.providerInputInventorySha256,
      },
      oneShot: true,
      serializableCapability: false,
      productionWriteAttempted: false,
    });
    const bindingSha256 = canonicalSha256(binding);
    const capability = Object.freeze(Object.create(null));
    const state = {
      binding,
      bindingSha256,
      candidate,
      packageDescriptor,
      mountedPackage,
      workspace,
      context: structuredClone(context),
      recoveryReadbackProvider: recoveryInspection
        ? recoveryReadbackProvider
        : undefined,
      consumed: false,
      cleaned: false,
    };
    if (recoveryBinding.mode === "readback_first") {
      registerLiveSessionCapability(
        recoveryInspectionCapabilities,
        capability,
        state,
      );
    } else {
      registerLiveSessionCapability(preparedLiveSessions, capability, state);
    }
    return {
      capability,
      summary: Object.freeze({
        outcome: "authorization_required",
        bindingSha256,
        expiresAt,
        appCommit: context.expectedAppCommit,
        governedMainCommit: context.expectedCurrentMainCommit,
        gitTreeSha1: candidate.gitTreeSha1,
        gitArchiveSha256: packageDescriptor.gitArchiveSha256,
        packageInventorySha256: packageDescriptor.packageInventorySha256,
        candidateManifestSha256: candidate.manifestSha256,
        reviewedEvidenceReceiptSetSha256: candidate.receiptSetSha256,
        targetConfigurationDigestSha256:
          nativeCatalogTargetConfigurationDigestSha256(),
        operation: Object.freeze({ ...binding.operation }),
        recoveryMode: recoveryBinding.mode,
        receiptPathSha256: binding.receiptPathSha256,
        sourceKernelReadOnly: binding.scratch.sourceKernelReadOnly,
        providerScratchEntryCount: binding.scratch.providerScratchEntryCount,
        productionWriteAttempted: false,
      }),
    };
  } catch (error) {
    await cleanupLiveSessionState({
      packageDescriptor,
      mountedPackage,
      workspace,
      cleaned: false,
    });
    throw error;
  }
}

async function authorizePreparedProductionLiveSession(
  preparedCapability,
  { authorizedAt, deadline, clock = () => new Date() },
) {
  const state = preparedLiveSessions.get(preparedCapability);
  const authorizedAtMs = Date.parse(authorizedAt);
  const deadlineMs = Date.parse(deadline);
  const current = clock();
  const nowMs = current instanceof Date ? current.getTime() : Number.NaN;
  await rejectAndCleanupExpiredLiveSession({
    registry: preparedLiveSessions,
    capability: preparedCapability,
    state,
    currentMs: nowMs,
    code: "FRESH_PRODUCTION_ACTION_AUTHORIZATION_REQUIRED",
  });
  if (
    !state ||
    state.consumed ||
    state.binding.recovery.mode !== "direct" ||
    !Number.isFinite(authorizedAtMs) ||
    !Number.isFinite(deadlineMs) ||
    !Number.isFinite(nowMs) ||
    authorizedAtMs > nowMs ||
    authorizedAtMs < Date.parse(state.binding.preparedAt) ||
    deadlineMs <= nowMs ||
    deadlineMs <= authorizedAtMs ||
    deadlineMs - authorizedAtMs > LIVE_SESSION_MAX_AGE_MS ||
    deadlineMs > Date.parse(state.binding.expiresAt)
  ) {
    fail("FRESH_PRODUCTION_ACTION_AUTHORIZATION_REQUIRED");
  }
  try {
    await verifyMountedExactCommitFirebasePackage(state.mountedPackage);
    await verifyFirebaseProductionSessionWorkspace(state.workspace);
  } catch (error) {
    await invalidateLiveSessionCapability({
      registry: preparedLiveSessions,
      capability: preparedCapability,
      state,
    });
    throw error;
  }
  detachLiveSessionCapability(preparedLiveSessions, preparedCapability, state);
  state.consumed = true;
  const authorizedBinding = deepFreeze({
    ...state.binding,
    authorizedAt,
    expiresAt: deadline,
  });
  const capability = Object.freeze(Object.create(null));
  const authorizedState = {
    ...state,
    binding: authorizedBinding,
    bindingSha256: canonicalSha256(authorizedBinding),
    consumed: false,
  };
  registerLiveSessionCapability(
    liveSessionCapabilities,
    capability,
    authorizedState,
  );
  return {
    capability,
    summary: Object.freeze({
      outcome: "authorized_in_same_process",
      bindingSha256: authorizedState.bindingSha256,
      expiresAt: deadline,
      operation: Object.freeze({ ...authorizedBinding.operation }),
      receiptPathSha256: authorizedBinding.receiptPathSha256,
      serializableCapability: false,
      remoteWriteAttempted: false,
    }),
  };
}

async function disposePreparedProductionLiveSession(preparedCapability) {
  return disposeActiveLiveSession({
    registry: preparedLiveSessions,
    capability: preparedCapability,
    inactiveCode: "PRODUCTION_PREPARED_SESSION_NOT_ACTIVE",
  });
}

async function disposeAuthorizedProductionLiveSession(capability) {
  return disposeActiveLiveSession({
    registry: liveSessionCapabilities,
    capability,
    inactiveCode: "PRODUCTION_AUTHORIZED_SESSION_NOT_ACTIVE",
  });
}

async function disposeRecoveryInspectionLiveSession(inspectionCapability) {
  return disposeActiveLiveSession({
    registry: recoveryInspectionCapabilities,
    capability: inspectionCapability,
    inactiveCode: "PRODUCTION_RECOVERY_SESSION_NOT_ACTIVE",
  });
}

async function disposeConsumedProductionLiveSession(session) {
  if (!consumedLiveSessions.has(session)) {
    fail("PRODUCTION_CONSUMED_SESSION_NOT_ACTIVE");
  }
  consumedLiveSessions.delete(session);
  try {
    await cleanupLiveSessionState(session);
  } catch (error) {
    fail("PRODUCTION_LIVE_SESSION_DISPOSAL_FAILED", { cause: error });
  }
  return Object.freeze({
    outcome: "disposed",
    bindingSha256: session.bindingSha256,
    remoteWriteAttempted: false,
  });
}

async function consumeProductionLiveSessionCapability(
  capability,
  expectedContext,
  { clock = () => new Date() } = {},
) {
  const state = liveSessionCapabilities.get(capability);
  const consumedAt = clock();
  const consumedAtMs =
    consumedAt instanceof Date ? consumedAt.getTime() : Number.NaN;
  await rejectAndCleanupExpiredLiveSession({
    registry: liveSessionCapabilities,
    capability,
    state,
    currentMs: consumedAtMs,
    code: "PRODUCTION_LIVE_SESSION_CAPABILITY_REJECTED",
  });
  if (
    !state ||
    state.consumed ||
    !(consumedAt instanceof Date) ||
    !Number.isFinite(consumedAtMs) ||
    canonicalSha256(state.context) !== canonicalSha256(expectedContext) ||
    state.binding.recovery.mode === "readback_first"
  ) {
    fail("PRODUCTION_LIVE_SESSION_CAPABILITY_REJECTED");
  }
  detachLiveSessionCapability(liveSessionCapabilities, capability, state);
  state.consumed = true;
  try {
    await verifyMountedExactCommitFirebasePackage(state.mountedPackage);
    await verifyFirebaseProductionSessionWorkspace(state.workspace);
  } catch (error) {
    await invalidateLiveSessionCapability({
      registry: liveSessionCapabilities,
      capability,
      state,
    });
    throw error;
  }
  const consumptionFacts = {
    schemaVersion: 1,
    kind: "spazaone_production_live_session_consumption",
    consumedAt: consumedAt.toISOString(),
    bindingSha256: state.bindingSha256,
    operationSha256: canonicalSha256(state.binding.operation),
    recoverySha256: canonicalSha256(state.binding.recovery),
    oneShot: true,
  };
  const consumedSession = {
    ...state,
    consumedAt: consumptionFacts.consumedAt,
    consumptionSha256: canonicalSha256(consumptionFacts),
  };
  consumedLiveSessions.add(consumedSession);
  return consumedSession;
}

async function inspectAuthorizedProductionLiveSession(
  capability,
  expectedContext,
  { clock = () => new Date() } = {},
) {
  const state = liveSessionCapabilities.get(capability);
  const inspectedAt = clock();
  const inspectedAtMs =
    inspectedAt instanceof Date ? inspectedAt.getTime() : Number.NaN;
  await rejectAndCleanupExpiredLiveSession({
    registry: liveSessionCapabilities,
    capability,
    state,
    currentMs: inspectedAtMs,
    code: "PRODUCTION_LIVE_SESSION_CAPABILITY_REJECTED",
  });
  if (
    !state ||
    state.consumed ||
    !(inspectedAt instanceof Date) ||
    !Number.isFinite(inspectedAtMs) ||
    canonicalSha256(state.context) !== canonicalSha256(expectedContext) ||
    state.binding.recovery.mode === "readback_first"
  ) {
    fail("PRODUCTION_LIVE_SESSION_CAPABILITY_REJECTED");
  }
  try {
    await verifyMountedExactCommitFirebasePackage(state.mountedPackage);
    await verifyFirebaseProductionSessionWorkspace(state.workspace);
  } catch (error) {
    await invalidateLiveSessionCapability({
      registry: liveSessionCapabilities,
      capability,
      state,
    });
    throw error;
  }
  return state;
}

function exactRecoveryReadback(value) {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !== Object.prototype ||
    !new Set(["complete", "incomplete"]).has(value.outcome)
  ) {
    fail("PRODUCTION_RECOVERY_READBACK_REJECTED");
  }
  const cycleId = value.cycleId === undefined ? null : String(value.cycleId);
  const expectedKeys =
    value.outcome === "complete"
      ? value.evidenceSha256 === undefined
        ? ["cycleId", "outcome"]
        : ["cycleId", "evidenceSha256", "outcome"]
      : [
          "acknowledgedPages",
          "continuationStateDigestSha256",
          "mappingScanComplete",
          "outcome",
          "productScanComplete",
          ...(cycleId === null ? [] : ["cycleId"]),
        ];
  if (
    canonicalJson(Object.keys(value).sort()) !==
      canonicalJson(expectedKeys.sort()) ||
    (value.outcome === "complete" &&
      !/^[a-f0-9]{32}$/.test(String(value.cycleId ?? ""))) ||
    (value.outcome === "incomplete" &&
      cycleId !== null &&
      !/^[a-f0-9]{32}$/.test(cycleId)) ||
    (value.outcome === "complete" &&
      value.evidenceSha256 !== undefined &&
      !SHA256.test(String(value.evidenceSha256))) ||
    (value.outcome === "incomplete" &&
      (!SHA256.test(String(value.continuationStateDigestSha256 ?? "")) ||
        !Number.isSafeInteger(value.acknowledgedPages) ||
        value.acknowledgedPages < 0 ||
        typeof value.productScanComplete !== "boolean" ||
        typeof value.mappingScanComplete !== "boolean" ||
        (value.mappingScanComplete && !value.productScanComplete)))
  ) {
    fail("PRODUCTION_RECOVERY_READBACK_REJECTED");
  }
  const facts = deepFreeze(structuredClone(value));
  return deepFreeze({
    facts,
    readbackSha256: canonicalSha256(facts),
  });
}

async function recordRecoveryInspection(
  inspectionCapability,
  { clock = () => new Date() } = {},
) {
  const state = recoveryInspectionCapabilities.get(inspectionCapability);
  const inspectedAt = clock();
  const inspectedAtMs =
    inspectedAt instanceof Date ? inspectedAt.getTime() : Number.NaN;
  await rejectAndCleanupExpiredLiveSession({
    registry: recoveryInspectionCapabilities,
    capability: inspectionCapability,
    state,
    currentMs: inspectedAtMs,
    code: "PRODUCTION_RECOVERY_READBACK_REJECTED",
  });
  if (
    !state ||
    state.consumed ||
    state.binding.recovery.mode !== "readback_first" ||
    state.recoveryReadback !== undefined ||
    state.recoveryInspectionStarted === true ||
    typeof state.recoveryReadbackProvider !== "function" ||
    !(inspectedAt instanceof Date) ||
    !Number.isFinite(inspectedAtMs)
  ) {
    fail("PRODUCTION_RECOVERY_READBACK_REJECTED");
  }
  try {
    await verifyMountedExactCommitFirebasePackage(state.mountedPackage);
    await verifyFirebaseProductionSessionWorkspace(state.workspace);
  } catch (error) {
    await invalidateLiveSessionCapability({
      registry: recoveryInspectionCapabilities,
      capability: inspectionCapability,
      state,
    });
    throw error;
  }
  const provider = state.recoveryReadbackProvider;
  state.recoveryInspectionStarted = true;
  state.recoveryReadbackProvider = undefined;
  let canonicalReadback;
  try {
    canonicalReadback = exactRecoveryReadback(
      await provider(
        Object.freeze({
          mountedPackage: state.mountedPackage,
          workspace: state.workspace,
        }),
      ),
    );
  } catch (error) {
    await invalidateLiveSessionCapability({
      registry: recoveryInspectionCapabilities,
      capability: inspectionCapability,
      state,
    });
    if (error instanceof ProductionExecutorError) throw error;
    fail("PRODUCTION_RECOVERY_READBACK_REJECTED", { cause: error });
  }
  const validatedReadback = canonicalReadback.facts;
  state.recoveryReadback = validatedReadback;
  state.recoveryReadbackSha256 = canonicalReadback.readbackSha256;
  state.recoveryInspectedAt = inspectedAt.toISOString();
  if (validatedReadback.outcome === "complete") {
    const result = Object.freeze({
      outcome: "recovered_readback",
      bindingSha256: state.bindingSha256,
      recoveryReadbackSha256: state.recoveryReadbackSha256,
      priorReceiptSha256: state.binding.recovery.priorReceiptSha256,
      remoteWriteAttempted: false,
      continuationAuthorizationRequired: false,
    });
    detachLiveSessionCapability(
      recoveryInspectionCapabilities,
      inspectionCapability,
      state,
    );
    state.consumed = true;
    await cleanupLiveSessionState(state);
    return result;
  }
  return Object.freeze({
    outcome: "continuation_authorization_required",
    bindingSha256: state.bindingSha256,
    recoveryReadbackSha256: state.recoveryReadbackSha256,
    priorReceiptSha256: state.binding.recovery.priorReceiptSha256,
    remoteWriteAttempted: false,
    continuationAuthorizationRequired: true,
  });
}

async function mintFreshReconciliationContinuationCapability(
  inspectionCapability,
  { authorizedAt, deadline, clock = () => new Date() },
) {
  const state = recoveryInspectionCapabilities.get(inspectionCapability);
  const validatedReadback = state?.recoveryReadback ?? null;
  const authorizedAtMs = Date.parse(authorizedAt);
  const deadlineMs = Date.parse(deadline);
  const current = clock();
  const nowMs = current instanceof Date ? current.getTime() : Number.NaN;
  await rejectAndCleanupExpiredLiveSession({
    registry: recoveryInspectionCapabilities,
    capability: inspectionCapability,
    state,
    currentMs: nowMs,
    code: "FRESH_RECONCILIATION_CONTINUATION_AUTHORIZATION_REQUIRED",
  });
  if (
    !state ||
    state.consumed ||
    validatedReadback?.outcome !== "incomplete" ||
    canonicalSha256(validatedReadback) !== state.recoveryReadbackSha256 ||
    !Number.isFinite(authorizedAtMs) ||
    !Number.isFinite(deadlineMs) ||
    !Number.isFinite(nowMs) ||
    authorizedAtMs > nowMs ||
    authorizedAtMs < Date.parse(state.recoveryInspectedAt) ||
    deadlineMs <= nowMs ||
    deadlineMs <= authorizedAtMs ||
    deadlineMs - authorizedAtMs > LIVE_SESSION_MAX_AGE_MS ||
    deadlineMs > Date.parse(state.binding.expiresAt)
  ) {
    fail("FRESH_RECONCILIATION_CONTINUATION_AUTHORIZATION_REQUIRED");
  }
  try {
    await verifyMountedExactCommitFirebasePackage(state.mountedPackage);
    await verifyFirebaseProductionSessionWorkspace(state.workspace);
  } catch (error) {
    await invalidateLiveSessionCapability({
      registry: recoveryInspectionCapabilities,
      capability: inspectionCapability,
      state,
    });
    throw error;
  }
  detachLiveSessionCapability(
    recoveryInspectionCapabilities,
    inspectionCapability,
    state,
  );
  state.consumed = true;
  const continuationBinding = deepFreeze({
    ...state.binding,
    authorizedAt,
    expiresAt: deadline,
    recovery: {
      mode: "continuation",
      priorReceiptSha256: state.binding.recovery.priorReceiptSha256,
      ...(validatedReadback.cycleId === undefined
        ? {}
        : { cycleId: validatedReadback.cycleId }),
      continuationStateDigestSha256:
        validatedReadback.continuationStateDigestSha256,
      recoveryReadbackSha256: state.recoveryReadbackSha256,
    },
  });
  const capability = Object.freeze(Object.create(null));
  const continuationState = {
    ...state,
    binding: continuationBinding,
    bindingSha256: canonicalSha256(continuationBinding),
    consumed: false,
    continuationReadback: validatedReadback,
    recoveryReadback: undefined,
    recoveryReadbackSha256: undefined,
    recoveryReadbackProvider: undefined,
    recoveryInspectedAt: undefined,
    recoveryInspectionStarted: undefined,
  };
  registerLiveSessionCapability(
    liveSessionCapabilities,
    capability,
    continuationState,
  );
  return {
    capability,
    summary: Object.freeze({
      outcome: "continuation_authorized_in_same_process",
      bindingSha256: continuationState.bindingSha256,
      expiresAt: deadline,
      priorReceiptSha256: continuationBinding.recovery.priorReceiptSha256,
      recoveryReadbackSha256:
        continuationBinding.recovery.recoveryReadbackSha256,
      remoteWriteAttempted: false,
    }),
  };
}

function extractActionAuthorizationArguments(argv) {
  const remaining = [];
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const authorizationArgument =
      argument === "--action-authorization-receipt-path" ||
      argument === "--expected-action-authorization-receipt-sha256";
    if (!authorizationArgument) {
      remaining.push(argument);
      continue;
    }
    // A file, digest, environment variable, or CLI argument must never become
    // a production capability. Only the private object minted and consumed in
    // this process can cross the writer boundary.
    fail("SERIALIZED_PRODUCTION_CAPABILITY_FORBIDDEN");
  }
  return { remaining };
}

function extractDeploymentRecoveryArguments(argv) {
  const remaining = [];
  const values = new Map();
  let recoverNeedsReview = false;
  const valueKeys = new Set([
    "prior-needs-review-receipt-path",
    "expected-prior-needs-review-receipt-path-sha256",
    "expected-prior-needs-review-receipt-sha256",
    "expected-prior-needs-review-receipt-file-sha256",
    "prior-target-receipt-path",
    "expected-prior-target-receipt-path-sha256",
    "expected-prior-target-receipt-file-sha256",
  ]);
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--recover-needs-review") {
      if (recoverNeedsReview) fail("PRODUCTION_RECOVERY_ARGUMENT_DUPLICATE");
      recoverNeedsReview = true;
      continue;
    }
    const key = argument.startsWith("--") ? argument.slice(2) : "";
    if (!valueKeys.has(key)) {
      remaining.push(argument);
      continue;
    }
    const value = argv[index + 1];
    if (values.has(key) || !value || value.startsWith("--")) {
      fail("PRODUCTION_RECOVERY_ARGUMENT_INVALID");
    }
    values.set(key, value);
    index += 1;
  }
  if (!recoverNeedsReview) {
    if (values.size > 0) fail("PRODUCTION_RECOVERY_ARGUMENT_INVALID");
    return { remaining, recovery: null };
  }
  const recoveryRecordPath = String(
    values.get("prior-needs-review-receipt-path") ?? "",
  );
  const recoveryRecordSha256 = String(
    values.get("expected-prior-needs-review-receipt-sha256") ?? "",
  );
  const recoveryRecordPathSha256 = String(
    values.get("expected-prior-needs-review-receipt-path-sha256") ?? "",
  );
  const recoveryRecordFileSha256 = String(
    values.get("expected-prior-needs-review-receipt-file-sha256") ?? "",
  );
  const targetPath = String(values.get("prior-target-receipt-path") ?? "");
  const targetPathSha256 = String(
    values.get("expected-prior-target-receipt-path-sha256") ?? "",
  );
  const expectedTargetFileSha256 = values.has(
    "expected-prior-target-receipt-file-sha256",
  )
    ? String(values.get("expected-prior-target-receipt-file-sha256"))
    : null;
  if (
    !path.isAbsolute(recoveryRecordPath) ||
    path.resolve(recoveryRecordPath) !== recoveryRecordPath ||
    !path.isAbsolute(targetPath) ||
    path.resolve(targetPath) !== targetPath ||
    !SHA256.test(recoveryRecordSha256) ||
    !SHA256.test(recoveryRecordPathSha256) ||
    !SHA256.test(recoveryRecordFileSha256) ||
    !SHA256.test(targetPathSha256) ||
    (expectedTargetFileSha256 !== null &&
      !SHA256.test(expectedTargetFileSha256)) ||
    sha256(recoveryRecordPath) !== recoveryRecordPathSha256 ||
    sha256(targetPath) !== targetPathSha256
  ) {
    fail("PRODUCTION_RECOVERY_ARGUMENT_INVALID");
  }
  return {
    remaining,
    recovery: Object.freeze({
      recoveryRecordPath,
      recoveryRecordSha256,
      recoveryRecordPathSha256,
      recoveryRecordFileSha256,
      targetPath,
      targetPathSha256,
      expectedTargetFileSha256,
    }),
  };
}

function now() {
  return new Date().toISOString();
}

function assertLiveSessionDispatchDeadline(session, clock = () => new Date()) {
  const current = clock();
  const currentMs = current instanceof Date ? current.getTime() : Number.NaN;
  if (
    !Number.isFinite(currentMs) ||
    currentMs >= Date.parse(session?.binding?.expiresAt ?? "")
  ) {
    fail("PRODUCTION_LIVE_SESSION_EXPIRED_BEFORE_DISPATCH");
  }
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

function nonNegativeInteger(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : null;
}

const RECONCILIATION_OUTBOX_STATUS_KEYS = Object.freeze([
  "pending",
  "retry",
  "processing",
  "submitted",
  "active",
  "deleted",
  "rejected",
  "unknown",
]);

function pendingOutboxStatusCount(counts) {
  return counts.pending + counts.retry + counts.processing + counts.submitted;
}

function drainedOutboxEvidence(value) {
  const counts = value?.outboxStatusCounts;
  return (
    value?.outboxCountsVerified === true &&
    nonNegativeInteger(value?.totalOutboxDocuments) !== null &&
    counts &&
    canonicalJson(Object.keys(counts).sort()) ===
      canonicalJson([...RECONCILIATION_OUTBOX_STATUS_KEYS].sort()) &&
    RECONCILIATION_OUTBOX_STATUS_KEYS.every(
      (key) => nonNegativeInteger(counts[key]) !== null,
    ) &&
    pendingOutboxStatusCount(counts) === 0 &&
    counts.unknown === 0 &&
    RECONCILIATION_OUTBOX_STATUS_KEYS.reduce(
      (sum, key) => sum + counts[key],
      0,
    ) === value.totalOutboxDocuments
  );
}

function redactedReconciliationPage(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const outcomes = new Set([
    "page",
    "product_scan_complete",
    "scan_complete",
    "verification_incomplete",
    "complete",
  ]);
  const phases = new Set(["products", "mappings", "verify", "complete"]);
  const cycleId = String(value.cycleId ?? "");
  const outcome = String(value.outcome ?? "");
  const phase = String(value.phase ?? "");
  const continuationStateDigestSha256 = String(
    value.continuationStateDigestSha256 ?? "",
  );
  const pendingOutboxJobs = nonNegativeInteger(value.pendingOutboxJobs);
  const totalOutboxDocuments = nonNegativeInteger(value.totalOutboxDocuments);
  const outboxCountsVerified = value.outboxCountsVerified === true;
  const incompleteMerchants = nonNegativeInteger(value.incompleteMerchants);
  const malformedMappings = nonNegativeInteger(value.malformedMappings);
  const deployedAppCommit = String(value.deployedAppCommit ?? "");
  const targetConfigurationDigestSha256 = String(
    value.targetConfigurationDigestSha256 ?? "",
  );
  const firebaseProjectId = String(value.firebaseProjectId ?? "");
  const catalogId = String(value.catalogId ?? "");
  const senderPhoneNumberId = String(value.senderPhoneNumberId ?? "");
  const counts = value.outboxStatusCounts;
  const outboxStatusCounts =
    counts && typeof counts === "object" && !Array.isArray(counts)
      ? Object.fromEntries(
          RECONCILIATION_OUTBOX_STATUS_KEYS.map((key) => [
            key,
            nonNegativeInteger(counts[key]),
          ]),
        )
      : null;
  const terminal = outcome === "complete";
  const cycleStartedAt = String(value.cycleStartedAt ?? "");
  const cycleCompletedAt = String(value.cycleCompletedAt ?? "");
  const mutationGenerationDigestSha256 = String(
    value.mutationGenerationDigestSha256 ?? "",
  );
  const validTerminalTimes =
    Number.isFinite(Date.parse(cycleStartedAt)) &&
    Number.isFinite(Date.parse(cycleCompletedAt)) &&
    Date.parse(cycleStartedAt) <= Date.parse(cycleCompletedAt);
  const completeOutboxCounts =
    outboxStatusCounts &&
    canonicalJson(Object.keys(counts).sort()) ===
      canonicalJson([...RECONCILIATION_OUTBOX_STATUS_KEYS].sort()) &&
    Object.values(outboxStatusCounts).every((count) => count !== null);
  const hasOutboxEvidence =
    value.outboxStatusCounts !== undefined ||
    value.totalOutboxDocuments !== undefined ||
    value.outboxCountsVerified !== undefined;
  if (
    !outcomes.has(outcome) ||
    !phases.has(phase) ||
    !/^[a-f0-9]{32}$/.test(cycleId) ||
    (!terminal && !SHA256.test(continuationStateDigestSha256)) ||
    (terminal && continuationStateDigestSha256) ||
    (terminal && !validTerminalTimes) ||
    (terminal && !SHA256.test(mutationGenerationDigestSha256)) ||
    (!terminal && mutationGenerationDigestSha256) ||
    pendingOutboxJobs === null ||
    incompleteMerchants === null ||
    malformedMappings === null ||
    (hasOutboxEvidence &&
      (!completeOutboxCounts || totalOutboxDocuments === null)) ||
    (terminal &&
      (!completeOutboxCounts ||
        totalOutboxDocuments === null ||
        !outboxCountsVerified)) ||
    !/^[a-f0-9]{40}$/.test(deployedAppCommit) ||
    !SHA256.test(targetConfigurationDigestSha256) ||
    firebaseProjectId !== PRODUCTION_FIREBASE_PROJECT_ID ||
    catalogId !== PRODUCTION_NATIVE_CATALOG_TARGET.catalogId ||
    senderPhoneNumberId !==
      PRODUCTION_NATIVE_CATALOG_TARGET.senderPhoneNumberId ||
    (completeOutboxCounts &&
      Object.values(outboxStatusCounts).reduce(
        (sum, count) => sum + count,
        0,
      ) !== totalOutboxDocuments) ||
    (completeOutboxCounts &&
      pendingOutboxStatusCount(outboxStatusCounts) !== pendingOutboxJobs)
  ) {
    return null;
  }
  return {
    outcome,
    phase,
    cycleId,
    continuationStateDigestSha256,
    pendingOutboxJobs,
    incompleteMerchants,
    malformedMappings,
    cycleComplete: value.cycleComplete === true,
    catalogComplete: value.catalogComplete === true,
    stabilityVerified: value.stabilityVerified === true,
    sourceCountsVerified: value.sourceCountsVerified === true,
    ...(completeOutboxCounts
      ? { totalOutboxDocuments, outboxCountsVerified }
      : {}),
    completionDigest: String(value.completionDigest ?? ""),
    ...(terminal
      ? {
          cycleStartedAt,
          cycleCompletedAt,
          mutationGenerationDigestSha256,
        }
      : {}),
    deployedAppCommit,
    targetConfigurationDigestSha256,
    firebaseProjectId,
    catalogId,
    senderPhoneNumberId,
    ...(completeOutboxCounts ? { outboxStatusCounts } : {}),
  };
}

function safeReconciliationProviderCode(value) {
  const code = String(value ?? "").toUpperCase();
  return /^[A-Z][A-Z0-9_]{0,79}$/.test(code) ? code : "UNCLASSIFIED";
}

async function readReconciliationResponseJson(response) {
  const responseAmbiguous =
    response.ok ||
    response.status >= 500 ||
    [408, 425, 429].includes(response.status);
  const declaredLength = Number(response.headers?.get?.("content-length"));
  if (
    Number.isFinite(declaredLength) &&
    declaredLength > MAX_RECONCILIATION_RESPONSE_BYTES
  ) {
    throw new ReconciliationOperatorError("RECONCILIATION_RESPONSE_TOO_LARGE", {
      ambiguous: responseAmbiguous,
    });
  }
  let responseText = "";
  try {
    responseText = await response.text();
  } catch (_) {
    throw new ReconciliationOperatorError(
      "RECONCILIATION_RESPONSE_UNREADABLE",
      { ambiguous: responseAmbiguous },
    );
  }
  if (
    Buffer.byteLength(responseText, "utf8") > MAX_RECONCILIATION_RESPONSE_BYTES
  ) {
    responseText = "";
    throw new ReconciliationOperatorError("RECONCILIATION_RESPONSE_TOO_LARGE", {
      ambiguous: responseAmbiguous,
    });
  }
  try {
    const parsed = JSON.parse(responseText);
    responseText = "";
    return parsed;
  } catch (_) {
    responseText = "";
    throw new ReconciliationOperatorError("RECONCILIATION_RESPONSE_INVALID", {
      ambiguous: responseAmbiguous,
    });
  }
}

async function requestPrivateReconciliationJson({
  fetchImpl,
  token,
  body,
  requestTimeoutMs,
}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), requestTimeoutMs);
  let response;
  let headerValue = "";
  try {
    headerValue = token.toString("utf8");
    response = await fetchImpl(RECONCILIATION_FUNCTION_URL, {
      method: "POST",
      redirect: "error",
      headers: {
        "content-type": "application/json",
        "x-pasella-bot-token": headerValue,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (_) {
    throw new ReconciliationOperatorError("RECONCILIATION_HTTP_AMBIGUOUS", {
      ambiguous: true,
    });
  } finally {
    headerValue = "";
    clearTimeout(timer);
  }
  const payload = await readReconciliationResponseJson(response);
  if (!response.ok) {
    const providerCode = safeReconciliationProviderCode(payload?.code);
    const ambiguous =
      response.status >= 500 || [408, 425, 429].includes(response.status);
    throw new ReconciliationOperatorError(
      `RECONCILIATION_HTTP_${response.status}_${providerCode}`,
      { ambiguous },
    );
  }
  return payload;
}

async function requestPrivateReconciliationPage(options) {
  const page = redactedReconciliationPage(
    await requestPrivateReconciliationJson(options),
  );
  if (!page) {
    throw new ReconciliationOperatorError("RECONCILIATION_RESPONSE_INVALID", {
      ambiguous: true,
    });
  }
  return page;
}

function redactedReconciliationRecoveryState(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const phase = String(value.phase ?? "");
  const cycleId = value.cycleId === undefined ? null : String(value.cycleId);
  const acknowledgedPages = nonNegativeInteger(value.acknowledgedPages);
  const continuationStateDigestSha256 = String(
    value.continuationStateDigestSha256 ?? "",
  );
  const deployedAppCommit = String(value.deployedAppCommit ?? "");
  const targetConfigurationDigestSha256 = String(
    value.targetConfigurationDigestSha256 ?? "",
  );
  const productScanComplete = value.productScanComplete;
  const mappingScanComplete = value.mappingScanComplete;
  const completion =
    phase === "complete"
      ? redactedReconciliationPage({
          ...value,
          outcome: "complete",
          phase: "complete",
          continuationStateDigestSha256: "",
        })
      : null;
  if (
    value.outcome !== "recovery_state" ||
    !new Set(["products", "mappings", "verify", "complete"]).has(phase) ||
    (cycleId !== null && !/^[a-f0-9]{32}$/.test(cycleId)) ||
    (phase === "complete" && cycleId === null) ||
    acknowledgedPages === null ||
    !SHA256.test(continuationStateDigestSha256) ||
    !/^[a-f0-9]{40}$/.test(deployedAppCommit) ||
    !SHA256.test(targetConfigurationDigestSha256) ||
    typeof productScanComplete !== "boolean" ||
    typeof mappingScanComplete !== "boolean" ||
    (mappingScanComplete && !productScanComplete) ||
    (phase === "complete" &&
      (!completion || !productScanComplete || !mappingScanComplete)) ||
    value.firebaseProjectId !== PRODUCTION_FIREBASE_PROJECT_ID ||
    value.catalogId !== PRODUCTION_NATIVE_CATALOG_TARGET.catalogId ||
    value.senderPhoneNumberId !==
      PRODUCTION_NATIVE_CATALOG_TARGET.senderPhoneNumberId
  ) {
    return null;
  }
  return {
    ...(cycleId === null ? {} : { cycleId }),
    phase,
    acknowledgedPages,
    productScanComplete,
    mappingScanComplete,
    continuationStateDigestSha256,
    deployedAppCommit,
    targetConfigurationDigestSha256,
    ...(completion ? { completion } : {}),
  };
}

async function requestPrivateReconciliationRecoveryState(options) {
  const state = redactedReconciliationRecoveryState(
    await requestPrivateReconciliationJson(options),
  );
  if (!state) {
    throw new ReconciliationOperatorError(
      "RECONCILIATION_RECOVERY_RESPONSE_INVALID",
      { ambiguous: false, needsReview: true },
    );
  }
  return state;
}

function reconciliationIso(clock) {
  const value = clock();
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) {
    throw new ReconciliationOperatorError("OPERATOR_CLOCK_INVALID");
  }
  return date.toISOString();
}

function finalizePrivateReconciliationArtifact(input) {
  const startedAtMs = Date.parse(input.startedAt);
  const completedAtMs = Date.parse(input.completedAt);
  const verifiedAtMs = Date.parse(input.verifiedAt);
  if (
    !Number.isFinite(startedAtMs) ||
    !Number.isFinite(completedAtMs) ||
    !Number.isFinite(verifiedAtMs) ||
    startedAtMs > completedAtMs ||
    completedAtMs > verifiedAtMs ||
    !/^[a-f0-9]{40}$/.test(input.appCommit) ||
    !SHA256.test(input.targetConfigurationDigestSha256) ||
    !/^[a-f0-9]{32}$/.test(input.cycleId) ||
    !SHA256.test(input.mutationGenerationDigestSha256) ||
    !SHA256.test(input.completionDigest) ||
    input.productScanComplete !== true ||
    input.mappingScanComplete !== true ||
    !drainedOutboxEvidence(input)
  ) {
    throw new ReconciliationOperatorError("RECONCILIATION_RECEIPT_INVALID");
  }
  const receipt = {
    schemaVersion: 1,
    kind: "spazaone_catalog_full_reconciliation",
    verifiedAt: input.verifiedAt,
    startedAt: input.startedAt,
    completedAt: input.completedAt,
    firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
    catalogId: PRODUCTION_NATIVE_CATALOG_TARGET.catalogId,
    senderPhoneNumberId: PRODUCTION_NATIVE_CATALOG_TARGET.senderPhoneNumberId,
    appCommit: input.appCommit,
    targetConfigurationDigestSha256: input.targetConfigurationDigestSha256,
    cycleId: input.cycleId,
    deliveryEnabled: false,
    syncEnabled: true,
    scanScope: "all_eligible_merchants",
    cycleComplete: true,
    productScanComplete: true,
    mappingScanComplete: true,
    stabilityVerified: true,
    sourceCountsVerified: true,
    outboxDrained: true,
    outboxPendingCount: input.outboxStatusCounts.pending,
    outboxRetryCount: input.outboxStatusCounts.retry,
    outboxProcessingCount: input.outboxStatusCounts.processing,
    outboxSubmittedCount: input.outboxStatusCounts.submitted,
    outboxActiveCount: input.outboxStatusCounts.active,
    outboxDeletedCount: input.outboxStatusCounts.deleted,
    outboxRejectedCount: input.outboxStatusCounts.rejected,
    outboxUnknownCount: input.outboxStatusCounts.unknown,
    outboxTotalCount: input.totalOutboxDocuments,
    outboxCountsVerified: true,
    catalogComplete: true,
    setEqualityVerified: true,
    mutationGenerationDigestSha256: input.mutationGenerationDigestSha256,
    completionDigest: input.completionDigest,
    incompleteMerchantCount: 0,
    malformedMappingCount: 0,
  };
  const finalized = {
    ...receipt,
    redactedReceiptSha256: canonicalSha256(receipt),
  };
  if (
    canonicalJson(Object.keys(finalized)) !==
    canonicalJson(FINALIZED_RECONCILIATION_ARTIFACT_KEYS)
  ) {
    throw new ReconciliationOperatorError("RECONCILIATION_RECEIPT_INVALID");
  }
  try {
    validateFinalizedReconciliationArtifact(finalized, {
      expectedAppCommit: input.appCommit,
      expectedTargetConfigurationDigestSha256:
        input.targetConfigurationDigestSha256,
    });
  } catch (_) {
    throw new ReconciliationOperatorError("RECONCILIATION_RECEIPT_INVALID");
  }
  return finalized;
}

function exactReconciliationContinuationState(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const requiredKeys = [
    "acknowledgedPages",
    "continuationStateDigestSha256",
    "mappingScanComplete",
    "productScanComplete",
  ];
  const cycleId = value.cycleId === undefined ? null : String(value.cycleId);
  const expectedKeys =
    cycleId === null ? requiredKeys : [...requiredKeys, "cycleId"];
  if (
    canonicalJson(Object.keys(value).sort()) !==
      canonicalJson(expectedKeys.sort()) ||
    (cycleId !== null && !/^[a-f0-9]{32}$/.test(cycleId)) ||
    !SHA256.test(String(value.continuationStateDigestSha256 ?? "")) ||
    nonNegativeInteger(value.acknowledgedPages) === null ||
    typeof value.productScanComplete !== "boolean" ||
    typeof value.mappingScanComplete !== "boolean" ||
    (value.mappingScanComplete && !value.productScanComplete)
  ) {
    return null;
  }
  return Object.freeze({
    ...(cycleId === null ? {} : { cycleId }),
    continuationStateDigestSha256: value.continuationStateDigestSha256,
    acknowledgedPages: value.acknowledgedPages,
    productScanComplete: value.productScanComplete,
    mappingScanComplete: value.mappingScanComplete,
  });
}

async function runPrivateFullCatalogReconciliation({
  execute = false,
  expectedAppCommit,
  expectedCurrentMainCommit,
  candidateManifestPath,
  expectedCandidateManifestSha256,
  reviewedResume = false,
  pageSize = 200,
  pollMs = 65_000,
  maxSteps = 10_000,
  maxElapsedMs = 24 * 60 * 60 * 1000,
  requestTimeoutMs = 570_000,
  continuationState = null,
  onBeforeFirstWrite,
  fetchImpl = global.fetch,
  verifyToolchain = assertPinnedProductionToolchain,
  verifyCandidateManifest = loadAndValidateProductionCandidateManifest,
  resolveSecret = resolvePasellaBotToken,
  resolveCommit = resolveAuthorityAppCommit,
  sleep = (milliseconds) =>
    new Promise((resolve) => setTimeout(resolve, milliseconds)),
  clock = () => new Date(),
} = {}) {
  if (execute !== true) {
    throw new ReconciliationOperatorError("RECONCILIATION_EXECUTE_REQUIRED");
  }
  if (!/^[a-f0-9]{40}$/.test(String(expectedAppCommit ?? ""))) {
    throw new ReconciliationOperatorError("EXPECTED_APP_COMMIT_INVALID");
  }
  if (
    !/^[a-f0-9]{40}$/.test(String(expectedCurrentMainCommit ?? "")) ||
    expectedCurrentMainCommit !== FROZEN_APP_MAIN_COMMIT
  ) {
    throw new ReconciliationOperatorError(
      "EXPECTED_CURRENT_MAIN_COMMIT_INVALID",
    );
  }
  const continuation =
    continuationState === null
      ? null
      : exactReconciliationContinuationState(continuationState);
  if (
    (continuationState !== null && !continuation) ||
    (continuation !== null && reviewedResume !== true) ||
    (continuation === null &&
      reviewedResume !== true &&
      typeof onBeforeFirstWrite !== "function") ||
    (continuation !== null && typeof onBeforeFirstWrite !== "function") ||
    (continuation === null &&
      reviewedResume === true &&
      onBeforeFirstWrite !== undefined)
  ) {
    throw new ReconciliationOperatorError(
      "RECONCILIATION_EXECUTION_CAPABILITY_INVALID",
    );
  }
  if (
    typeof candidateManifestPath !== "string" ||
    !path.isAbsolute(candidateManifestPath) ||
    path.resolve(candidateManifestPath) !== candidateManifestPath ||
    !SHA256.test(String(expectedCandidateManifestSha256 ?? ""))
  ) {
    throw new ReconciliationOperatorError(
      "PRODUCTION_CANDIDATE_MANIFEST_REFERENCE_INVALID",
    );
  }
  if (!Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > 200) {
    throw new ReconciliationOperatorError("RECONCILIATION_PAGE_SIZE_INVALID");
  }
  if (
    !Number.isSafeInteger(maxSteps) ||
    maxSteps < 1 ||
    !Number.isSafeInteger(maxElapsedMs) ||
    maxElapsedMs < 1 ||
    !Number.isSafeInteger(requestTimeoutMs) ||
    requestTimeoutMs < 1 ||
    !Number.isSafeInteger(pollMs) ||
    pollMs < 0 ||
    typeof fetchImpl !== "function"
  ) {
    throw new ReconciliationOperatorError(
      "RECONCILIATION_OPERATOR_CONFIG_INVALID",
    );
  }
  try {
    await verifyToolchain();
  } catch (_) {
    throw new ReconciliationOperatorError(
      "PRODUCTION_TOOLCHAIN_PREFLIGHT_FAILED",
    );
  }
  const operationInputSha256 = reconciliationOperationInputSha256({
    pageSize,
    pollMs,
    maxSteps,
    maxElapsedMs,
    requestTimeoutMs,
  });
  const resolveExactCommit = async () => {
    const resolvedCommit = await resolveCommit({
      expectedCandidateCommit: expectedAppCommit,
      expectedCurrentMainCommit,
    });
    try {
      await verifyCandidateManifest({
        manifestPath: candidateManifestPath,
        expectedManifestSha256: expectedCandidateManifestSha256,
        expectedAppCommit,
        expectedCurrentMainCommit,
        expectedOperation: {
          kind: "full_reconciliation",
          lane: "full-reconciliation",
          selector: "functions:runWhatsAppCatalogFullReconciliationBotHttp",
          inputSha256: operationInputSha256,
        },
      });
    } catch (_) {
      throw new ReconciliationOperatorError(
        "PRODUCTION_CANDIDATE_MANIFEST_INVALID",
      );
    }
    return resolvedCommit;
  };
  const appCommit = await resolveExactCommit();
  if (appCommit !== expectedAppCommit) {
    throw new ReconciliationOperatorError("EXPECTED_APP_COMMIT_MISMATCH");
  }
  const startedAt = reconciliationIso(clock);
  const startedAtMs = Date.parse(startedAt);
  const targetConfigurationDigestSha256 =
    nativeCatalogTargetConfigurationDigestSha256();
  const token = await resolveSecret();
  if (!Buffer.isBuffer(token)) {
    throw new ReconciliationOperatorError("BOT_SECRET_RESOLUTION_INVALID");
  }

  let cycleId = continuation?.cycleId ?? "";
  let continuationStateDigestSha256 =
    continuation?.continuationStateDigestSha256 ?? "";
  let acknowledgedPages = continuation?.acknowledgedPages ?? 0;
  let productScanComplete = continuation?.productScanComplete ?? false;
  let mappingScanComplete = continuation?.mappingScanComplete ?? false;
  let firstWriteStarted = false;
  const serverStateRequiresReview = () =>
    reviewedResume || acknowledgedPages > 0;
  try {
    const deploymentBinding = {
      expectedAppCommit: appCommit,
      expectedTargetConfigurationDigestSha256: targetConfigurationDigestSha256,
    };
    if (reviewedResume && continuation === null) {
      let recovery;
      try {
        if ((await resolveExactCommit()) !== appCommit)
          throw new Error("changed");
        recovery = await requestPrivateReconciliationRecoveryState({
          fetchImpl,
          token,
          body: { ...deploymentBinding, operation: "inspect_recovery" },
          requestTimeoutMs,
        });
      } catch (error) {
        const code =
          error instanceof ReconciliationOperatorError
            ? error.code
            : "RECONCILIATION_RECOVERY_INSPECTION_NEEDS_REVIEW";
        throw new ReconciliationOperatorError(code, {
          ambiguous:
            error instanceof ReconciliationOperatorError
              ? error.ambiguous
              : false,
          needsReview: true,
        });
      }
      if (
        recovery.deployedAppCommit !== appCommit ||
        recovery.targetConfigurationDigestSha256 !==
          targetConfigurationDigestSha256
      ) {
        throw new ReconciliationOperatorError(
          "RECONCILIATION_RECOVERY_BINDING_NEEDS_REVIEW",
          { ambiguous: false, needsReview: true },
        );
      }
      continuationStateDigestSha256 = recovery.continuationStateDigestSha256;
      acknowledgedPages = recovery.acknowledgedPages;
      productScanComplete = recovery.productScanComplete;
      mappingScanComplete = recovery.mappingScanComplete;
      if (recovery.completion) {
        const completion = recovery.completion;
        if (
          completion.cycleComplete !== true ||
          completion.catalogComplete !== true ||
          completion.stabilityVerified !== true ||
          completion.sourceCountsVerified !== true ||
          completion.pendingOutboxJobs !== 0 ||
          !drainedOutboxEvidence(completion) ||
          completion.incompleteMerchants !== 0 ||
          completion.malformedMappings !== 0 ||
          !SHA256.test(completion.mutationGenerationDigestSha256) ||
          !SHA256.test(completion.completionDigest)
        ) {
          throw new ReconciliationOperatorError(
            "RECONCILIATION_RECOVERED_COMPLETION_EVIDENCE_INVALID",
            { ambiguous: false, needsReview: true },
          );
        }
        return finalizePrivateReconciliationArtifact({
          verifiedAt: reconciliationIso(clock),
          startedAt: completion.cycleStartedAt,
          completedAt: completion.cycleCompletedAt,
          appCommit,
          targetConfigurationDigestSha256,
          cycleId: completion.cycleId,
          mutationGenerationDigestSha256:
            completion.mutationGenerationDigestSha256,
          completionDigest: completion.completionDigest,
          productScanComplete,
          mappingScanComplete,
          totalOutboxDocuments: completion.totalOutboxDocuments,
          outboxCountsVerified: completion.outboxCountsVerified,
          outboxStatusCounts: completion.outboxStatusCounts,
        });
      }
      return Object.freeze({
        outcome: "continuation_authorization_required",
        ...(recovery.cycleId === undefined
          ? {}
          : { cycleId: recovery.cycleId }),
        continuationStateDigestSha256: recovery.continuationStateDigestSha256,
        acknowledgedPages: recovery.acknowledgedPages,
        productScanComplete: recovery.productScanComplete,
        mappingScanComplete: recovery.mappingScanComplete,
      });
    }

    for (let step = 0; step < maxSteps; step += 1) {
      if (Date.now() - startedAtMs > maxElapsedMs) {
        throw new ReconciliationOperatorError(
          serverStateRequiresReview()
            ? "RECONCILIATION_ELAPSED_LIMIT_NEEDS_REVIEW"
            : "RECONCILIATION_ELAPSED_LIMIT_REACHED",
          {
            ambiguous: serverStateRequiresReview(),
            needsReview: serverStateRequiresReview(),
          },
        );
      }
      const body = continuationStateDigestSha256
        ? {
            ...deploymentBinding,
            operation: "continue",
            expectedContinuationStateDigestSha256:
              continuationStateDigestSha256,
          }
        : { ...deploymentBinding, operation: "start", pageSize };
      try {
        if ((await resolveExactCommit()) !== appCommit)
          throw new Error("changed");
      } catch (_) {
        throw new ReconciliationOperatorError(
          serverStateRequiresReview()
            ? "RECONCILIATION_AUTHORITY_RECHECK_NEEDS_REVIEW"
            : "APP_AUTHORITY_CHANGED",
          {
            ambiguous: serverStateRequiresReview(),
            needsReview: serverStateRequiresReview(),
          },
        );
      }
      let page;
      try {
        if (!firstWriteStarted) {
          await onBeforeFirstWrite();
          firstWriteStarted = true;
        }
        page = await requestPrivateReconciliationPage({
          fetchImpl,
          token,
          body,
          requestTimeoutMs,
        });
      } catch (error) {
        if (serverStateRequiresReview()) {
          throw new ReconciliationOperatorError(
            error instanceof ReconciliationOperatorError
              ? error.code
              : "RECONCILIATION_PAGE_NEEDS_REVIEW",
            { ambiguous: true, needsReview: true },
          );
        }
        throw error;
      }
      if (
        page.deployedAppCommit !== appCommit ||
        page.targetConfigurationDigestSha256 !==
          targetConfigurationDigestSha256 ||
        page.firebaseProjectId !== PRODUCTION_FIREBASE_PROJECT_ID ||
        page.catalogId !== PRODUCTION_NATIVE_CATALOG_TARGET.catalogId ||
        page.senderPhoneNumberId !==
          PRODUCTION_NATIVE_CATALOG_TARGET.senderPhoneNumberId
      ) {
        throw new ReconciliationOperatorError(
          "RECONCILIATION_DEPLOYMENT_BINDING_MISMATCH",
          { ambiguous: true },
        );
      }
      if (cycleId && page.cycleId !== cycleId) {
        throw new ReconciliationOperatorError("RECONCILIATION_CYCLE_CHANGED", {
          ambiguous: true,
        });
      }
      cycleId = page.cycleId;
      continuationStateDigestSha256 = page.continuationStateDigestSha256;
      acknowledgedPages += 1;
      if (page.outcome === "product_scan_complete") {
        productScanComplete = true;
      }
      if (page.outcome === "scan_complete") mappingScanComplete = true;

      if (page.outcome === "complete") {
        if (
          page.phase !== "complete" ||
          page.cycleComplete !== true ||
          page.catalogComplete !== true ||
          page.stabilityVerified !== true ||
          page.sourceCountsVerified !== true ||
          page.pendingOutboxJobs !== 0 ||
          !drainedOutboxEvidence(page) ||
          page.incompleteMerchants !== 0 ||
          page.malformedMappings !== 0 ||
          !productScanComplete ||
          !mappingScanComplete ||
          !SHA256.test(page.mutationGenerationDigestSha256) ||
          !SHA256.test(page.completionDigest)
        ) {
          throw new ReconciliationOperatorError(
            "RECONCILIATION_COMPLETION_EVIDENCE_INVALID",
            { ambiguous: true },
          );
        }
        return finalizePrivateReconciliationArtifact({
          verifiedAt: reconciliationIso(clock),
          startedAt: page.cycleStartedAt,
          completedAt: page.cycleCompletedAt,
          appCommit,
          targetConfigurationDigestSha256,
          cycleId,
          mutationGenerationDigestSha256: page.mutationGenerationDigestSha256,
          completionDigest: page.completionDigest,
          productScanComplete,
          mappingScanComplete,
          totalOutboxDocuments: page.totalOutboxDocuments,
          outboxCountsVerified: page.outboxCountsVerified,
          outboxStatusCounts: page.outboxStatusCounts,
        });
      }
      if (
        page.outcome === "verification_incomplete" ||
        page.pendingOutboxJobs > 0
      ) {
        await sleep(pollMs);
      }
    }
    throw new ReconciliationOperatorError(
      serverStateRequiresReview()
        ? "RECONCILIATION_STEP_LIMIT_NEEDS_REVIEW"
        : "RECONCILIATION_STEP_LIMIT_REACHED",
      {
        ambiguous: serverStateRequiresReview(),
        needsReview: serverStateRequiresReview(),
      },
    );
  } finally {
    cycleId = "";
    continuationStateDigestSha256 = "";
    token.fill(0);
  }
}

function readControllingTtyLine(display) {
  let fd;
  const bytes = Buffer.alloc(MAX_TTY_RESPONSE_BYTES);
  let length = 0;
  try {
    fd = openSync(
      CONTROLLING_TTY_PATH,
      fsConstants.O_RDWR | fsConstants.O_NOFOLLOW | (fsConstants.O_NOCTTY ?? 0),
    );
    if (!isatty(fd)) fail("PRODUCTION_ACTION_CONTROLLING_TTY_REQUIRED");
    const output = Buffer.from(
      `${JSON.stringify(display, null, 2)}\nType the exact authorization challenge, then press Return:\n> `,
      "utf8",
    );
    try {
      writeSync(fd, output);
    } finally {
      output.fill(0);
    }
    const one = Buffer.alloc(1);
    try {
      while (length < bytes.length) {
        const count = readSync(fd, one, 0, 1, null);
        if (count !== 1) fail("PRODUCTION_ACTION_TTY_RESPONSE_INVALID");
        if (one[0] === 0x0a) break;
        bytes[length] = one[0];
        length += 1;
      }
    } finally {
      one.fill(0);
    }
    if (length === bytes.length) {
      fail("PRODUCTION_ACTION_TTY_RESPONSE_INVALID");
    }
    if (length > 0 && bytes[length - 1] === 0x0d) length -= 1;
    const response = bytes.subarray(0, length).toString("utf8");
    if (
      Buffer.byteLength(response, "utf8") !== length ||
      /[\u0000-\u001f\u007f]/u.test(response)
    ) {
      fail("PRODUCTION_ACTION_TTY_RESPONSE_INVALID");
    }
    return response;
  } catch (error) {
    if (error instanceof ProductionExecutorError) throw error;
    fail("PRODUCTION_ACTION_CONTROLLING_TTY_REQUIRED", { cause: error });
  } finally {
    bytes.fill(0);
    if (fd !== undefined) {
      try {
        closeSync(fd);
      } catch (_) {
        // Preserve the primary authorization result.
      }
    }
  }
}

function productionActionChallenge(bindingSha256) {
  if (!SHA256.test(String(bindingSha256 ?? ""))) {
    fail("PRODUCTION_ACTION_BINDING_INVALID");
  }
  return `AUTHORIZE SPAZA ONE PRODUCTION ${bindingSha256}`;
}

async function conductProductionActionCeremony({
  prepared,
  authorize,
  extraBinding = null,
  ttyExchange = readControllingTtyLine,
  clock = () => new Date(),
}) {
  if (
    !prepared?.capability ||
    !SHA256.test(String(prepared?.summary?.bindingSha256 ?? "")) ||
    typeof authorize !== "function" ||
    typeof ttyExchange !== "function"
  ) {
    fail("PRODUCTION_ACTION_CEREMONY_INVALID");
  }
  const presentedAt = clock();
  const presentedAtMs =
    presentedAt instanceof Date ? presentedAt.getTime() : Number.NaN;
  const sessionExpiresAtMs = Date.parse(prepared.summary.expiresAt);
  if (!Number.isFinite(presentedAtMs) || !Number.isFinite(sessionExpiresAtMs)) {
    fail("PRODUCTION_ACTION_CEREMONY_CLOCK_INVALID");
  }
  const deadline = new Date(
    Math.min(
      sessionExpiresAtMs,
      presentedAtMs + ACTION_AUTHORIZATION_WINDOW_MS,
    ),
  ).toISOString();
  if (Date.parse(deadline) <= presentedAtMs) {
    fail("PRODUCTION_ACTION_CEREMONY_EXPIRED");
  }
  const challengeBindingSha256 = canonicalSha256({
    liveSessionBindingSha256: prepared.summary.bindingSha256,
    deadline,
    extraBinding,
  });
  const challenge = productionActionChallenge(challengeBindingSha256);
  const display = deepFreeze({
    schemaVersion: 1,
    kind: "spazaone_production_action_authorization",
    authority: { ...PRODUCTION_WRITE_AUTHORITY },
    target: { ...PRODUCTION_WRITE_TARGET },
    bindingSha256: prepared.summary.bindingSha256,
    candidate: {
      appCommit: prepared.summary.appCommit,
      governedMainCommit: prepared.summary.governedMainCommit,
      gitTreeSha1: prepared.summary.gitTreeSha1,
      gitArchiveSha256: prepared.summary.gitArchiveSha256,
      packageInventorySha256: prepared.summary.packageInventorySha256,
      candidateManifestSha256: prepared.summary.candidateManifestSha256,
      reviewedEvidenceReceiptSetSha256:
        prepared.summary.reviewedEvidenceReceiptSetSha256,
      targetConfigurationDigestSha256:
        prepared.summary.targetConfigurationDigestSha256,
    },
    operation: { ...prepared.summary.operation },
    receiptPathSha256: prepared.summary.receiptPathSha256,
    sourceKernelReadOnly: prepared.summary.sourceKernelReadOnly,
    recoveryMode: prepared.summary.recoveryMode,
    ...(extraBinding === null ? {} : { extraBinding }),
    deadline,
    challenge,
    productionWriteAttempted: false,
  });
  const response = await ttyExchange(display);
  if (response !== challenge) {
    fail("PRODUCTION_ACTION_CHALLENGE_REJECTED");
  }
  const authorizedAt = clock();
  if (
    !(authorizedAt instanceof Date) ||
    !Number.isFinite(authorizedAt.getTime())
  ) {
    fail("PRODUCTION_ACTION_CEREMONY_CLOCK_INVALID");
  }
  return authorize({
    authorizedAt: authorizedAt.toISOString(),
    deadline,
    clock: () => authorizedAt,
  });
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
      // A readback-first recovery may run from a clean, narrowly allowlisted
      // executor-fix descendant while it authenticates and mounts the exact
      // frozen deployment candidate. Direct write paths remain exact-HEAD.
      allowRecoveryExecutorDescendant: input.recovery != null,
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
      providerScratchEvidence: input.providerScratchEvidence ?? null,
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

function genericLocalIntentBytes(input) {
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
      liveSessionExpiresAt: input.liveSessionExpiresAt,
      liveSessionRecoverySha256: input.liveSessionRecoverySha256,
      serializableCapability: false,
      priorReceiptSha256: input.priorReceiptSha256,
      receiptPathSha256: sha256(input.receiptPath),
      actionStartedAt: input.actionStartedAt,
      remoteWritePlanned: input.remoteWritePlanned !== false,
      retryAllowed: false,
    })}\n`,
    "utf8",
  );
}

function recoveryAuthorityBytes(input, dispatchPreparedAt) {
  const receipt = receiptRecord({
    ...input,
    outcome: "needs_review",
    actionStartedAt: input.actionStartedAt,
    dispatchStartedAt: dispatchPreparedAt,
    actionCompletedAt: dispatchPreparedAt,
    verifiedAt: dispatchPreparedAt,
    lineageMode: input.priorReceiptSha256
      ? "reviewed_resume_write"
      : "direct_write",
    commandExitZero: false,
    readbackStatus: "needs_review",
    cleanupStatus:
      input.kind === "spazaone_catalog_full_reconciliation"
        ? "not_applicable"
        : "needs_review",
    providerScratchEvidence: null,
    remoteEvidence: null,
    errorCode: "PRODUCTION_DISPATCH_OUTCOME_UNRESOLVED",
    remoteWriteAttempted: true,
  });
  return Buffer.from(`${canonicalJson(receipt)}\n`, "utf8");
}

async function beginIntent(input, dispatchPreparedAt = null) {
  const bytes =
    input.remoteWritePlanned === false
      ? genericLocalIntentBytes(input)
      : recoveryAuthorityBytes(input, dispatchPreparedAt);
  try {
    const recoveryAuthoritySha256 =
      input.remoteWritePlanned === false
        ? null
        : JSON.parse(bytes.toString("utf8")).redactedReceiptSha256;
    return await createDurableArtifactTransaction({
      targetPath: input.receiptPath,
      redactedIntentBytes: bytes,
      recoveryAuthoritySha256,
    });
  } finally {
    bytes.fill(0);
  }
}

function persistenceRecoveryError(transaction, error, code) {
  const recovery =
    error?.recovery ?? transaction?.recoveryDescriptor?.() ?? null;
  return new ProductionExecutorError(code, {
    needsReview: true,
    targetMayExist:
      error?.targetMayExist === true || recovery?.targetMayExist === true,
    recovery,
    cause: error,
  });
}

function persistedNeedsReviewRecovery(receipt, persistedPath) {
  const bytes = Buffer.from(`${canonicalJson(receipt)}\n`, "utf8");
  try {
    const fileSha256 = sha256(bytes);
    return Object.freeze({
      schemaVersion: 1,
      kind: "spazaone_durable_artifact_recovery",
      recoveryRecordPath: persistedPath,
      recoveryRecordPathSha256: sha256(persistedPath),
      recoveryRecordFileSha256: fileSha256,
      recoveryRecordSha256: receipt.redactedReceiptSha256,
      targetPath: persistedPath,
      targetPathSha256: sha256(persistedPath),
      expectedTargetFileSha256: fileSha256,
      targetMayExist: false,
      readbackFirst: true,
      retryAllowed: false,
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
      {
        environmentVariables: { ...(row.environmentVariables ?? {}) },
        secretEnvironmentVariables: Array.isArray(
          row.secretEnvironmentVariables,
        )
          ? row.secretEnvironmentVariables.map((entry) => ({ ...entry }))
          : row.secretEnvironmentVariables,
      },
    ]),
  );
}

async function collectExistingCodeRecoveryReadback({
  context,
  sourceContract,
  collectBaselines = collectExistingEnvironmentBaselines,
  collectReadback = collectCatalogFunctionReadback,
  verifyBaseline = verifyExistingCodeEnvironmentBaseline,
}) {
  if (
    context?.lane !== "existing-code" ||
    !sourceContract ||
    typeof collectBaselines !== "function" ||
    typeof collectReadback !== "function" ||
    typeof verifyBaseline !== "function"
  ) {
    fail("PRODUCTION_EXISTING_CODE_RECOVERY_INPUT_INVALID");
  }
  // A direct existing-code dispatch proves the pre-deploy baseline before it
  // can write. Recovery cannot recreate that consumed snapshot, so it performs
  // two fresh reads instead: first prove that the current state is one of the
  // exact permitted final baseline shapes, then prove a stable second read is
  // bound to the frozen candidate source and identical environment digest.
  const existingEnvironmentBaselines = await collectBaselines(context.lane);
  const firstRead = await collectReadback({
    lane: context.lane,
    validated: null,
    candidateSourceContract: sourceContract,
    existingEnvironmentBaselines,
  });
  const baselineContract = verifyBaseline({
    functionNames: Object.keys(existingEnvironmentBaselines),
    existingEnvironmentBaselines,
  });
  if (
    !SHA256.test(String(firstRead?.environmentDigestSha256 ?? "")) ||
    firstRead.environmentShapesValid !== true ||
    baselineContract?.baselineMatches !== true ||
    baselineContract.preDeployEnvironmentDigestSha256 !==
      firstRead.environmentDigestSha256
  ) {
    fail("PRODUCTION_EXISTING_CODE_RECOVERY_BASELINE_MISMATCH", {
      needsReview: true,
    });
  }
  const readback = await collectReadback({
    lane: context.lane,
    validated: null,
    expectedPreservationDigestSha256: firstRead.environmentDigestSha256,
    existingEnvironmentBaselines,
    candidateSourceContract: sourceContract,
  });
  if (readback.environmentMatches !== true) {
    fail("PRODUCTION_RECOVERY_READBACK_MISMATCH", { needsReview: true });
  }
  return readback;
}

async function candidateSourceContract(expectedAppCommit, mountedPackage) {
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
      functionsDirectory: mountedExactCommitFirebasePackagePath(
        mountedPackage,
        "functions",
      ),
      gitFunctionsDirectory: FUNCTIONS_DIRECTORY,
      expectedAppCommit,
      runtimeConfigHashSha1,
      environment: scrubCredentialEnvironment(),
    });
  } catch (_) {
    fail("CANDIDATE_FUNCTION_SOURCE_BINDING_FAILED");
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
    environmentTransitionMode: readback.environmentTransitionMode,
    preDeployEnvironmentDigestSha256:
      readback.preDeployEnvironmentDigestSha256,
    environmentTransitionDigestSha256:
      readback.environmentTransitionDigestSha256,
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

async function deploymentExecutionContext(options, dotenvText) {
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
  return { context, kind, policyLane, selector, source, validated };
}

async function executeDeployment(sessionCapability, options, dotenvText) {
  const { context, kind, policyLane, selector, source, validated } =
    await deploymentExecutionContext(options, dotenvText);
  await revalidateAuthorityAndCandidate(context);
  const inspectedSession = await inspectAuthorizedProductionLiveSession(
    sessionCapability,
    context,
  );
  const mountedSourceRoot = path.dirname(
    mountedExactCommitFirebasePackagePath(
      inspectedSession.mountedPackage,
      "firestore.rules",
    ),
  );
  if (policyLane) {
    const exactSource = await catalogPolicySourceContract(options.lane, {
      sourceRoot: mountedSourceRoot,
    });
    if (
      exactSource.sourceSha256 !== source.sourceSha256 ||
      exactSource.selector !== selector
    ) {
      fail("CATALOG_POLICY_EXACT_PACKAGE_MISMATCH");
    }
  } else {
    const exactFunctionsDirectory = firebaseProviderWorkspacePath(
      inspectedSession.workspace,
      "functions-source",
    );
    await assertNoSourceDeploymentDotenv(exactFunctionsDirectory);
  }
  const initialSourceContract = policyLane
    ? null
    : await candidateSourceContract(
        options.expectedAppCommit,
        inspectedSession.mountedPackage,
      );
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
  const existingBaselineContract = before
    ? verifyExistingCodeEnvironmentBaseline({
        functionNames: Object.keys(existingEnvironmentBaselines),
        existingEnvironmentBaselines,
      })
    : null;
  if (
    before &&
    (!SHA256.test(String(before.environmentDigestSha256 ?? "")) ||
      before.environmentShapesValid !== true ||
      existingBaselineContract?.baselineMatches !== true ||
      existingBaselineContract.preDeployEnvironmentDigestSha256 !==
        before.environmentDigestSha256)
  ) {
    fail("CATALOG_FUNCTION_READBACK_FAILED");
  }

  await revalidateAuthorityAndCandidate(context);
  await verifyMountedExactCommitFirebasePackage(
    inspectedSession.mountedPackage,
  );
  await verifyFirebaseProductionSessionWorkspace(inspectedSession.workspace);
  const session = await consumeProductionLiveSessionCapability(
    sessionCapability,
    context,
  );
  context.actionAuthorizationSha256 = session.bindingSha256;
  context.actionAuthorizationClaimSha256 = session.consumptionSha256;
  context.liveSessionExpiresAt = session.binding.expiresAt;
  context.liveSessionRecoverySha256 = canonicalSha256(session.binding.recovery);
  const configPath = firebaseProviderWorkspacePath(session.workspace, "config");

  const actionStartedAt = now();
  context.actionStartedAt = actionStartedAt;
  let transaction;
  let dispatchStartedAt;
  let commandExitZero = false;
  let cleanupStatus = "deleted";
  let providerScratchEvidence = null;
  let sessionCleaned = false;
  const cleanupSession = async () => {
    if (sessionCleaned) return;
    try {
      await disposeConsumedProductionLiveSession(session);
      sessionCleaned = true;
    } catch (_) {
      cleanupStatus = "needs_review";
    }
  };
  try {
    const dispatchPreparedAt = now();
    transaction = await beginIntent(context, dispatchPreparedAt);
    await transaction.verifyReadyForDispatch();
    await revalidateAuthorityAndCandidate(context);
    await verifyMountedExactCommitFirebasePackage(session.mountedPackage);
    await verifyFirebaseProductionSessionWorkspace(session.workspace);
    assertLiveSessionDispatchDeadline(session);
    const markedAt = now();
    transaction.markDispatchStarted();
    dispatchStartedAt = markedAt;
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
          env: {
            ...scrubCredentialEnvironment(),
            TMPDIR: firebaseProviderWorkspacePath(session.workspace, "scratch"),
            FIREBASE_CLI_DISABLE_UPDATE_CHECK: "1",
            CI: "1",
          },
          stdio: "inherit",
        },
      );
      commandExitZero = true;
    } catch (_) {
      commandExitZero = false;
    }
    let packageIntegrityVerified = false;
    try {
      await revalidateAuthorityAndCandidate(context);
      await verifyMountedExactCommitFirebasePackage(session.mountedPackage);
      const verifiedWorkspace = await verifyFirebaseProductionSessionWorkspace(
        session.workspace,
        {
          allowScratchChanges: true,
        },
      );
      const scratch = await inspectFirebaseProviderWorkspace(session.workspace);
      packageIntegrityVerified =
        verifiedWorkspace.sourceKernelReadOnly === true &&
        verifiedWorkspace.providerInputKernelReadOnly === true &&
        SHA256.test(scratch.providerScratchInventorySha256) &&
        Number.isSafeInteger(scratch.providerScratchEntryCount) &&
        Number.isSafeInteger(scratch.providerScratchTotalBytes);
      if (packageIntegrityVerified) {
        providerScratchEvidence = Object.freeze({
          inventorySha256: scratch.providerScratchInventorySha256,
          entryCount: scratch.providerScratchEntryCount,
          totalBytes: scratch.providerScratchTotalBytes,
        });
      }
    } catch (_) {
      packageIntegrityVerified = false;
    }
    await cleanupSession();
    if (!commandExitZero) {
      throw new ProductionExecutorError(
        "CATALOG_DEPLOY_EXECUTION_NEEDS_REVIEW",
        { needsReview: true },
      );
    }
    if (!packageIntegrityVerified) {
      throw new ProductionExecutorError(
        "CATALOG_DEPLOY_EXACT_PACKAGE_INTEGRITY_NEEDS_REVIEW",
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
      providerScratchEvidence,
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
      await cleanupSession();
      if (cleanupStatus !== "deleted") {
        fail("PRODUCTION_DEPLOY_SESSION_CLEANUP_UNCERTAIN");
      }
      throw error;
    }
    if (transaction?.state === "failed") {
      throw persistenceRecoveryError(
        transaction,
        error,
        "PRODUCTION_RECEIPT_PERSISTENCE_UNCERTAIN",
      );
    }
    if (transaction?.state === "dispatch_started") {
      await cleanupSession();
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
        providerScratchEvidence,
        remoteEvidence: null,
        errorCode: safeCode,
        remoteWriteAttempted: true,
      });
      let persistedReview;
      try {
        persistedReview = await persistNeedsReview(receipt, transaction);
      } catch (persistError) {
        throw persistenceRecoveryError(
          transaction,
          persistError,
          "PRODUCTION_RECEIPT_PERSISTENCE_UNCERTAIN",
        );
      }
      throw new ProductionExecutorError(safeCode, {
        needsReview: true,
        recovery: persistedNeedsReviewRecovery(receipt, persistedReview.path),
      });
    }
    throw error;
  }
}

function reconciliationExecutionContext(options) {
  const operationInputSha256 = reconciliationOperationInputSha256(options);
  return {
    ...options,
    kind: "spazaone_catalog_full_reconciliation",
    lane: "full-reconciliation",
    selector: "functions:runWhatsAppCatalogFullReconciliationBotHttp",
    operationInputSha256,
    sourceSha256: appCommitSourceSha256(options.expectedAppCommit),
    priorReceiptSha256: options.reviewedResume
      ? options.expectedPriorNeedsReviewReceiptSha256
      : null,
  };
}

function priorReconciliationOperation(context) {
  return {
    lane: context.lane,
    selector: context.selector,
    sourceSha256: context.sourceSha256,
    configurationSha256: nativeCatalogTargetConfigurationDigestSha256(),
    candidateManifestSha256: context.expectedCandidateManifestSha256,
    operationInputSha256: context.operationInputSha256,
  };
}

async function loadReviewedReconciliationReceipt(options, context) {
  if (!options.reviewedResume) return null;
  try {
    return await loadPriorNeedsReviewReceipt({
      receiptPath: options.priorNeedsReviewReceiptPath,
      expectedPriorReceiptSha256: options.expectedPriorNeedsReviewReceiptSha256,
      expectedAppCommit: options.expectedAppCommit,
      expectedOperation: priorReconciliationOperation(context),
    });
  } catch (error) {
    fail("PRIOR_NEEDS_REVIEW_RECEIPT_REJECTED", { cause: error });
  }
}

async function executeReconciliation(
  sessionCapability,
  options,
  { loadedPriorReceipt = null } = {},
) {
  await assertPinnedProductionToolchain();
  const context = reconciliationExecutionContext(options);
  await revalidateAuthorityAndCandidate(context);
  const inspectedSession = await inspectAuthorizedProductionLiveSession(
    sessionCapability,
    context,
  );
  if (options.reviewedResume) {
    if (
      !loadedPriorReceipt ||
      loadedPriorReceipt.priorReceiptSha256 !== context.priorReceiptSha256
    ) {
      fail("PRIOR_NEEDS_REVIEW_RECEIPT_REJECTED");
    }
    await revalidateLoadedPriorNeedsReviewReceipt(loadedPriorReceipt);
  } else if (loadedPriorReceipt !== null) {
    fail("PRIOR_NEEDS_REVIEW_RECEIPT_REJECTED");
  }
  await verifyMountedExactCommitFirebasePackage(
    inspectedSession.mountedPackage,
  );
  await verifyFirebaseProductionSessionWorkspace(inspectedSession.workspace);
  const continuationFacts = inspectedSession.continuationReadback ?? null;
  if (
    (options.reviewedResume &&
      (continuationFacts?.outcome !== "incomplete" ||
        canonicalSha256(continuationFacts) !==
          inspectedSession.binding.recovery.recoveryReadbackSha256)) ||
    (!options.reviewedResume && continuationFacts !== null)
  ) {
    fail("PRODUCTION_RECONCILIATION_CONTINUATION_BINDING_INVALID");
  }
  const session = await consumeProductionLiveSessionCapability(
    sessionCapability,
    context,
  );
  context.actionAuthorizationSha256 = session.bindingSha256;
  context.actionAuthorizationClaimSha256 = session.consumptionSha256;
  context.liveSessionExpiresAt = session.binding.expiresAt;
  context.liveSessionRecoverySha256 = canonicalSha256(session.binding.recovery);
  context.remoteWritePlanned = true;
  const continuationState = continuationFacts
    ? {
        ...(continuationFacts.cycleId === undefined
          ? {}
          : { cycleId: continuationFacts.cycleId }),
        continuationStateDigestSha256:
          continuationFacts.continuationStateDigestSha256,
        acknowledgedPages: continuationFacts.acknowledgedPages,
        productScanComplete: continuationFacts.productScanComplete,
        mappingScanComplete: continuationFacts.mappingScanComplete,
      }
    : null;

  const actionStartedAt = now();
  context.actionStartedAt = actionStartedAt;
  let transaction;
  let dispatchStartedAt;
  let sessionCleaned = false;
  const cleanupSession = async () => {
    if (sessionCleaned) return;
    await disposeConsumedProductionLiveSession(session);
    sessionCleaned = true;
  };
  try {
    const dispatchPreparedAt = now();
    transaction = await beginIntent(context, dispatchPreparedAt);
    await transaction.verifyReadyForDispatch();
    const artifact = await runPrivateFullCatalogReconciliation({
      ...options,
      continuationState,
      onBeforeFirstWrite: async () => {
        if (dispatchStartedAt) {
          fail("PRODUCTION_RECONCILIATION_MULTIPLE_DISPATCH_CALLBACKS");
        }
        await revalidateAuthorityAndCandidate(context);
        if (loadedPriorReceipt) {
          await revalidateLoadedPriorNeedsReviewReceipt(loadedPriorReceipt);
        }
        await verifyMountedExactCommitFirebasePackage(session.mountedPackage);
        await verifyFirebaseProductionSessionWorkspace(session.workspace);
        assertLiveSessionDispatchDeadline(session);
        await transaction.verifyReadyForDispatch();
        const markedAt = now();
        transaction.markDispatchStarted();
        dispatchStartedAt = markedAt;
      },
    });
    if (
      !dispatchStartedAt ||
      artifact?.kind !== "spazaone_catalog_full_reconciliation"
    ) {
      fail("RECONCILIATION_COMPLETION_EVIDENCE_INVALID", {
        needsReview: Boolean(dispatchStartedAt),
      });
    }
    await revalidateAuthorityAndCandidate(context);
    if (loadedPriorReceipt) {
      await revalidateLoadedPriorNeedsReviewReceipt(loadedPriorReceipt);
    }
    await verifyMountedExactCommitFirebasePackage(session.mountedPackage);
    await verifyFirebaseProductionSessionWorkspace(session.workspace, {
      allowScratchChanges: true,
    });
    await cleanupSession();
    const completedAt = now();
    const receipt = receiptRecord({
      ...context,
      outcome: "verified",
      actionStartedAt,
      dispatchStartedAt,
      actionCompletedAt: completedAt,
      verifiedAt: completedAt,
      lineageMode: options.reviewedResume
        ? "reviewed_resume_write"
        : "direct_write",
      commandExitZero: true,
      readbackStatus: "verified",
      cleanupStatus: "not_applicable",
      providerScratchEvidence: null,
      remoteEvidence: { kind: "full_reconciliation", artifact },
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
      kind: context.kind,
      lane: context.lane,
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
        await cleanupSession();
      } catch (_) {
        fail("PRODUCTION_RECONCILIATION_SESSION_CLEANUP_UNCERTAIN");
      }
      if (error?.needsReview === true || error?.ambiguous === true) {
        const safePredispatchCode = /^[A-Z][A-Z0-9_]{0,95}$/.test(
          String(error?.code ?? ""),
        )
          ? error.code
          : "PRODUCTION_RECONCILIATION_PREDISPATCH_BLOCKED";
        throw new ProductionExecutorError(safePredispatchCode, {
          needsReview: false,
          cause: error,
        });
      }
      throw error;
    }
    try {
      await cleanupSession();
    } catch (_) {
      // The remote reconciliation remains needs_review regardless of cleanup.
    }
    if (transaction?.state === "failed") {
      throw persistenceRecoveryError(
        transaction,
        error,
        "PRODUCTION_RECEIPT_PERSISTENCE_UNCERTAIN",
      );
    }
    const completedAt = now();
    const safeCode = /^[A-Z][A-Z0-9_]{0,95}$/.test(String(error?.code ?? ""))
      ? error.code
      : "RECONCILIATION_EXECUTION_NEEDS_REVIEW";
    const receipt = receiptRecord({
      ...context,
      outcome: "needs_review",
      actionStartedAt,
      dispatchStartedAt,
      actionCompletedAt: completedAt,
      verifiedAt: completedAt,
      lineageMode: options.reviewedResume
        ? "reviewed_resume_write"
        : "direct_write",
      commandExitZero: false,
      readbackStatus: "needs_review",
      cleanupStatus: "not_applicable",
      providerScratchEvidence: null,
      remoteEvidence: null,
      errorCode: safeCode,
      remoteWriteAttempted: true,
    });
    let persistedReview;
    try {
      persistedReview = await persistNeedsReview(receipt, transaction);
    } catch (persistError) {
      throw persistenceRecoveryError(
        transaction,
        persistError,
        "PRODUCTION_RECEIPT_PERSISTENCE_UNCERTAIN",
      );
    }
    throw new ProductionExecutorError(safeCode, {
      needsReview: true,
      recovery: persistedNeedsReviewRecovery(receipt, persistedReview.path),
    });
  }
}

async function persistRecoveredReconciliation({
  context,
  preparedSummary,
  recoveryReadbackSha256,
  artifact,
  loadedPriorReceipt,
}) {
  await revalidateLoadedPriorNeedsReviewReceipt(loadedPriorReceipt);
  let finalCandidate = await revalidateAuthorityAndCandidate(context);
  const actionStartedAt = now();
  const receiptContext = {
    ...context,
    actionAuthorizationSha256: preparedSummary.bindingSha256,
    actionAuthorizationClaimSha256: recoveryReadbackSha256,
    liveSessionExpiresAt: preparedSummary.expiresAt,
    liveSessionRecoverySha256: canonicalSha256({
      mode: "readback_first",
      priorReceiptSha256: context.priorReceiptSha256,
    }),
    actionStartedAt,
    remoteWritePlanned: false,
  };
  let transaction;
  let persistenceStartedAt;
  try {
    transaction = await beginIntent(receiptContext);
    await transaction.verifyReadyForDispatch();
    await revalidateLoadedPriorNeedsReviewReceipt(loadedPriorReceipt);
    finalCandidate = await revalidateAuthorityAndCandidate(context);
    const markedAt = now();
    transaction.markDispatchStarted();
    persistenceStartedAt = markedAt;
    const completedAt = now();
    const receipt = receiptRecord({
      ...receiptContext,
      outcome: "recovered_verified",
      actionStartedAt,
      dispatchStartedAt: persistenceStartedAt,
      actionCompletedAt: completedAt,
      verifiedAt: completedAt,
      lineageMode: "recovered_readback",
      commandExitZero: null,
      readbackStatus: "verified",
      cleanupStatus: "not_applicable",
      providerScratchEvidence: null,
      remoteEvidence: { kind: "full_reconciliation", artifact },
      errorCode: null,
      remoteWriteAttempted: false,
    });
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
      outcome: "recovered_verified",
      kind: context.kind,
      lane: context.lane,
      receiptPath: persisted.path,
      receiptSha256: receipt.redactedReceiptSha256,
      remoteWriteAttempted: false,
      retryAllowed: false,
    };
  } catch (error) {
    if (!persistenceStartedAt) {
      try {
        await transaction?.cancelBeforeDispatch();
      } catch (cancelError) {
        throw new ProductionExecutorError(
          "PRODUCTION_WRITE_INTENT_CANCELLATION_UNCERTAIN",
          { needsReview: true, cause: cancelError },
        );
      }
      throw error;
    }
    throw new ProductionExecutorError(
      "PRODUCTION_RECOVERED_RECEIPT_PERSISTENCE_UNCERTAIN",
      {
        needsReview: true,
        targetMayExist: error?.targetMayExist === true,
        recovery:
          error?.recovery ?? transaction?.recoveryDescriptor?.() ?? null,
        cause: error,
      },
    );
  }
}

async function authorizeDirectPreparedSession(prepared) {
  try {
    return await conductProductionActionCeremony({
      prepared,
      authorize: (authorization) =>
        authorizePreparedProductionLiveSession(
          prepared.capability,
          authorization,
        ),
    });
  } catch (error) {
    try {
      await disposePreparedProductionLiveSession(prepared.capability);
    } catch (_) {
      // The original authorization failure remains authoritative.
    }
    throw error;
  }
}

function recoveryOperationBinding(context) {
  return {
    lane: context.lane,
    selector: context.selector,
    sourceSha256: context.sourceSha256,
    configurationSha256: nativeCatalogTargetConfigurationDigestSha256(),
    candidateManifestSha256: context.expectedCandidateManifestSha256,
    operationInputSha256: context.operationInputSha256,
  };
}

async function inspectPossibleRecoveryTarget(recovery, context) {
  if (
    recovery.targetPath === context.receiptPath ||
    recovery.targetPath === context.candidateManifestPath
  ) {
    return Object.freeze({ outcome: "target_present_untrusted" });
  }
  let stat;
  try {
    stat = await lstat(recovery.targetPath);
  } catch (error) {
    if (error?.code === "ENOENT") {
      return Object.freeze({ outcome: "target_absent" });
    }
    fail("PRODUCTION_RECOVERY_TARGET_REJECTED", { cause: error });
  }
  const uid = process.geteuid?.();
  if (
    !Number.isSafeInteger(uid) ||
    !stat.isFile() ||
    stat.isSymbolicLink() ||
    stat.uid !== uid ||
    stat.nlink !== 1 ||
    (stat.mode & 0o777) !== 0o600 ||
    stat.size < 2 ||
    stat.size > 256 * 1024 ||
    (await realpath(recovery.targetPath)) !== recovery.targetPath
  ) {
    fail("PRODUCTION_RECOVERY_TARGET_REJECTED");
  }
  let bytes;
  try {
    bytes = await readFile(recovery.targetPath);
    const receipt = JSON.parse(bytes.toString("utf8"));
    const canonicalBytes = Buffer.from(`${canonicalJson(receipt)}\n`, "utf8");
    try {
      if (!bytes.equals(canonicalBytes)) {
        return Object.freeze({ outcome: "target_present_untrusted" });
      }
    } finally {
      canonicalBytes.fill(0);
    }
    validateProductionWriteReceipt(receipt);
    const expected = recoveryOperationBinding(context);
    const actual = Object.fromEntries(
      Object.keys(expected).map((key) => [key, receipt.operation?.[key]]),
    );
    const receiptFileSha256 = sha256(bytes);
    if (
      recovery.expectedTargetFileSha256 === null ||
      receiptFileSha256 !== recovery.expectedTargetFileSha256 ||
      receipt.appCommit !== context.expectedAppCommit ||
      receipt.kind !== context.kind ||
      !new Set(["verified", "needs_review"]).has(receipt.outcome) ||
      canonicalJson(actual) !== canonicalJson(expected)
    ) {
      return Object.freeze({ outcome: "target_present_untrusted" });
    }
    return Object.freeze({
      outcome: "target_present_canonical",
      receiptOutcome: receipt.outcome,
      receiptSha256: receipt.redactedReceiptSha256,
      receiptFileSha256,
    });
  } catch (error) {
    if (error instanceof ProductionExecutorError) throw error;
    return Object.freeze({ outcome: "target_present_untrusted" });
  } finally {
    bytes?.fill?.(0);
  }
}

async function loadDeploymentRecoveryAuthority(options, context) {
  const recovery = options.recovery;
  if (!recovery) fail("PRODUCTION_RECOVERY_ARGUMENT_INVALID");
  // The possible canonical target is always inspected before the hidden
  // recovery authority. This covers an acknowledgement loss after link/fsync.
  const targetInspection = await inspectPossibleRecoveryTarget(
    recovery,
    context,
  );
  let loaded;
  let recoveryLoadError;
  try {
    loaded = await loadPriorNeedsReviewReceipt({
      receiptPath: recovery.recoveryRecordPath,
      expectedPriorReceiptSha256: recovery.recoveryRecordSha256,
      expectedAppCommit: context.expectedAppCommit,
      expectedOperation: recoveryOperationBinding(context),
      expectedKind: context.kind,
    });
  } catch (error) {
    recoveryLoadError = error;
  }
  if (
    (loaded &&
      loaded.priorReceiptFileSha256 !== recovery.recoveryRecordFileSha256) ||
    (loaded &&
      loaded.priorReceiptPathSha256 !== sha256(recovery.recoveryRecordPath))
  ) {
    fail("PRODUCTION_RECOVERY_AUTHORITY_REJECTED");
  }
  if (loaded) return { loaded, targetInspection, existingVerified: null };
  if (targetInspection.outcome !== "target_present_canonical") {
    fail("PRODUCTION_RECOVERY_AUTHORITY_REJECTED", {
      cause: recoveryLoadError,
    });
  }
  if (targetInspection.receiptOutcome === "verified") {
    return {
      loaded: null,
      targetInspection,
      existingVerified: targetInspection,
    };
  }
  try {
    loaded = await loadPriorNeedsReviewReceipt({
      receiptPath: recovery.targetPath,
      expectedPriorReceiptSha256: targetInspection.receiptSha256,
      expectedAppCommit: context.expectedAppCommit,
      expectedOperation: recoveryOperationBinding(context),
      expectedKind: context.kind,
    });
  } catch (error) {
    fail("PRODUCTION_RECOVERY_AUTHORITY_REJECTED", { cause: error });
  }
  if (loaded.priorReceiptFileSha256 !== targetInspection.receiptFileSha256) {
    fail("PRODUCTION_RECOVERY_AUTHORITY_REJECTED");
  }
  return { loaded, targetInspection, existingVerified: null };
}

async function persistRecoveredDeployment({
  context,
  candidate,
  preparedSummary,
  recoveryReadbackSha256,
  rawEvidence,
  loadedPriorReceipt,
  targetInspection,
}) {
  await revalidateLoadedPriorNeedsReviewReceipt(loadedPriorReceipt);
  await revalidateAuthorityAndCandidate(context);
  const actionStartedAt = now();
  const receiptContext = {
    ...context,
    actionAuthorizationSha256: preparedSummary.bindingSha256,
    actionAuthorizationClaimSha256: recoveryReadbackSha256,
    liveSessionExpiresAt: preparedSummary.expiresAt,
    liveSessionRecoverySha256: canonicalSha256({
      mode: "readback_first",
      priorReceiptSha256: context.priorReceiptSha256,
      targetInspection,
    }),
    actionStartedAt,
    remoteWritePlanned: false,
  };
  let transaction;
  let persistenceStartedAt;
  try {
    transaction = await beginIntent(receiptContext);
    await transaction.verifyReadyForDispatch();
    await revalidateLoadedPriorNeedsReviewReceipt(loadedPriorReceipt);
    const finalCandidate = await revalidateAuthorityAndCandidate(context);
    if (canonicalSha256(candidate) !== canonicalSha256(finalCandidate)) {
      fail("PRODUCTION_RECOVERY_CANDIDATE_CHANGED");
    }
    persistenceStartedAt = now();
    transaction.markDispatchStarted();
    const completedAt = now();
    const receipt = receiptRecord({
      ...receiptContext,
      outcome: "recovered_verified",
      actionStartedAt,
      dispatchStartedAt: persistenceStartedAt,
      actionCompletedAt: completedAt,
      verifiedAt: completedAt,
      lineageMode: "recovered_readback",
      commandExitZero: null,
      readbackStatus: "verified",
      cleanupStatus: "not_applicable",
      providerScratchEvidence: null,
      remoteEvidence: rawEvidence,
      errorCode: null,
      remoteWriteAttempted: false,
    });
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
      outcome: "recovered_verified",
      kind: context.kind,
      lane: context.lane,
      receiptPath: persisted.path,
      receiptSha256: receipt.redactedReceiptSha256,
      priorReceiptSha256: context.priorReceiptSha256,
      targetInspection,
      remoteWriteAttempted: false,
      retryAllowed: false,
    };
  } catch (error) {
    if (!persistenceStartedAt) {
      try {
        await transaction?.cancelBeforeDispatch();
      } catch (cancelError) {
        throw persistenceRecoveryError(
          transaction,
          cancelError,
          "PRODUCTION_WRITE_INTENT_CANCELLATION_UNCERTAIN",
        );
      }
      throw error;
    }
    throw persistenceRecoveryError(
      transaction,
      error,
      "PRODUCTION_RECOVERED_RECEIPT_PERSISTENCE_UNCERTAIN",
    );
  }
}

async function runDeploymentRecovery(options, dotenvText) {
  const execution = await deploymentExecutionContext(options, dotenvText);
  const context = {
    ...execution.context,
    priorReceiptSha256: options.recovery.recoveryRecordSha256,
  };
  const candidate = await revalidateAuthorityAndCandidate(context);
  const { loaded, targetInspection, existingVerified } =
    await loadDeploymentRecoveryAuthority(options, context);
  if (existingVerified) {
    return {
      outcome: "recovered_existing_verified",
      kind: context.kind,
      lane: context.lane,
      receiptPath: options.recovery.targetPath,
      receiptSha256: existingVerified.receiptSha256,
      receiptFileSha256: existingVerified.receiptFileSha256,
      targetInspection,
      remoteWriteAttempted: false,
      retryAllowed: false,
    };
  }
  context.priorReceiptSha256 = loaded.priorReceiptSha256;
  let rawEvidence = null;
  const prepared = await prepareProductionLiveSession({
    context,
    candidate,
    dotenvText,
    recovery: {
      mode: "readback_first",
      priorReceiptSha256: loaded.priorReceiptSha256,
    },
    recoveryReadbackProvider: async ({ mountedPackage, workspace }) => {
      await revalidateLoadedPriorNeedsReviewReceipt(loaded);
      await revalidateAuthorityAndCandidate(context);
      await verifyMountedExactCommitFirebasePackage(mountedPackage);
      await verifyFirebaseProductionSessionWorkspace(workspace);
      if (execution.policyLane) {
        const readback = await collectCatalogPolicyReadback(context.lane);
        if (!policyReadbackMatches(context.lane, execution.source, readback)) {
          fail("PRODUCTION_RECOVERY_READBACK_MISMATCH", {
            needsReview: true,
          });
        }
        rawEvidence = policyRemoteEvidence(
          context.lane,
          execution.source,
          readback,
        );
      } else {
        const sourceContract = await candidateSourceContract(
          context.expectedAppCommit,
          mountedPackage,
        );
        const readback =
          context.lane === "existing-code"
            ? await collectExistingCodeRecoveryReadback({
                context,
                sourceContract,
              })
            : await collectCatalogFunctionReadback({
                lane: context.lane,
                validated: execution.validated,
                candidateSourceContract: sourceContract,
              });
        if (readback.environmentMatches !== true) {
          fail("PRODUCTION_RECOVERY_READBACK_MISMATCH", {
            needsReview: true,
          });
        }
        rawEvidence = functionRemoteEvidence(
          context.lane,
          context.selector,
          readback,
        );
      }
      return {
        outcome: "complete",
        cycleId: canonicalSha256(rawEvidence).slice(0, 32),
        evidenceSha256: canonicalSha256(rawEvidence),
      };
    },
  });
  const inspection = await recordRecoveryInspection(prepared.capability);
  if (
    inspection.outcome !== "recovered_readback" ||
    !rawEvidence ||
    inspection.priorReceiptSha256 !== loaded.priorReceiptSha256
  ) {
    fail("PRODUCTION_RECOVERY_READBACK_REJECTED", { needsReview: true });
  }
  return persistRecoveredDeployment({
    context,
    candidate,
    preparedSummary: prepared.summary,
    recoveryReadbackSha256: inspection.recoveryReadbackSha256,
    rawEvidence,
    loadedPriorReceipt: loaded,
    targetInspection,
  });
}

async function runDeploymentWithActionCeremony(options, dotenvText) {
  const { context } = await deploymentExecutionContext(options, dotenvText);
  const candidate = await revalidateAuthorityAndCandidate(context);
  const prepared = await prepareProductionLiveSession({
    context,
    candidate,
    dotenvText,
    recovery: { mode: "direct" },
  });
  const authorized = await authorizeDirectPreparedSession(prepared);
  try {
    return await executeDeployment(authorized.capability, options, dotenvText);
  } finally {
    try {
      await disposeAuthorizedProductionLiveSession(authorized.capability);
    } catch (error) {
      if (error?.code !== "PRODUCTION_AUTHORIZED_SESSION_NOT_ACTIVE") {
        throw error;
      }
    }
  }
}

async function runReconciliationWithActionCeremony(options) {
  const context = reconciliationExecutionContext(options);
  const candidate = await revalidateAuthorityAndCandidate(context);
  const loadedPriorReceipt = await loadReviewedReconciliationReceipt(
    options,
    context,
  );
  if (!options.reviewedResume) {
    const prepared = await prepareProductionLiveSession({
      context,
      candidate,
      dotenvText: "",
      recovery: { mode: "direct" },
    });
    const authorized = await authorizeDirectPreparedSession(prepared);
    try {
      return await executeReconciliation(authorized.capability, options);
    } finally {
      try {
        await disposeAuthorizedProductionLiveSession(authorized.capability);
      } catch (error) {
        if (error?.code !== "PRODUCTION_AUTHORIZED_SESSION_NOT_ACTIVE") {
          throw error;
        }
      }
    }
  }

  let recoveredArtifact = null;
  let continuationReadback = null;
  const prepared = await prepareProductionLiveSession({
    context,
    candidate,
    dotenvText: "",
    recovery: {
      mode: "readback_first",
      priorReceiptSha256: loadedPriorReceipt.priorReceiptSha256,
    },
    recoveryReadbackProvider: async () => {
      await revalidateLoadedPriorNeedsReviewReceipt(loadedPriorReceipt);
      const result = await runPrivateFullCatalogReconciliation({
        ...options,
        continuationState: null,
        onBeforeFirstWrite: undefined,
      });
      if (result?.kind === "spazaone_catalog_full_reconciliation") {
        recoveredArtifact = result;
        return { outcome: "complete", cycleId: result.cycleId };
      }
      if (result?.outcome !== "continuation_authorization_required") {
        fail("PRODUCTION_RECOVERY_READBACK_REJECTED");
      }
      continuationReadback = Object.freeze({
        outcome: "incomplete",
        ...(result.cycleId === undefined ? {} : { cycleId: result.cycleId }),
        continuationStateDigestSha256: result.continuationStateDigestSha256,
        acknowledgedPages: result.acknowledgedPages,
        productScanComplete: result.productScanComplete,
        mappingScanComplete: result.mappingScanComplete,
      });
      return continuationReadback;
    },
  });
  const inspection = await recordRecoveryInspection(prepared.capability);
  if (inspection.outcome === "recovered_readback") {
    if (recoveredArtifact?.kind !== "spazaone_catalog_full_reconciliation") {
      fail("PRODUCTION_RECOVERY_READBACK_REJECTED");
    }
    return persistRecoveredReconciliation({
      context,
      preparedSummary: prepared.summary,
      recoveryReadbackSha256: inspection.recoveryReadbackSha256,
      artifact: recoveredArtifact,
      loadedPriorReceipt,
    });
  }
  if (
    inspection.outcome !== "continuation_authorization_required" ||
    !continuationReadback ||
    canonicalSha256(continuationReadback) !== inspection.recoveryReadbackSha256
  ) {
    try {
      await disposeRecoveryInspectionLiveSession(prepared.capability);
    } catch (_) {
      // Preserve the binding failure.
    }
    fail("PRODUCTION_RECOVERY_READBACK_REJECTED");
  }
  let authorized;
  try {
    authorized = await conductProductionActionCeremony({
      prepared,
      extraBinding: Object.freeze({
        priorReceiptSha256: loadedPriorReceipt.priorReceiptSha256,
        recoveryReadbackSha256: inspection.recoveryReadbackSha256,
        continuationStateDigestSha256:
          continuationReadback.continuationStateDigestSha256,
      }),
      authorize: (authorization) =>
        mintFreshReconciliationContinuationCapability(
          prepared.capability,
          authorization,
        ),
    });
  } catch (error) {
    try {
      await disposeRecoveryInspectionLiveSession(prepared.capability);
    } catch (_) {
      // Preserve the original challenge or authorization failure.
    }
    throw error;
  }
  try {
    return await executeReconciliation(authorized.capability, options, {
      loadedPriorReceipt,
    });
  } finally {
    try {
      await disposeAuthorizedProductionLiveSession(authorized.capability);
    } catch (error) {
      if (error?.code !== "PRODUCTION_AUTHORIZED_SESSION_NOT_ACTIVE") {
        throw error;
      }
    }
  }
}

async function main() {
  try {
    await assertCleanLauncherOrigin();
    cleanExecutorEnvironment();
    await assertPinnedNodeProcess();
    const [mode, ...args] = process.argv.slice(2);
    const authorizationArguments = extractActionAuthorizationArguments(args);
    if (mode === "deployment") {
      const deploymentRecoveryArguments = extractDeploymentRecoveryArguments(
        authorizationArguments.remaining,
      );
      const options = {
        ...parseDeploymentGuardArguments(deploymentRecoveryArguments.remaining),
        recovery: deploymentRecoveryArguments.recovery,
      };
      if (!options.execute) {
        if (options.recovery) fail("PRODUCTION_RECOVERY_ARGUMENT_INVALID");
        await runLegacyReadOnly(LEGACY_DEPLOYMENT_SCRIPT, args);
        return;
      }
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
      const result = options.recovery
        ? await runDeploymentRecovery(options, dotenvText)
        : await runDeploymentWithActionCeremony(options, dotenvText);
      process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
      return;
    }
    if (mode === "reconciliation") {
      const options = parseRunnerArguments(authorizationArguments.remaining);
      if (!options.execute) {
        await runLegacyReadOnly(LEGACY_RECONCILIATION_SCRIPT, args);
        return;
      }
      const result = await runReconciliationWithActionCeremony(options);
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
        ...(safe.recovery ? { recovery: safe.recovery } : {}),
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
