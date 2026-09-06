#!/usr/bin/env node

import {
  execFile as nodeExecFile,
  spawn as nodeSpawn,
} from "node:child_process";
import { createHash } from "node:crypto";
import { chmod, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { promisify } from "node:util";

import { APP_REPOSITORY_ROOT } from "./production-candidate-manifest.mjs";
import {
  PRODUCTION_WRITE_AUTHORITY,
  PINNED_FIREBASE_CLI,
} from "./production-write-receipt.mjs";
import {
  assertNoSourceDeploymentDotenv,
  canonicalFirestoreIndexConfiguration,
} from "./guard-whatsapp-catalog-functions-deploy.mjs";
import {
  collectFirebaseGen1RuntimeConfigHashSha1,
  computeCandidateFirebaseSourceContract,
  verifyCandidateFirebaseFunctionHashes,
} from "./firebase-function-source-binding.mjs";
import {
  DEVELOPMENT_FIREBASE_PROJECT_ID,
  DEVELOPMENT_FIREBASE_PROJECT_NUMBER,
  DEVELOPMENT_RELEASE_ENVIRONMENT_ANCHORS,
  DEVELOPMENT_RELEASE_FUNCTIONS,
  DEVELOPMENT_RELEASE_FUNCTION_SECRET_REFS,
  REQUIRED_RELEASE_COMPOSITE_INDEXES,
} from "./release-deployment-contract.mjs";
import { scrubCredentialEnvironment } from "./run-whatsapp-catalog-full-reconciliation.mjs";

const execFile = promisify(nodeExecFile);
const CODEX_GUARD = "/Users/admin/.codex/identity-governance/bin/codex-guard";
const FUNCTIONS_DIRECTORY = path.join(APP_REPOSITORY_ROOT, "functions");
const FIRESTORE_INDEXES_PATH = path.join(
  APP_REPOSITORY_ROOT,
  "firestore.indexes.json",
);
const DEVELOPMENT_PREDEPLOY_GUARD_PATH = path.join(
  FUNCTIONS_DIRECTORY,
  "scripts/assert-development-release-predeploy.mjs",
);
const MAX_OUTPUT_BYTES = 10 * 1024 * 1024;
const SHA1 = /^[a-f0-9]{40}$/;
const PLATFORM_ENVIRONMENT_KEYS = new Set([
  "FIREBASE_CONFIG",
  "GCLOUD_PROJECT",
  "GCP_PROJECT",
  "FUNCTION_TARGET",
  "FUNCTION_SIGNATURE_TYPE",
  "K_SERVICE",
  "K_REVISION",
  "PORT",
  "EVENTARC_CLOUD_EVENT_SOURCE",
]);

export class DevelopmentReleaseDeployError extends Error {
  constructor(code, { needsReview = false } = {}) {
    super(code);
    this.name = "DevelopmentReleaseDeployError";
    this.code = code;
    this.needsReview = needsReview;
    this.retryAllowed = false;
  }
}

function fail(code, options) {
  throw new DevelopmentReleaseDeployError(code, options);
}

export async function assertDevelopmentSourceDeploymentClean(
  functionsDirectory = FUNCTIONS_DIRECTORY,
) {
  try {
    await assertNoSourceDeploymentDotenv(functionsDirectory);
  } catch (_) {
    fail("DEVELOPMENT_RELEASE_SOURCE_DOTENV_PRESENT");
  }
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function exactAuthority(value) {
  return (
    value?.project_id === PRODUCTION_WRITE_AUTHORITY.projectId &&
    value?.project === PRODUCTION_WRITE_AUTHORITY.project &&
    value?.component === PRODUCTION_WRITE_AUTHORITY.component &&
    value?.role === PRODUCTION_WRITE_AUTHORITY.role &&
    value?.entity === PRODUCTION_WRITE_AUTHORITY.entity &&
    value?.account === PRODUCTION_WRITE_AUTHORITY.account &&
    value?.repository === PRODUCTION_WRITE_AUTHORITY.repository &&
    value?.matched_by === PRODUCTION_WRITE_AUTHORITY.matchedBy
  );
}

export async function resolveDevelopmentAuthorityCommit({
  expectedAppCommit,
  execFileImpl = execFile,
} = {}) {
  if (!SHA1.test(String(expectedAppCommit ?? ""))) {
    fail("DEVELOPMENT_RELEASE_COMMIT_INVALID");
  }
  const environment = scrubCredentialEnvironment();
  let status;
  let head;
  let upstream;
  let mergeBase;
  let authority;
  try {
    const [statusResult, headResult, upstreamResult, authorityResult] =
      await Promise.all([
        execFileImpl("git", ["status", "--porcelain"], {
          cwd: APP_REPOSITORY_ROOT,
          encoding: "utf8",
          env: environment,
        }),
        execFileImpl("git", ["rev-parse", "HEAD"], {
          cwd: APP_REPOSITORY_ROOT,
          encoding: "utf8",
          env: environment,
        }),
        execFileImpl("git", ["rev-parse", "origin/main"], {
          cwd: APP_REPOSITORY_ROOT,
          encoding: "utf8",
          env: environment,
        }),
        execFileImpl(CODEX_GUARD, ["resolve", "--path", APP_REPOSITORY_ROOT], {
          cwd: APP_REPOSITORY_ROOT,
          encoding: "utf8",
          env: environment,
        }),
      ]);
    status = String(statusResult.stdout ?? "");
    head = String(headResult.stdout ?? "").trim();
    upstream = String(upstreamResult.stdout ?? "").trim();
    authority = JSON.parse(String(authorityResult.stdout ?? ""));
    mergeBase = String(
      (
        await execFileImpl("git", ["merge-base", head, upstream], {
          cwd: APP_REPOSITORY_ROOT,
          encoding: "utf8",
          env: environment,
        })
      ).stdout ?? "",
    ).trim();
  } catch (_) {
    fail("DEVELOPMENT_RELEASE_AUTHORITY_UNVERIFIED");
  }
  if (status.trim()) fail("DEVELOPMENT_RELEASE_CHECKOUT_DIRTY");
  if (
    head !== expectedAppCommit ||
    !SHA1.test(upstream) ||
    mergeBase !== upstream ||
    !exactAuthority(authority)
  ) {
    fail("DEVELOPMENT_RELEASE_AUTHORITY_MISMATCH");
  }
  return Object.freeze({ appCommit: head, authorityMainCommit: upstream });
}

function predeployCommand(resource) {
  return (
    "/usr/bin/env -i PATH=/opt/homebrew/bin:/usr/bin:/bin " +
    'TMPDIR="$TMPDIR" ' +
    'GCLOUD_PROJECT="$GCLOUD_PROJECT" PROJECT_DIR="$PROJECT_DIR" ' +
    'RESOURCE_DIR="$RESOURCE_DIR" /opt/homebrew/bin/node ' +
    `"${DEVELOPMENT_PREDEPLOY_GUARD_PATH}" --resource ${resource}`
  );
}

export function developmentReleaseFirebaseConfig(lane, { configDir } = {}) {
  if (!path.isAbsolute(String(configDir ?? ""))) {
    fail("DEVELOPMENT_RELEASE_CONFIG_DIR_INVALID");
  }
  if (lane === "functions") {
    return {
      functions: [
        {
          source: FUNCTIONS_DIRECTORY,
          codebase: "default",
          configDir,
          ignore: [
            "node_modules",
            ".git",
            "firebase-debug.log",
            "firebase-debug.*.log",
          ],
          predeploy: [
            predeployCommand("functions"),
            'npm --prefix "$RESOURCE_DIR" run lint',
            'npm --prefix "$RESOURCE_DIR" run build',
          ],
        },
      ],
    };
  }
  if (lane === "indexes") {
    const indexesPath = path.join(configDir, "firestore.indexes.json");
    return {
      firestore: {
        predeploy: [predeployCommand("firestore")],
        indexes: indexesPath,
      },
    };
  }
  fail("DEVELOPMENT_RELEASE_LANE_INVALID");
}

export function developmentReleaseSelector(lane, { functionName } = {}) {
  if (lane === "indexes") return "firestore:indexes";
  if (lane === "functions") {
    if (functionName !== undefined) {
      if (!DEVELOPMENT_RELEASE_FUNCTIONS.includes(functionName)) {
        fail("DEVELOPMENT_RELEASE_FUNCTION_SELECTOR_INVALID");
      }
      return `functions:${functionName}`;
    }
    return DEVELOPMENT_RELEASE_FUNCTIONS.map(
      (name) => `functions:${name}`,
    ).join(",");
  }
  fail("DEVELOPMENT_RELEASE_LANE_INVALID");
}

export function developmentCodexGuardArguments({
  lane,
  functionName,
  configPath,
  dryRun,
}) {
  if (!path.isAbsolute(String(configPath ?? ""))) {
    fail("DEVELOPMENT_RELEASE_CONFIG_PATH_INVALID");
  }
  const args = [
    "firebase-deploy",
    "--project",
    "spaza-one",
    "--environment",
    "firebase_development",
  ];
  if (dryRun) args.push("--dry-run");
  args.push(
    "--",
    "--config",
    configPath,
    "--only",
    developmentReleaseSelector(lane, { functionName }),
  );
  return args;
}

function waitForSpawn(command, args, options, spawnImpl = nodeSpawn) {
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = spawnImpl(command, args, options);
    } catch (_) {
      reject(new Error("spawn"));
      return;
    }
    child.once("error", () => reject(new Error("spawn")));
    child.once("exit", (code, signal) =>
      code === 0 && signal === null
        ? resolve()
        : reject(new Error("child_exit")),
    );
  });
}

function allFunctionRows(value) {
  const rows = Array.isArray(value)
    ? value
    : Array.isArray(value?.result)
      ? value.result
      : null;
  if (!rows) fail("DEVELOPMENT_RELEASE_FUNCTION_READBACK_INVALID");
  if (
    new Set(rows.map((row) => String(row?.id ?? ""))).size !== rows.length ||
    rows.some(
      (row) =>
        typeof row?.id !== "string" ||
        !row.id ||
        (DEVELOPMENT_RELEASE_FUNCTIONS.includes(row.id) &&
          (row.region !== "us-central1" ||
            row.runtime !== "nodejs20" ||
            row.codebase !== "default" ||
            row.entryPoint !== row.id)),
    )
  ) {
    fail("DEVELOPMENT_RELEASE_FUNCTION_READBACK_INVALID");
  }
  return rows;
}

function exactFunctionRow(rows, functionName, { allowMissing = false } = {}) {
  const selected = rows.filter((row) => String(row?.id ?? "") === functionName);
  if (selected.length === 0 && allowMissing) return null;
  if (selected.length !== 1) {
    fail("DEVELOPMENT_RELEASE_FUNCTION_READBACK_INVALID");
  }
  const row = selected[0];
  if (
    row.project !== DEVELOPMENT_FIREBASE_PROJECT_ID ||
    row.region !== "us-central1" ||
    row.runtime !== "nodejs20" ||
    row.codebase !== "default" ||
    row.entryPoint !== row.id
  ) {
    fail("DEVELOPMENT_RELEASE_FUNCTION_READBACK_INVALID");
  }
  return row;
}

function canonicalRemoteFunctionState(rows) {
  return rows.map((row) => [
    String(row.id),
    {
      environment: Object.entries(row.environmentVariables ?? {})
        .filter(([key]) => !PLATFORM_ENVIRONMENT_KEYS.has(key))
        .sort(([left], [right]) => left.localeCompare(right)),
      secrets: (row.secretEnvironmentVariables ?? [])
        .map((entry) => ({
          key: String(entry?.key ?? ""),
          projectId: String(entry?.projectId ?? ""),
          secret: String(entry?.secret ?? ""),
          version: String(entry?.version ?? ""),
        }))
        .sort((left, right) => left.key.localeCompare(right.key)),
    },
  ]);
}

function userEnvironmentEntries(row) {
  const raw = row?.environmentVariables;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    fail("DEVELOPMENT_RELEASE_FUNCTION_ENVIRONMENT_INVALID");
  }
  const entries = Object.entries(raw)
    .filter(([key]) => !PLATFORM_ENVIRONMENT_KEYS.has(key))
    .sort(([left], [right]) => left.localeCompare(right));
  if (
    entries.some(
      ([key, value]) =>
        !/^[A-Z][A-Z0-9_]*$/.test(key) || typeof value !== "string",
    )
  ) {
    fail("DEVELOPMENT_RELEASE_FUNCTION_ENVIRONMENT_INVALID");
  }
  return entries;
}

function escapedDotenvValue(value) {
  return value.replace(/[\n\r\t\v\\'"]/g, (character) => {
    return {
      "\n": "\\n",
      "\r": "\\r",
      "\t": "\\t",
      "\v": "\\v",
      "\\": "\\\\",
      "'": "\\'",
      '"': '\\"',
    }[character];
  });
}

export function buildDevelopmentReleaseEnvironment({
  rows,
  functionName,
  appCommit,
} = {}) {
  if (!SHA1.test(String(appCommit ?? "")) || !Array.isArray(rows)) {
    fail("DEVELOPMENT_RELEASE_FUNCTION_ENVIRONMENT_INVALID");
  }
  if (!DEVELOPMENT_RELEASE_FUNCTIONS.includes(functionName)) {
    fail("DEVELOPMENT_RELEASE_FUNCTION_SELECTOR_INVALID");
  }
  const allRows = allFunctionRows(rows);
  const target = exactFunctionRow(allRows, functionName, {
    allowMissing: functionName === "getWhatsAppCatalogSyncStatusV2",
  });
  const anchorName = target
    ? functionName
    : DEVELOPMENT_RELEASE_ENVIRONMENT_ANCHORS[functionName];
  const anchor = exactFunctionRow(allRows, anchorName);
  if (!target && (anchor.secretEnvironmentVariables ?? []).length !== 0) {
    fail("DEVELOPMENT_RELEASE_ENVIRONMENT_ANCHOR_SECRET_MISMATCH");
  }
  if (target) assertExpectedDevelopmentSecrets([target]);
  const values = new Map(userEnvironmentEntries(anchor));
  if (
    values.get("SPAZAONE_ENVIRONMENT") !== "development" ||
    (values.has("SPAZAONE_FIREBASE_PROJECT_ID") &&
      values.get("SPAZAONE_FIREBASE_PROJECT_ID") !==
        DEVELOPMENT_FIREBASE_PROJECT_ID)
  ) {
    fail("DEVELOPMENT_RELEASE_FUNCTION_ENVIRONMENT_TARGET_MISMATCH");
  }
  values.set("BUILD_COMMIT", appCommit);
  const entries = [...values.entries()].sort(([left], [right]) =>
    left.localeCompare(right),
  );
  const normalized = `${entries
    .map(([key, value]) => `${key}="${escapedDotenvValue(value)}"`)
    .join("\n")}\n`;
  return Object.freeze({
    functionName,
    anchorFunctionName: anchorName,
    targetExisted: target !== null,
    baselineAnchorState: canonicalRemoteFunctionState([anchor])[0][1],
    baselineTargetState: target
      ? canonicalRemoteFunctionState([target])[0][1]
      : null,
    entries: Object.freeze(entries.map((entry) => Object.freeze([...entry]))),
    normalized,
    sha256: sha256(Buffer.from(normalized, "utf8")),
  });
}

function assertExpectedDevelopmentSecrets(rows) {
  for (const row of rows) {
    const expected = [
      ...(DEVELOPMENT_RELEASE_FUNCTION_SECRET_REFS[row.id] ?? []),
    ].sort();
    const actual = (row.secretEnvironmentVariables ?? [])
      .map((entry) => String(entry?.key ?? ""))
      .sort();
    if (
      JSON.stringify(actual) !== JSON.stringify(expected) ||
      (row.secretEnvironmentVariables ?? []).some(
        (entry) =>
          !/^[1-9][0-9]*$/.test(String(entry?.version ?? "")) ||
          String(entry?.projectId ?? "") !==
            DEVELOPMENT_FIREBASE_PROJECT_NUMBER ||
          (String(entry?.secret ?? "") !== String(entry?.key ?? "") &&
            !String(entry?.secret ?? "").endsWith(
              `/secrets/${String(entry?.key ?? "")}`,
            )),
      )
    ) {
      fail("DEVELOPMENT_RELEASE_SECRET_BINDING_MISMATCH");
    }
  }
}

async function listDevelopmentFunctions(execFileImpl = execFile) {
  let parsed;
  try {
    const result = await execFileImpl(
      PINNED_FIREBASE_CLI.executablePath,
      [
        "--project",
        DEVELOPMENT_FIREBASE_PROJECT_ID,
        "--account",
        "tsepo.ntsaba@thedelta.io",
        "--non-interactive",
        "--json",
        "functions:list",
      ],
      {
        cwd: APP_REPOSITORY_ROOT,
        encoding: "utf8",
        maxBuffer: MAX_OUTPUT_BYTES,
        env: scrubCredentialEnvironment(),
      },
    );
    parsed = JSON.parse(String(result.stdout ?? ""));
  } catch (_) {
    fail("DEVELOPMENT_RELEASE_FUNCTION_READBACK_FAILED");
  }
  return allFunctionRows(parsed);
}

export async function assertRequiredDevelopmentSecrets({
  execFileImpl = execFile,
} = {}) {
  const required = ["WHATSAPP_CATALOG_STATUS_CURSOR_SECRET"];
  for (const secretName of required) {
    try {
      const result = await execFileImpl(
        PINNED_FIREBASE_CLI.executablePath,
        [
          "--project",
          DEVELOPMENT_FIREBASE_PROJECT_ID,
          "--account",
          "tsepo.ntsaba@thedelta.io",
          "--non-interactive",
          "--json",
          "functions:secrets:get",
          secretName,
        ],
        {
          cwd: APP_REPOSITORY_ROOT,
          encoding: "utf8",
          maxBuffer: MAX_OUTPUT_BYTES,
          env: scrubCredentialEnvironment(),
        },
      );
      const metadata = JSON.parse(String(result.stdout ?? ""));
      const versions = metadata?.result?.secrets;
      const hasEnabledVersion =
        metadata?.status === "success" &&
        Array.isArray(versions) &&
        versions.some(
          (entry) =>
            String(entry?.secret?.projectId ?? "") ===
              DEVELOPMENT_FIREBASE_PROJECT_NUMBER &&
            entry?.secret?.name === secretName &&
            entry?.state === "ENABLED" &&
            /^[1-9][0-9]*$/.test(String(entry?.versionId ?? "")),
        );
      if (!hasEnabledVersion) throw new Error("version");
    } catch (_) {
      fail("MISSING_REQUIRED_DEVELOPMENT_SECRET");
    }
  }
  return Object.freeze({ requiredSecretCount: required.length });
}

export function requiredReleaseIndexesActive(rows) {
  if (!Array.isArray(rows)) return false;
  const normalized = rows.map((row) => ({
    collectionGroup: String(row?.collectionGroup ?? ""),
    state: String(row?.state ?? ""),
    fields: (row?.fields ?? [])
      .filter((field) => String(field?.fieldPath ?? "") !== "__name__")
      .map((field) => ({
        fieldPath: String(field?.fieldPath ?? ""),
        order: String(field?.order ?? ""),
      })),
  }));
  return REQUIRED_RELEASE_COMPOSITE_INDEXES.every((required) =>
    normalized.some(
      (actual) =>
        actual.state === "READY" &&
        actual.collectionGroup === required.collectionGroup &&
        JSON.stringify(actual.fields) ===
          JSON.stringify(
            required.fields.filter((field) => field.fieldPath !== "__name__"),
          ),
    ),
  );
}

export function parseFirebasePrettyIndexStates(text) {
  if (typeof text !== "string" || Buffer.byteLength(text) > MAX_OUTPUT_BYTES) {
    fail("DEVELOPMENT_RELEASE_INDEX_STATE_READBACK_INVALID");
  }
  const rows = [];
  for (const line of text.replaceAll("\r\n", "\n").split("\n")) {
    const match = line.match(
      /^\[([A-Z_]+)\] \(([^()]+)\) -- ((?:\([^(),]+,(?:ASCENDING|DESCENDING|CONTAINS)\) ?)+) -- /,
    );
    if (!match) continue;
    const fields = [
      ...match[3].matchAll(/\(([^(),]+),(ASCENDING|DESCENDING|CONTAINS)\)/g),
    ].map((field) => ({ fieldPath: field[1], order: field[2] }));
    rows.push({
      state: match[1],
      collectionGroup: match[2],
      fields,
    });
  }
  if (rows.length === 0) {
    fail("DEVELOPMENT_RELEASE_INDEX_STATE_READBACK_INVALID");
  }
  return rows;
}

async function readDevelopmentIndexes(execFileImpl = execFile) {
  let parsed;
  try {
    const result = await execFileImpl(
      PINNED_FIREBASE_CLI.executablePath,
      [
        "--project",
        DEVELOPMENT_FIREBASE_PROJECT_ID,
        "--account",
        "tsepo.ntsaba@thedelta.io",
        "--non-interactive",
        "firestore:indexes",
        "--database",
        "(default)",
      ],
      {
        cwd: APP_REPOSITORY_ROOT,
        encoding: "utf8",
        maxBuffer: MAX_OUTPUT_BYTES,
        env: scrubCredentialEnvironment(),
      },
    );
    parsed = JSON.parse(String(result.stdout ?? ""));
  } catch (_) {
    fail("DEVELOPMENT_RELEASE_INDEX_READBACK_FAILED");
  }
  return parsed;
}

async function readDevelopmentIndexStates(execFileImpl = execFile) {
  let text;
  try {
    const result = await execFileImpl(
      PINNED_FIREBASE_CLI.executablePath,
      [
        "--project",
        DEVELOPMENT_FIREBASE_PROJECT_ID,
        "--account",
        "tsepo.ntsaba@thedelta.io",
        "--non-interactive",
        "firestore:indexes",
        "--database",
        "(default)",
        "--pretty",
      ],
      {
        cwd: APP_REPOSITORY_ROOT,
        encoding: "utf8",
        maxBuffer: MAX_OUTPUT_BYTES,
        env: { ...scrubCredentialEnvironment(), NO_COLOR: "1" },
      },
    );
    text = String(result.stdout ?? "");
  } catch (_) {
    fail("DEVELOPMENT_RELEASE_INDEX_STATE_READBACK_FAILED");
  }
  return parseFirebasePrettyIndexStates(text);
}

function canonicalIndexConfiguration(value) {
  try {
    return canonicalFirestoreIndexConfiguration(value);
  } catch (_) {
    fail("DEVELOPMENT_RELEASE_INDEX_CONFIGURATION_INVALID");
  }
}

function indexConfigurationDigest(value) {
  return sha256(JSON.stringify(canonicalIndexConfiguration(value)));
}

function indexKey(value) {
  return JSON.stringify(value);
}

function requiredCanonicalIndexes() {
  return canonicalIndexConfiguration({
    indexes: REQUIRED_RELEASE_COMPOSITE_INDEXES.map((entry) => ({
      collectionGroup: entry.collectionGroup,
      queryScope: entry.queryScope,
      fields: entry.fields.map((field) => ({ ...field })),
    })),
    fieldOverrides: [],
  }).indexes;
}

export function requiredReleaseIndexesConfigured(value) {
  let canonical;
  try {
    canonical = canonicalFirestoreIndexConfiguration(value);
  } catch (_) {
    return false;
  }
  const actual = new Set(canonical.indexes.map(indexKey));
  return requiredCanonicalIndexes().every((entry) =>
    actual.has(indexKey(entry)),
  );
}

/**
 * Produces a Firebase indexes document from the live development baseline plus
 * only the two reviewed composites. Unrelated local indexes and TTL overrides
 * are deliberately excluded so this lane cannot activate or delete them.
 */
export function synthesizeDevelopmentIndexConfiguration({
  remote,
  local,
} = {}) {
  const baseline = canonicalIndexConfiguration(remote);
  const localConfiguration = canonicalIndexConfiguration(local);
  const required = requiredCanonicalIndexes();
  const localKeys = new Set(localConfiguration.indexes.map(indexKey));
  if (required.some((entry) => !localKeys.has(indexKey(entry)))) {
    fail("DEVELOPMENT_RELEASE_REQUIRED_INDEX_SOURCE_MISSING");
  }
  const baselineKeys = new Set(baseline.indexes.map(indexKey));
  const additions = required.filter(
    (entry) => !baselineKeys.has(indexKey(entry)),
  );
  const configuration = canonicalIndexConfiguration({
    indexes: [...baseline.indexes, ...additions],
    fieldOverrides: baseline.fieldOverrides,
  });
  const expectedKeys = new Set(configuration.indexes.map(indexKey));
  const addedKeys = [...expectedKeys]
    .filter((entry) => !baselineKeys.has(entry))
    .sort();
  if (
    baseline.indexes.some((entry) => !expectedKeys.has(indexKey(entry))) ||
    JSON.stringify(configuration.fieldOverrides) !==
      JSON.stringify(baseline.fieldOverrides) ||
    JSON.stringify(addedKeys) !==
      JSON.stringify(additions.map(indexKey).sort()) ||
    addedKeys.some(
      (entry) => !required.some((item) => indexKey(item) === entry),
    )
  ) {
    fail("DEVELOPMENT_RELEASE_INDEX_DELTA_INVALID");
  }
  return Object.freeze({
    baselineConfiguration: baseline,
    configuration,
    baselineConfigurationSha256: indexConfigurationDigest(baseline),
    expectedConfigurationSha256: indexConfigurationDigest(configuration),
    addedIndexCount: additions.length,
    addedIndexSetSha256: sha256(JSON.stringify(addedKeys)),
    fieldOverrideCount: baseline.fieldOverrides.length,
  });
}

async function prepareDevelopmentIndexPlan({ execFileImpl = execFile } = {}) {
  const [localText, remote] = await Promise.all([
    readFile(FIRESTORE_INDEXES_PATH, "utf8"),
    readDevelopmentIndexes(execFileImpl),
  ]);
  let local;
  try {
    local = JSON.parse(localText);
  } catch (_) {
    fail("DEVELOPMENT_RELEASE_INDEX_SOURCE_INVALID");
  }
  return synthesizeDevelopmentIndexConfiguration({ remote, local });
}

async function verifyDevelopmentIndexes({
  expectedConfiguration,
  execFileImpl = execFile,
} = {}) {
  const [remote, states] = await Promise.all([
    readDevelopmentIndexes(execFileImpl),
    readDevelopmentIndexStates(execFileImpl),
  ]);
  const canonicalRemote = canonicalIndexConfiguration(remote);
  const remoteConfigurationSha256 = indexConfigurationDigest(canonicalRemote);
  const expectedConfigurationMatches = expectedConfiguration
    ? remoteConfigurationSha256 ===
      indexConfigurationDigest(expectedConfiguration)
    : null;
  return Object.freeze({
    firebaseProjectId: DEVELOPMENT_FIREBASE_PROJECT_ID,
    expectedConfigurationMatches,
    requiredIndexesConfigured:
      requiredReleaseIndexesConfigured(canonicalRemote),
    requiredIndexesActive: requiredReleaseIndexesActive(states),
    remoteConfigurationSha256,
    remoteIndexCount: canonicalRemote.indexes.length,
    remoteFieldOverrideCount: canonicalRemote.fieldOverrides.length,
  });
}

async function assertDevelopmentIndexBaselineUnchanged(
  plan,
  execFileImpl = execFile,
) {
  const current = await readDevelopmentIndexes(execFileImpl);
  if (indexConfigurationDigest(current) !== plan.baselineConfigurationSha256) {
    fail("DEVELOPMENT_RELEASE_INDEX_BASELINE_CHANGED");
  }
}

async function assertDevelopmentFunctionBaselineUnchanged({
  plan,
  execFileImpl = execFile,
}) {
  const rows = await listDevelopmentFunctions(execFileImpl);
  const anchor = exactFunctionRow(rows, plan.anchorFunctionName);
  const target = exactFunctionRow(rows, plan.functionName, {
    allowMissing:
      plan.functionName === "getWhatsAppCatalogSyncStatusV2" &&
      !plan.targetExisted,
  });
  const anchorState = canonicalRemoteFunctionState([anchor])[0][1];
  const targetState = target
    ? canonicalRemoteFunctionState([target])[0][1]
    : null;
  if (
    JSON.stringify(anchorState) !== JSON.stringify(plan.baselineAnchorState) ||
    JSON.stringify(targetState) !== JSON.stringify(plan.baselineTargetState)
  ) {
    fail("DEVELOPMENT_RELEASE_FUNCTION_BASELINE_CHANGED");
  }
}

async function verifyDevelopmentFunction({
  functionName,
  expectedAppCommit,
  baselineRows,
  expectedEnvironment,
  execFileImpl = execFile,
} = {}) {
  const rows = await listDevelopmentFunctions(execFileImpl);
  const after = exactFunctionRow(rows, functionName);
  const before = exactFunctionRow(baselineRows, functionName, {
    allowMissing: functionName === "getWhatsAppCatalogSyncStatusV2",
  });
  const afterEnvironment = userEnvironmentEntries(after);
  if (
    JSON.stringify(afterEnvironment) !==
    JSON.stringify(expectedEnvironment.entries)
  ) {
    fail("DEVELOPMENT_RELEASE_FUNCTION_ENVIRONMENT_CHANGED", {
      needsReview: true,
    });
  }
  assertExpectedDevelopmentSecrets([after]);
  if (before) {
    const beforeSecrets = canonicalRemoteFunctionState([before])[0][1].secrets;
    const afterSecrets = canonicalRemoteFunctionState([after])[0][1].secrets;
    if (JSON.stringify(beforeSecrets) !== JSON.stringify(afterSecrets)) {
      fail("DEVELOPMENT_RELEASE_SECRET_BINDING_CHANGED", {
        needsReview: true,
      });
    }
  }
  let sourceContract;
  try {
    const runtimeConfigHashSha1 =
      await collectFirebaseGen1RuntimeConfigHashSha1({
        firebaseCliPath: PINNED_FIREBASE_CLI.executablePath,
        projectId: DEVELOPMENT_FIREBASE_PROJECT_ID,
        account: "tsepo.ntsaba@thedelta.io",
        anchorFunctionId: "getEnvironmentInfo",
        environment: scrubCredentialEnvironment(),
        execFileImpl,
      });
    sourceContract = await computeCandidateFirebaseSourceContract({
      repositoryRoot: APP_REPOSITORY_ROOT,
      functionsDirectory: FUNCTIONS_DIRECTORY,
      expectedAppCommit,
      runtimeConfigHashSha1,
      environment: scrubCredentialEnvironment(),
      execFileImpl,
    });
  } catch (_) {
    fail("DEVELOPMENT_RELEASE_SOURCE_BINDING_FAILED", { needsReview: true });
  }
  let proof;
  try {
    proof = verifyCandidateFirebaseFunctionHashes({
      endpoints: [after],
      expectedFunctionNames: [functionName],
      expectedSecretReferences: DEVELOPMENT_RELEASE_FUNCTION_SECRET_REFS,
      sourceContract,
      projectId: DEVELOPMENT_FIREBASE_PROJECT_ID,
      region: "us-central1",
      configuredEnvironmentEntries: expectedEnvironment.entries,
    });
  } catch (_) {
    fail("DEVELOPMENT_RELEASE_SOURCE_BINDING_FAILED", { needsReview: true });
  }
  if (!proof.candidateSourceBindingMatches) {
    fail("DEVELOPMENT_RELEASE_SOURCE_BINDING_MISMATCH", { needsReview: true });
  }
  return Object.freeze({
    functionName,
    firebaseProjectId: DEVELOPMENT_FIREBASE_PROJECT_ID,
    environmentPreservedExceptBuildCommit: true,
    buildCommit: expectedAppCommit,
    environmentTransitionSha256: sha256(
      JSON.stringify({
        before: before ? canonicalRemoteFunctionState([before])[0][1] : null,
        after: canonicalRemoteFunctionState([after])[0][1],
      }),
    ),
    sourceBindingVerified: true,
    candidateSourceContractSha256: proof.candidateSourceContractSha256,
    candidateProviderBindingSetSha256: proof.candidateProviderBindingSetSha256,
  });
}

async function removeDevelopmentTemporaryDirectory({
  temporaryDirectory,
  execute,
  removeTemporaryDirectory,
}) {
  try {
    await removeTemporaryDirectory(temporaryDirectory, {
      recursive: true,
      force: true,
    });
  } catch (_) {
    fail("DEVELOPMENT_RELEASE_TEMP_CLEANUP_FAILED", {
      needsReview: execute,
    });
  }
}

async function dispatchDevelopmentFunction({
  plan,
  expectedAppCommit,
  execute,
  baselineRows,
  resolveCommit,
  spawnImpl,
  execFileImpl,
  assertSourceDeploymentClean,
  temporaryRoot,
  removeTemporaryDirectory,
}) {
  const temporaryDirectory = await mkdtemp(
    path.join(temporaryRoot, "spazaone-development-release-"),
  );
  let operationError = null;
  try {
    await chmod(temporaryDirectory, 0o700);
    const configPath = path.join(temporaryDirectory, "firebase.json");
    await writeFile(
      path.join(temporaryDirectory, `.env.${DEVELOPMENT_FIREBASE_PROJECT_ID}`),
      plan.normalized,
      { flag: "wx", mode: 0o600 },
    );
    await writeFile(
      configPath,
      `${JSON.stringify(
        developmentReleaseFirebaseConfig("functions", {
          configDir: temporaryDirectory,
        }),
        null,
        2,
      )}\n`,
      { flag: "wx", mode: 0o600 },
    );
    await resolveCommit({ expectedAppCommit, execFileImpl });
    await assertDevelopmentFunctionBaselineUnchanged({
      plan,
      execFileImpl,
    });
    // Check again immediately before handing the live source tree to Firebase.
    // Dotenv files are ignored by git and therefore bypass the clean-tree gate.
    await assertSourceDeploymentClean();
    await waitForSpawn(
      CODEX_GUARD,
      developmentCodexGuardArguments({
        lane: "functions",
        functionName: plan.functionName,
        configPath,
        dryRun: !execute,
      }),
      {
        cwd: APP_REPOSITORY_ROOT,
        env: scrubCredentialEnvironment(),
        stdio: "inherit",
      },
      spawnImpl,
    );
  } catch (error) {
    operationError =
      error instanceof DevelopmentReleaseDeployError
        ? error
        : new DevelopmentReleaseDeployError(
            execute
              ? "DEVELOPMENT_RELEASE_DEPLOY_NEEDS_REVIEW"
              : "DEVELOPMENT_RELEASE_DRY_RUN_FAILED",
            { needsReview: execute },
          );
  }
  await removeDevelopmentTemporaryDirectory({
    temporaryDirectory,
    execute,
    removeTemporaryDirectory,
  });
  if (operationError) throw operationError;
  const readback = execute
    ? await verifyDevelopmentFunction({
        functionName: plan.functionName,
        expectedAppCommit,
        baselineRows,
        expectedEnvironment: plan,
        execFileImpl,
      })
    : null;
  return Object.freeze({
    functionName: plan.functionName,
    selector: developmentReleaseSelector("functions", {
      functionName: plan.functionName,
    }),
    environmentConfigurationSha256: plan.sha256,
    readback,
  });
}

async function dispatchDevelopmentIndexes({
  plan,
  expectedAppCommit,
  execute,
  resolveCommit,
  spawnImpl,
  execFileImpl,
  temporaryRoot,
  removeTemporaryDirectory,
}) {
  const temporaryDirectory = await mkdtemp(
    path.join(temporaryRoot, "spazaone-development-release-"),
  );
  let operationError = null;
  try {
    await chmod(temporaryDirectory, 0o700);
    const configPath = path.join(temporaryDirectory, "firebase.json");
    await writeFile(
      path.join(temporaryDirectory, "firestore.indexes.json"),
      `${JSON.stringify(plan.configuration, null, 2)}\n`,
      { flag: "wx", mode: 0o600 },
    );
    await writeFile(
      configPath,
      `${JSON.stringify(
        developmentReleaseFirebaseConfig("indexes", {
          configDir: temporaryDirectory,
        }),
        null,
        2,
      )}\n`,
      { flag: "wx", mode: 0o600 },
    );
    await resolveCommit({ expectedAppCommit, execFileImpl });
    await assertDevelopmentIndexBaselineUnchanged(plan, execFileImpl);
    await waitForSpawn(
      CODEX_GUARD,
      developmentCodexGuardArguments({
        lane: "indexes",
        configPath,
        dryRun: !execute,
      }),
      {
        cwd: APP_REPOSITORY_ROOT,
        env: scrubCredentialEnvironment(),
        stdio: "inherit",
      },
      spawnImpl,
    );
  } catch (error) {
    operationError =
      error instanceof DevelopmentReleaseDeployError
        ? error
        : new DevelopmentReleaseDeployError(
            execute
              ? "DEVELOPMENT_RELEASE_DEPLOY_NEEDS_REVIEW"
              : "DEVELOPMENT_RELEASE_DRY_RUN_FAILED",
            { needsReview: execute },
          );
  }
  await removeDevelopmentTemporaryDirectory({
    temporaryDirectory,
    execute,
    removeTemporaryDirectory,
  });
  if (operationError) throw operationError;
  const readback = execute
    ? await verifyDevelopmentIndexes({
        expectedConfiguration: plan.configuration,
        execFileImpl,
      })
    : null;
  if (readback && !readback.expectedConfigurationMatches) {
    fail("DEVELOPMENT_RELEASE_INDEX_READBACK_MISMATCH", {
      needsReview: true,
    });
  }
  return Object.freeze({
    selector: developmentReleaseSelector("indexes"),
    baselineConfigurationSha256: plan.baselineConfigurationSha256,
    expectedConfigurationSha256: plan.expectedConfigurationSha256,
    addedIndexCount: plan.addedIndexCount,
    addedIndexSetSha256: plan.addedIndexSetSha256,
    preservedFieldOverrideCount: plan.fieldOverrideCount,
    readback,
  });
}

export async function runDevelopmentReleaseDeployment({
  lane,
  expectedAppCommit,
  execute = false,
  readbackOnly = false,
  resolveCommit = resolveDevelopmentAuthorityCommit,
  spawnImpl = nodeSpawn,
  execFileImpl = execFile,
  assertSourceDeploymentClean = assertDevelopmentSourceDeploymentClean,
  temporaryRoot = os.tmpdir(),
  removeTemporaryDirectory = rm,
} = {}) {
  if (!new Set(["functions", "indexes"]).has(lane)) {
    fail("DEVELOPMENT_RELEASE_LANE_INVALID");
  }
  if (readbackOnly && (execute || lane !== "indexes")) {
    fail("DEVELOPMENT_RELEASE_ARGUMENT_INVALID");
  }
  const authority = await resolveCommit({ expectedAppCommit, execFileImpl });
  if (readbackOnly) {
    return Object.freeze({
      outcome: "readback_complete",
      lane,
      appCommit: authority.appCommit,
      authorityMainCommit: authority.authorityMainCommit,
      firebaseProjectId: DEVELOPMENT_FIREBASE_PROJECT_ID,
      readback: await verifyDevelopmentIndexes({ execFileImpl }),
      remoteWriteAttempted: false,
      retryAllowed: false,
    });
  }
  if (lane === "indexes") {
    const plan = await prepareDevelopmentIndexPlan({ execFileImpl });
    const step = await dispatchDevelopmentIndexes({
      plan,
      expectedAppCommit,
      execute,
      resolveCommit,
      spawnImpl,
      execFileImpl,
      temporaryRoot,
      removeTemporaryDirectory,
    });
    const indexesActive = Boolean(step.readback?.requiredIndexesActive);
    return Object.freeze({
      outcome: execute
        ? indexesActive
          ? "deployed_and_read_back"
          : "deployed_waiting_for_indexes"
        : "dry_run_complete",
      lane,
      selector: step.selector,
      appCommit: authority.appCommit,
      authorityMainCommit: authority.authorityMainCommit,
      firebaseProjectId: DEVELOPMENT_FIREBASE_PROJECT_ID,
      indexPlan: Object.freeze({
        baselineConfigurationSha256: step.baselineConfigurationSha256,
        expectedConfigurationSha256: step.expectedConfigurationSha256,
        addedIndexCount: step.addedIndexCount,
        addedIndexSetSha256: step.addedIndexSetSha256,
        preservedFieldOverrideCount: step.preservedFieldOverrideCount,
      }),
      readback: step.readback,
      remoteWriteAttempted: execute,
      retryAllowed: false,
    });
  }

  // This metadata-only lookup deliberately runs before any function dispatch.
  // The cursor key is required by source and must be provisioned separately.
  await assertSourceDeploymentClean();
  await assertRequiredDevelopmentSecrets({ execFileImpl });
  const indexGate = await verifyDevelopmentIndexes({ execFileImpl });
  if (
    !indexGate.requiredIndexesConfigured ||
    !indexGate.requiredIndexesActive
  ) {
    fail("DEVELOPMENT_RELEASE_INDEX_GATE_NOT_READY");
  }
  const baselineRows = await listDevelopmentFunctions(execFileImpl);
  const plans = DEVELOPMENT_RELEASE_FUNCTIONS.map((functionName) =>
    buildDevelopmentReleaseEnvironment({
      rows: baselineRows,
      functionName,
      appCommit: expectedAppCommit,
    }),
  );
  const steps = [];
  for (const plan of plans) {
    try {
      steps.push(
        await dispatchDevelopmentFunction({
          plan,
          expectedAppCommit,
          execute,
          baselineRows,
          resolveCommit,
          spawnImpl,
          execFileImpl,
          assertSourceDeploymentClean,
          temporaryRoot,
          removeTemporaryDirectory,
        }),
      );
    } catch (error) {
      if (
        execute &&
        steps.length > 0 &&
        error instanceof DevelopmentReleaseDeployError &&
        !error.needsReview
      ) {
        fail("DEVELOPMENT_RELEASE_PARTIAL_DEPLOY_NEEDS_REVIEW", {
          needsReview: true,
        });
      }
      throw error;
    }
  }
  return Object.freeze({
    outcome: execute ? "deployed_and_read_back" : "dry_run_complete",
    lane,
    selector: developmentReleaseSelector(lane),
    appCommit: authority.appCommit,
    authorityMainCommit: authority.authorityMainCommit,
    firebaseProjectId: DEVELOPMENT_FIREBASE_PROJECT_ID,
    indexGate,
    functionSteps: Object.freeze(steps),
    remoteWriteAttempted: execute,
    retryAllowed: false,
  });
}

function parseArguments(argv) {
  let lane = "";
  let expectedAppCommit = "";
  let execute = false;
  let readbackOnly = false;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--execute") {
      if (execute) fail("DEVELOPMENT_RELEASE_ARGUMENT_INVALID");
      execute = true;
      continue;
    }
    if (argument === "--readback-only") {
      if (readbackOnly) fail("DEVELOPMENT_RELEASE_ARGUMENT_INVALID");
      readbackOnly = true;
      continue;
    }
    if (argument === "--lane" || argument === "--expected-app-commit") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        fail("DEVELOPMENT_RELEASE_ARGUMENT_INVALID");
      }
      if (argument === "--lane" && !lane) lane = value;
      else if (argument === "--expected-app-commit" && !expectedAppCommit) {
        expectedAppCommit = value;
      } else fail("DEVELOPMENT_RELEASE_ARGUMENT_INVALID");
      index += 1;
      continue;
    }
    fail("DEVELOPMENT_RELEASE_ARGUMENT_FORBIDDEN");
  }
  if (
    !new Set(["functions", "indexes"]).has(lane) ||
    !SHA1.test(expectedAppCommit) ||
    (readbackOnly && (execute || lane !== "indexes"))
  ) {
    fail("DEVELOPMENT_RELEASE_ARGUMENT_INVALID");
  }
  return { lane, expectedAppCommit, execute, readbackOnly };
}

async function main() {
  try {
    const result = await runDevelopmentReleaseDeployment(
      parseArguments(process.argv.slice(2)),
    );
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } catch (error) {
    const safe =
      error instanceof DevelopmentReleaseDeployError
        ? error
        : new DevelopmentReleaseDeployError("DEVELOPMENT_RELEASE_FAILED");
    process.stderr.write(
      `${JSON.stringify({
        outcome: safe.needsReview ? "needs_review" : "blocked",
        code: safe.code,
        remoteWriteAttempted: safe.needsReview,
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
