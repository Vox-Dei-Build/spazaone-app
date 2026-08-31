#!/usr/bin/env node

import { execFile as nodeExecFile } from "node:child_process";
import { createHash } from "node:crypto";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { promisify } from "node:util";

import {
  IMMUTABLE_TARGET_CONFIGURATION,
  PRODUCTION_FIREBASE_ACCOUNT,
  PRODUCTION_FIREBASE_PROJECT_ID,
  PRODUCTION_NATIVE_CATALOG_TARGET,
  RECONCILIATION_FUNCTION_URL,
  nativeCatalogTargetConfigurationDigestSha256,
} from "./whatsapp-catalog-production-target.mjs";
import {
  FINALIZED_RECONCILIATION_ARTIFACT_KEYS,
  PINNED_FIREBASE_CLI,
  assertPinnedProductionToolchain,
  canonicalSha256,
  validateFinalizedReconciliationArtifact,
} from "./production-write-receipt.mjs";
import {
  APP_REPOSITORY_ROOT,
  FROZEN_APP_MAIN_COMMIT,
  loadAndValidateProductionCandidateManifest,
} from "./production-candidate-manifest.mjs";

const execFile = promisify(nodeExecFile);

export {
  APP_REPOSITORY_ROOT,
  FROZEN_APP_MAIN_COMMIT,
  IMMUTABLE_TARGET_CONFIGURATION,
  PRODUCTION_FIREBASE_ACCOUNT,
  PRODUCTION_FIREBASE_PROJECT_ID,
  PRODUCTION_NATIVE_CATALOG_TARGET,
  RECONCILIATION_FUNCTION_URL,
  nativeCatalogTargetConfigurationDigestSha256,
};

const EXPECTED_AUTHORITY = Object.freeze({
  project_id: "spaza-one",
  project: "Spaza One",
  component: "app",
  role: "authority",
  entity: "vox-dei",
  account: "github.tsepo-vox-dei",
  repository: "Vox-Dei-Build/spazaone-app",
  matched_by: "git_origin",
});

const RECOVERY_EXECUTOR_ALLOWED_CHANGED_PATHS = Object.freeze([
  "functions/scripts/execute-whatsapp-catalog-production.mjs",
  "functions/scripts/firebase-function-source-binding.mjs",
  "functions/scripts/guard-whatsapp-catalog-functions-deploy.mjs",
  "functions/scripts/run-whatsapp-catalog-full-reconciliation.mjs",
  "functions/test/production_executor_activation.test.mjs",
  "functions/test/whatsapp_catalog_production_tools.test.mjs",
]);

const CODEX_GUARD = "/Users/admin/.codex/identity-governance/bin/codex-guard";
const MAX_RESPONSE_BYTES = 5 * 1024 * 1024;
export class ReconciliationOperatorError extends Error {
  constructor(code, { ambiguous = false, needsReview = false } = {}) {
    super(code);
    this.name = "ReconciliationOperatorError";
    this.code = code;
    this.ambiguous = ambiguous;
    // Any ambiguous result follows a write-capable request and therefore may
    // represent an acknowledged server mutation whose response was lost.
    this.needsReview = needsReview || ambiguous;
  }
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function exactAuthority(value) {
  if (!value || typeof value !== "object") return false;
  return Object.entries(EXPECTED_AUTHORITY).every(
    ([key, expected]) => value[key] === expected,
  );
}

function stdoutText(result) {
  if (Buffer.isBuffer(result?.stdout)) return result.stdout.toString("utf8");
  return String(result?.stdout ?? "");
}

export function scrubCredentialEnvironment(environment = process.env) {
  const safeNames = new Set([
    "HOME",
    "USER",
    "LOGNAME",
    "TMPDIR",
    "SHELL",
    "TERM",
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
  ]);
  const scrubbed = {
    PATH: "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
  };
  for (const [key, value] of Object.entries(environment)) {
    if (safeNames.has(key) && typeof value === "string") scrubbed[key] = value;
  }
  return scrubbed;
}

function trimmedBuffer(value) {
  const source = Buffer.isBuffer(value)
    ? Buffer.from(value)
    : Buffer.from(String(value ?? ""), "utf8");
  let start = 0;
  let end = source.length;
  while (start < end && /\s/.test(String.fromCharCode(source[start]))) start++;
  while (end > start && /\s/.test(String.fromCharCode(source[end - 1]))) end--;
  const result = Buffer.from(source.subarray(start, end));
  source.fill(0);
  return result;
}

/**
 * Resolves the bot credential through the explicitly selected registered
 * Firebase account. The value exists only in returned process memory.
 */
export async function resolvePasellaBotToken({
  execFileImpl = execFile,
  environment = process.env,
} = {}) {
  let stdout;
  try {
    const result = await execFileImpl(
      PINNED_FIREBASE_CLI.executablePath,
      [
        "--project",
        PRODUCTION_FIREBASE_PROJECT_ID,
        "--account",
        PRODUCTION_FIREBASE_ACCOUNT,
        "--non-interactive",
        "functions:secrets:access",
        "PASELLA_BOT_TOKEN",
      ],
      {
        cwd: APP_REPOSITORY_ROOT,
        encoding: null,
        maxBuffer: 64 * 1024,
        env: scrubCredentialEnvironment(environment),
      },
    );
    stdout = result.stdout;
  } catch (_) {
    throw new ReconciliationOperatorError("BOT_SECRET_RESOLUTION_FAILED");
  }
  const token = trimmedBuffer(stdout);
  if (Buffer.isBuffer(stdout)) stdout.fill(0);
  stdout = undefined;
  if (
    token.length < 16 ||
    token.length > 16 * 1024 ||
    token.some((byte) => byte < 0x21 || byte > 0x7e)
  ) {
    token.fill(0);
    throw new ReconciliationOperatorError("BOT_SECRET_RESOLUTION_INVALID");
  }
  return token;
}

/** Verifies the exact clean Vox Dei authority checkout and returns its SHA. */
export async function resolveAuthorityAppCommit({
  expectedCandidateCommit,
  expectedCurrentMainCommit,
  allowRecoveryExecutorDescendant = false,
  execFileImpl = execFile,
  environment = process.env,
} = {}) {
  if (
    !/^[a-f0-9]{40}$/.test(String(expectedCandidateCommit ?? "")) ||
    !/^[a-f0-9]{40}$/.test(String(expectedCurrentMainCommit ?? "")) ||
    expectedCurrentMainCommit !== FROZEN_APP_MAIN_COMMIT ||
    ![true, false].includes(allowRecoveryExecutorDescendant)
  ) {
    throw new ReconciliationOperatorError("APP_AUTHORITY_PROVENANCE_INVALID");
  }
  let status;
  let revision;
  let authority;
  let governedMainRevision;
  let mergeBase;
  let candidateMergeBase;
  let recoveryChangedPaths;
  const childEnvironment = scrubCredentialEnvironment(environment);
  try {
    status = stdoutText(
      await execFileImpl("git", ["status", "--porcelain"], {
        cwd: APP_REPOSITORY_ROOT,
        encoding: "utf8",
        env: childEnvironment,
      }),
    );
    revision = stdoutText(
      await execFileImpl("git", ["rev-parse", "HEAD"], {
        cwd: APP_REPOSITORY_ROOT,
        encoding: "utf8",
        env: childEnvironment,
      }),
    ).trim();
    authority = JSON.parse(
      stdoutText(
        await execFileImpl(
          CODEX_GUARD,
          ["resolve", "--path", APP_REPOSITORY_ROOT],
          {
            cwd: APP_REPOSITORY_ROOT,
            encoding: "utf8",
            env: childEnvironment,
          },
        ),
      ),
    );
    governedMainRevision = stdoutText(
      await execFileImpl(
        CODEX_GUARD,
        [
          "gh",
          "--project",
          "spaza-one",
          "--component",
          "app",
          "--role",
          "authority",
          "--",
          // The machine guard permits the repository-bound read-only ref
          // endpoint; keep this exact route so current-main verification does
          // not widen into the general commits API.
          "api",
          "repos/Vox-Dei-Build/spazaone-app/git/ref/heads/main",
          "--jq",
          ".object.sha",
        ],
        {
          cwd: APP_REPOSITORY_ROOT,
          encoding: "utf8",
          env: childEnvironment,
        },
      ),
    ).trim();
    mergeBase = stdoutText(
      await execFileImpl(
        "git",
        ["merge-base", revision, FROZEN_APP_MAIN_COMMIT],
        {
          cwd: APP_REPOSITORY_ROOT,
          encoding: "utf8",
          env: childEnvironment,
        },
      ),
    ).trim();
    if (
      allowRecoveryExecutorDescendant &&
      revision !== expectedCandidateCommit
    ) {
      candidateMergeBase = stdoutText(
        await execFileImpl(
          "git",
          ["merge-base", revision, expectedCandidateCommit],
          {
            cwd: APP_REPOSITORY_ROOT,
            encoding: "utf8",
            env: childEnvironment,
          },
        ),
      ).trim();
      recoveryChangedPaths = stdoutText(
        await execFileImpl(
          "git",
          [
            "diff",
            "--name-only",
            "--no-renames",
            expectedCandidateCommit,
            revision,
            "--",
          ],
          {
            cwd: APP_REPOSITORY_ROOT,
            encoding: "utf8",
            env: childEnvironment,
          },
        ),
      )
        .split("\n")
        .filter(Boolean);
    }
  } catch (_) {
    throw new ReconciliationOperatorError("APP_AUTHORITY_RESOLUTION_FAILED");
  }
  if (status.trim()) {
    throw new ReconciliationOperatorError("APP_AUTHORITY_CHECKOUT_DIRTY");
  }
  if (!/^[a-f0-9]{40}$/.test(revision)) {
    throw new ReconciliationOperatorError("APP_AUTHORITY_REVISION_INVALID");
  }
  if (revision !== expectedCandidateCommit) {
    const uniqueChangedPaths = new Set(recoveryChangedPaths ?? []);
    if (
      !allowRecoveryExecutorDescendant ||
      candidateMergeBase !== expectedCandidateCommit ||
      uniqueChangedPaths.size === 0 ||
      uniqueChangedPaths.size !== (recoveryChangedPaths ?? []).length ||
      [...uniqueChangedPaths].some(
        (changedPath) =>
          !RECOVERY_EXECUTOR_ALLOWED_CHANGED_PATHS.includes(changedPath),
      )
    ) {
      throw new ReconciliationOperatorError(
        "APP_AUTHORITY_REVIEWED_CANDIDATE_MISMATCH",
      );
    }
  }
  if (
    governedMainRevision !== expectedCurrentMainCommit ||
    governedMainRevision !== FROZEN_APP_MAIN_COMMIT
  ) {
    throw new ReconciliationOperatorError("APP_AUTHORITY_MAIN_MOVED");
  }
  if (mergeBase !== FROZEN_APP_MAIN_COMMIT) {
    throw new ReconciliationOperatorError("APP_AUTHORITY_ANCESTRY_MISMATCH");
  }
  if (!exactAuthority(authority)) {
    throw new ReconciliationOperatorError("APP_AUTHORITY_CHECKOUT_MISMATCH");
  }
  return expectedCandidateCommit;
}

function nonNegativeInteger(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : null;
}

const OUTBOX_STATUS_KEYS = Object.freeze([
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
    JSON.stringify(Object.keys(counts).sort()) ===
      JSON.stringify([...OUTBOX_STATUS_KEYS].sort()) &&
    OUTBOX_STATUS_KEYS.every(
      (key) => nonNegativeInteger(counts[key]) !== null,
    ) &&
    pendingOutboxStatusCount(counts) === 0 &&
    counts.unknown === 0 &&
    OUTBOX_STATUS_KEYS.reduce((sum, key) => sum + counts[key], 0) ===
      value.totalOutboxDocuments
  );
}

function redactedPage(value) {
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
      ? {
          pending: nonNegativeInteger(counts.pending),
          retry: nonNegativeInteger(counts.retry),
          processing: nonNegativeInteger(counts.processing),
          submitted: nonNegativeInteger(counts.submitted),
          active: nonNegativeInteger(counts.active),
          deleted: nonNegativeInteger(counts.deleted),
          rejected: nonNegativeInteger(counts.rejected),
          unknown: nonNegativeInteger(counts.unknown),
        }
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
    JSON.stringify(Object.keys(counts).sort()) ===
      JSON.stringify([...OUTBOX_STATUS_KEYS].sort()) &&
    Object.values(outboxStatusCounts).every((count) => count !== null);
  const hasOutboxEvidence =
    value.outboxStatusCounts !== undefined ||
    value.totalOutboxDocuments !== undefined ||
    value.outboxCountsVerified !== undefined;
  if (
    !outcomes.has(outcome) ||
    !phases.has(phase) ||
    !/^[a-f0-9]{32}$/.test(cycleId) ||
    (!terminal && !/^[a-f0-9]{64}$/.test(continuationStateDigestSha256)) ||
    (terminal && continuationStateDigestSha256) ||
    (terminal && !validTerminalTimes) ||
    (terminal && !/^[a-f0-9]{64}$/.test(mutationGenerationDigestSha256)) ||
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
    !/^[a-f0-9]{64}$/.test(targetConfigurationDigestSha256) ||
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

function safeProviderCode(value) {
  const code = String(value ?? "").toUpperCase();
  return /^[A-Z][A-Z0-9_]{0,79}$/.test(code) ? code : "UNCLASSIFIED";
}

async function readResponseJson(response) {
  const responseAmbiguous =
    response.ok ||
    response.status >= 500 ||
    [408, 425, 429].includes(response.status);
  const declaredLength = Number(response.headers?.get?.("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_RESPONSE_BYTES) {
    throw new ReconciliationOperatorError("RECONCILIATION_RESPONSE_TOO_LARGE", {
      ambiguous: responseAmbiguous,
    });
  }
  let text = "";
  try {
    text = await response.text();
  } catch (_) {
    throw new ReconciliationOperatorError(
      "RECONCILIATION_RESPONSE_UNREADABLE",
      {
        ambiguous: responseAmbiguous,
      },
    );
  }
  if (Buffer.byteLength(text, "utf8") > MAX_RESPONSE_BYTES) {
    text = "";
    throw new ReconciliationOperatorError("RECONCILIATION_RESPONSE_TOO_LARGE", {
      ambiguous: responseAmbiguous,
    });
  }
  try {
    const parsed = JSON.parse(text);
    text = "";
    return parsed;
  } catch (_) {
    text = "";
    throw new ReconciliationOperatorError("RECONCILIATION_RESPONSE_INVALID", {
      ambiguous: responseAmbiguous,
    });
  }
}

async function requestReconciliationJson({
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

  const payload = await readResponseJson(response);
  if (!response.ok) {
    const providerCode = safeProviderCode(payload?.code);
    const ambiguous =
      response.status >= 500 || [408, 425, 429].includes(response.status);
    throw new ReconciliationOperatorError(
      `RECONCILIATION_HTTP_${response.status}_${providerCode}`,
      { ambiguous },
    );
  }
  return payload;
}

async function requestPage(options) {
  const page = redactedPage(await requestReconciliationJson(options));
  if (!page) {
    throw new ReconciliationOperatorError("RECONCILIATION_RESPONSE_INVALID", {
      ambiguous: true,
    });
  }
  return page;
}

function redactedRecoveryState(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const phase = String(value.phase ?? "");
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
      ? redactedPage({
          ...value,
          outcome: "complete",
          phase: "complete",
          continuationStateDigestSha256: "",
        })
      : null;
  if (
    value.outcome !== "recovery_state" ||
    !new Set(["products", "mappings", "verify", "complete"]).has(phase) ||
    acknowledgedPages === null ||
    !/^[a-f0-9]{64}$/.test(continuationStateDigestSha256) ||
    !/^[a-f0-9]{40}$/.test(deployedAppCommit) ||
    !/^[a-f0-9]{64}$/.test(targetConfigurationDigestSha256) ||
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
    cycleId: String(value.cycleId),
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

async function requestRecoveryState(options) {
  const state = redactedRecoveryState(await requestReconciliationJson(options));
  if (!state) {
    throw new ReconciliationOperatorError(
      "RECONCILIATION_RECOVERY_RESPONSE_INVALID",
      { ambiguous: false, needsReview: true },
    );
  }
  return state;
}

function iso(clock) {
  const value = clock();
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) {
    throw new ReconciliationOperatorError("OPERATOR_CLOCK_INVALID");
  }
  return date.toISOString();
}

// Authority evidence is not a public formatter. Only the module-private live
// execution path may finalize it once a future reviewed executor is enabled.
function finalizeRedactedReconciliationReceipt(input) {
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
    !/^[a-f0-9]{64}$/.test(input.targetConfigurationDigestSha256) ||
    !/^[a-f0-9]{32}$/.test(input.cycleId) ||
    !/^[a-f0-9]{64}$/.test(input.mutationGenerationDigestSha256) ||
    !/^[a-f0-9]{64}$/.test(input.completionDigest) ||
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
    JSON.stringify(Object.keys(finalized)) !==
    JSON.stringify(FINALIZED_RECONCILIATION_ARTIFACT_KEYS)
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

/**
 * Runs one server-owned cycle. The server persists each acknowledged cursor;
 * this client carries only its opaque state digest. A reviewed resume verifies
 * the immutable deployment binding before continuing. Network, timeout, or
 * malformed-success ambiguity stops immediately and is never blindly retried.
 */
// Module-private by design. The legacy CLI stops before this path. The enabled
// writer owns its separate private copy inside the zero-export high-level
// executor, so an importer cannot substitute dependency-injected responses for
// attested production reconciliation evidence.
export function reconciliationOperationInputSha256({
  pageSize = 200,
  pollMs = 65_000,
  maxSteps = 10_000,
  maxElapsedMs = 24 * 60 * 60 * 1000,
  requestTimeoutMs = 570_000,
} = {}) {
  return sha256(
    JSON.stringify({
      pageSize,
      pollMs,
      maxSteps,
      maxElapsedMs,
      requestTimeoutMs,
    }),
  );
}

function exactContinuationState(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const expectedKeys = [
    "acknowledgedPages",
    "continuationStateDigestSha256",
    "cycleId",
    "mappingScanComplete",
    "productScanComplete",
  ];
  if (
    JSON.stringify(Object.keys(value).sort()) !==
      JSON.stringify(expectedKeys) ||
    !/^[a-f0-9]{32}$/.test(String(value.cycleId ?? "")) ||
    !/^[a-f0-9]{64}$/.test(String(value.continuationStateDigestSha256 ?? "")) ||
    nonNegativeInteger(value.acknowledgedPages) === null ||
    typeof value.productScanComplete !== "boolean" ||
    typeof value.mappingScanComplete !== "boolean" ||
    (value.mappingScanComplete && !value.productScanComplete)
  ) {
    return null;
  }
  return Object.freeze({
    cycleId: value.cycleId,
    continuationStateDigestSha256: value.continuationStateDigestSha256,
    acknowledgedPages: value.acknowledgedPages,
    productScanComplete: value.productScanComplete,
    mappingScanComplete: value.mappingScanComplete,
  });
}

async function runFullCatalogReconciliation({
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
      : exactContinuationState(continuationState);
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
    !/^[a-f0-9]{64}$/.test(String(expectedCandidateManifestSha256 ?? ""))
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
    reviewedResume,
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
  const startedAt = iso(clock);
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
        if ((await resolveExactCommit()) !== appCommit) {
          throw new Error("changed");
        }
        recovery = await requestRecoveryState({
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
          !/^[a-f0-9]{64}$/.test(completion.mutationGenerationDigestSha256) ||
          !/^[a-f0-9]{64}$/.test(completion.completionDigest)
        ) {
          throw new ReconciliationOperatorError(
            "RECONCILIATION_RECOVERED_COMPLETION_EVIDENCE_INVALID",
            { ambiguous: false, needsReview: true },
          );
        }
        return finalizeRedactedReconciliationReceipt({
          verifiedAt: iso(clock),
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
      // Inspection is deliberately write-free. The high-level executor binds
      // these exact facts into a private capability and obtains a fresh TTY
      // authorization before invoking the continuation path.
      return Object.freeze({
        outcome: "continuation_authorization_required",
        cycleId: recovery.cycleId,
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
      // Re-resolve governed authority immediately before every server call;
      // each page may enqueue or commit reconciliation state.
      try {
        if ((await resolveExactCommit()) !== appCommit) {
          throw new Error("changed");
        }
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
        page = await requestPage({
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
      if (page.outcome === "scan_complete") {
        mappingScanComplete = true;
      }

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
          !/^[a-f0-9]{64}$/.test(page.mutationGenerationDigestSha256) ||
          !/^[a-f0-9]{64}$/.test(page.completionDigest)
        ) {
          throw new ReconciliationOperatorError(
            "RECONCILIATION_COMPLETION_EVIDENCE_INVALID",
            { ambiguous: true },
          );
        }
        const verifiedAt = iso(clock);
        return finalizeRedactedReconciliationReceipt({
          verifiedAt,
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

function positiveInteger(value, name, { minimum = 1, maximum } = {}) {
  const parsed = Number(value);
  if (
    !Number.isSafeInteger(parsed) ||
    parsed < minimum ||
    (maximum !== undefined && parsed > maximum)
  ) {
    throw new ReconciliationOperatorError(`${name}_INVALID`);
  }
  return parsed;
}

export function parseRunnerArguments(argv) {
  const values = new Map();
  let reviewedResume = false;
  let execute = false;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith("--") || argument.includes("=")) {
      throw new ReconciliationOperatorError("OPERATOR_ARGUMENT_INVALID");
    }
    const key = argument.slice(2);
    if (key === "reviewed-resume") {
      if (reviewedResume) {
        throw new ReconciliationOperatorError("OPERATOR_ARGUMENT_DUPLICATE");
      }
      reviewedResume = true;
      continue;
    }
    if (key === "execute") {
      if (execute) {
        throw new ReconciliationOperatorError("OPERATOR_ARGUMENT_DUPLICATE");
      }
      execute = true;
      continue;
    }
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      throw new ReconciliationOperatorError("OPERATOR_ARGUMENT_INVALID");
    }
    if (values.has(key)) {
      throw new ReconciliationOperatorError("OPERATOR_ARGUMENT_DUPLICATE");
    }
    values.set(key, next);
    index += 1;
  }
  const allowed = new Set([
    "expected-app-commit",
    "expected-current-main-commit",
    "candidate-manifest-path",
    "expected-candidate-manifest-sha256",
    "receipt-path",
    "prior-needs-review-receipt-path",
    "expected-prior-needs-review-receipt-sha256",
    "page-size",
    "poll-ms",
    "max-steps",
    "max-elapsed-ms",
    "request-timeout-ms",
  ]);
  if ([...values.keys()].some((key) => !allowed.has(key))) {
    throw new ReconciliationOperatorError("OPERATOR_ARGUMENT_FORBIDDEN");
  }
  const expectedAppCommit = String(values.get("expected-app-commit") ?? "");
  if (!/^[a-f0-9]{40}$/.test(expectedAppCommit)) {
    throw new ReconciliationOperatorError("EXPECTED_APP_COMMIT_INVALID");
  }
  const expectedCurrentMainCommit = String(
    values.get("expected-current-main-commit") ?? "",
  );
  if (
    !/^[a-f0-9]{40}$/.test(expectedCurrentMainCommit) ||
    expectedCurrentMainCommit !== FROZEN_APP_MAIN_COMMIT
  ) {
    throw new ReconciliationOperatorError(
      "EXPECTED_CURRENT_MAIN_COMMIT_INVALID",
    );
  }
  const receiptPath = String(values.get("receipt-path") ?? "");
  const candidateManifestPath = String(
    values.get("candidate-manifest-path") ?? "",
  );
  const expectedCandidateManifestSha256 = String(
    values.get("expected-candidate-manifest-sha256") ?? "",
  );
  const priorNeedsReviewReceiptPath = String(
    values.get("prior-needs-review-receipt-path") ?? "",
  );
  const expectedPriorNeedsReviewReceiptSha256 = String(
    values.get("expected-prior-needs-review-receipt-sha256") ?? "",
  );
  if (
    (execute &&
      (!receiptPath ||
        !path.isAbsolute(receiptPath) ||
        path.resolve(receiptPath) !== receiptPath ||
        !candidateManifestPath ||
        !path.isAbsolute(candidateManifestPath) ||
        path.resolve(candidateManifestPath) !== candidateManifestPath ||
        candidateManifestPath === receiptPath ||
        !/^[a-f0-9]{64}$/.test(expectedCandidateManifestSha256))) ||
    (execute &&
      reviewedResume &&
      (!priorNeedsReviewReceiptPath ||
        !path.isAbsolute(priorNeedsReviewReceiptPath) ||
        path.resolve(priorNeedsReviewReceiptPath) !==
          priorNeedsReviewReceiptPath ||
        priorNeedsReviewReceiptPath === receiptPath ||
        priorNeedsReviewReceiptPath === candidateManifestPath ||
        !/^[a-f0-9]{64}$/.test(expectedPriorNeedsReviewReceiptSha256))) ||
    (execute &&
      !reviewedResume &&
      (priorNeedsReviewReceiptPath || expectedPriorNeedsReviewReceiptSha256)) ||
    (!execute && receiptPath) ||
    (!execute && reviewedResume) ||
    (!execute &&
      (candidateManifestPath ||
        expectedCandidateManifestSha256 ||
        priorNeedsReviewReceiptPath ||
        expectedPriorNeedsReviewReceiptSha256))
  ) {
    throw new ReconciliationOperatorError("OPERATOR_RECEIPT_EXECUTION_INVALID");
  }
  return {
    execute,
    dryRun: !execute,
    receiptPath: execute ? receiptPath : null,
    candidateManifestPath: execute ? candidateManifestPath : null,
    expectedCandidateManifestSha256: execute
      ? expectedCandidateManifestSha256
      : null,
    expectedAppCommit,
    expectedCurrentMainCommit,
    reviewedResume,
    priorNeedsReviewReceiptPath: reviewedResume
      ? priorNeedsReviewReceiptPath
      : null,
    expectedPriorNeedsReviewReceiptSha256: reviewedResume
      ? expectedPriorNeedsReviewReceiptSha256
      : null,
    pageSize: positiveInteger(values.get("page-size") ?? 200, "PAGE_SIZE", {
      maximum: 200,
    }),
    pollMs: positiveInteger(values.get("poll-ms") ?? 65_000, "POLL_MS", {
      minimum: 1_000,
      maximum: 10 * 60_000,
    }),
    maxSteps: positiveInteger(values.get("max-steps") ?? 10_000, "MAX_STEPS", {
      maximum: 100_000,
    }),
    maxElapsedMs: positiveInteger(
      values.get("max-elapsed-ms") ?? 24 * 60 * 60_000,
      "MAX_ELAPSED_MS",
      { minimum: 60_000, maximum: 7 * 24 * 60 * 60_000 },
    ),
    requestTimeoutMs: positiveInteger(
      values.get("request-timeout-ms") ?? 570_000,
      "REQUEST_TIMEOUT_MS",
      { minimum: 10_000, maximum: 600_000 },
    ),
  };
}

async function main() {
  try {
    const options = parseRunnerArguments(process.argv.slice(2));
    if (options.execute) {
      throw new ReconciliationOperatorError(
        "PRODUCTION_RECONCILIATION_EXECUTOR_NOT_ENABLED",
      );
    }
    process.stdout.write(
      `${JSON.stringify(
        {
          schemaVersion: 1,
          outcome: "dry_run_only",
          dryRun: true,
          remoteWriteAttempted: false,
          receiptPersisted: false,
          firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
          appCommit: options.expectedAppCommit,
          currentMainCommit: options.expectedCurrentMainCommit,
          targetConfigurationDigestSha256:
            nativeCatalogTargetConfigurationDigestSha256(),
          executeGate: "separate_production_sync_authorization_required",
        },
        null,
        2,
      )}\n`,
    );
  } catch (error) {
    const safe =
      error instanceof ReconciliationOperatorError
        ? error
        : new ReconciliationOperatorError("RECONCILIATION_OPERATOR_FAILED");
    const needsReview = safe.needsReview || safe.ambiguous;
    process.stderr.write(
      `${JSON.stringify({
        outcome: needsReview ? "needs_review" : "blocked",
        code: safe.code,
        ambiguous: safe.ambiguous,
        retryAllowed: false,
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
