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
      (!/^[a-f0-9]{32}$/.test(String(cycleId ?? "")) ||
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
    (recoveryInspection &&
      (context.kind !== "spazaone_catalog_full_reconciliation" ||
        context.lane !== "full-reconciliation" ||
        typeof recoveryReadbackProvider !== "function")) ||
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
        gitTreeSha1: candidate.gitTreeSha1,
        gitArchiveSha256: packageDescriptor.gitArchiveSha256,
        packageInventorySha256: packageDescriptor.packageInventorySha256,
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
  const expectedKeys =
    value.outcome === "complete"
      ? ["cycleId", "outcome"]
      : ["continuationStateDigestSha256", "cycleId", "outcome"];
  if (
    canonicalJson(Object.keys(value).sort()) !== canonicalJson(expectedKeys) ||
    !/^[a-f0-9]{32}$/.test(String(value.cycleId ?? "")) ||
    (value.outcome === "incomplete" &&
      !SHA256.test(String(value.continuationStateDigestSha256 ?? "")))
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
    canonicalReadback = exactRecoveryReadback(await provider());
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
      cycleId: validatedReadback.cycleId,
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
      liveSessionExpiresAt: input.liveSessionExpiresAt,
      liveSessionRecoverySha256: input.liveSessionRecoverySha256,
      serializableCapability: false,
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

async function executeDeployment(sessionCapability, options, dotenvText) {
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
  if (
    before &&
    (!SHA256.test(String(before.environmentDigestSha256 ?? "")) ||
      before.environmentShapesValid !== true)
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
    transaction = await beginIntent(context);
    await transaction.verifyReadyForDispatch();
    await revalidateAuthorityAndCandidate(context);
    await verifyMountedExactCommitFirebasePackage(session.mountedPackage);
    await verifyFirebaseProductionSessionWorkspace(session.workspace);
    assertLiveSessionDispatchDeadline(session);
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
      const options = parseDeploymentGuardArguments(
        authorizationArguments.remaining,
      );
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
      // The future enabled orchestrator must prepare the reviewed package,
      // pause for action-time authority, authorize its private handle, and
      // pass that same-process object to executeDeployment. A CLI argument is
      // deliberately incapable of filling this slot.
      void options;
      void dotenvText;
      fail("FRESH_PRODUCTION_ACTION_AUTHORIZATION_REQUIRED");
    }
    if (mode === "reconciliation") {
      const options = parseRunnerArguments(authorizationArguments.remaining);
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
