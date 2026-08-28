#!/usr/bin/env node

import {
  execFile as nodeExecFile,
  spawn as nodeSpawn,
} from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmod,
  mkdtemp,
  readFile,
  realpath,
  readdir,
  rm,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { promisify } from "node:util";

import {
  APP_REPOSITORY_ROOT,
  FROZEN_APP_MAIN_COMMIT,
  PRODUCTION_FIREBASE_ACCOUNT,
  ReconciliationOperatorError,
  resolveAuthorityAppCommit,
  scrubCredentialEnvironment,
} from "./run-whatsapp-catalog-full-reconciliation.mjs";
import {
  IMMUTABLE_TARGET_CONFIGURATION,
  PRODUCTION_FIREBASE_PROJECT_ID,
  PRODUCTION_NATIVE_CATALOG_TARGET,
  nativeCatalogTargetConfigurationDigestSha256,
} from "./whatsapp-catalog-production-target.mjs";
import {
  PINNED_FIREBASE_CLI,
  PINNED_GCLOUD_CLI,
  assertPinnedProductionToolchain,
} from "./production-write-receipt.mjs";
import { loadAndValidateProductionCandidateManifest } from "./production-candidate-manifest.mjs";
import {
  FirebaseFunctionSourceBindingError,
  collectFirebaseGen1RuntimeConfigHashSha1,
  computeCandidateFirebaseSourceContract,
  verifyCandidateFirebaseFunctionHashes,
} from "./firebase-function-source-binding.mjs";

export {
  IMMUTABLE_TARGET_CONFIGURATION,
  PRODUCTION_NATIVE_CATALOG_TARGET,
  nativeCatalogTargetConfigurationDigestSha256,
};

const CODEX_GUARD = "/Users/admin/.codex/identity-governance/bin/codex-guard";
const FUNCTIONS_DIRECTORY = path.join(APP_REPOSITORY_ROOT, "functions");
const MAX_DOTENV_BYTES = 16 * 1024;
const MAX_READBACK_BYTES = 10 * 1024 * 1024;
const execFile = promisify(nodeExecFile);

export const PRODUCTION_FIRESTORE_DATABASE_ID = "(default)";
export const PRODUCTION_FIREBASE_FUNCTION_REGION = "us-central1";
export const CATALOG_POLICY_LANES = Object.freeze([
  "firestore-rules",
  "firestore-indexes",
]);
export const REQUIRED_CATALOG_TTL_FIELDS = Object.freeze([
  "whatsappCatalogCartReplacements/expiresAt",
  "whatsappProductListDeliveries/expiresAt",
  "whatsappProductListRecipientState/expiresAt",
]);

export const NATIVE_CATALOG_NEW_FUNCTIONS = Object.freeze([
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

export const NATIVE_CATALOG_EXISTING_FUNCTIONS = Object.freeze([
  "getMerchantCatalogBotHttp",
  "checkoutCart",
  "cancelOrder",
  "finalizeOnlinePaid",
  "updateOrderPayment",
]);

export const NATIVE_CATALOG_SYNC_FUNCTIONS = Object.freeze([
  "onMerchantProductCatalogChange",
  "syncWhatsAppMerchantCatalog",
  "reconcileWhatsAppMerchantCatalog",
  "runWhatsAppCatalogFullReconciliationBotHttp",
  "getMerchantWhatsAppCatalogCompletenessBotHttp",
  "getMerchantWhatsAppProductListBotHttp",
]);

// These are all new functions introduced by the native-catalogue release. No
// pre-existing production function is ever redeployed with a catalogue dotenv,
// so an unknown remote environment cannot be replaced during cutover.
export const NATIVE_CATALOG_DELIVERY_FUNCTIONS = Object.freeze([
  "resolveMerchantWhatsAppCatalogProductBotHttp",
  "sendMerchantWhatsAppCatalogBotHttp",
  "getWhatsAppProductListDeliveryStatusBotHttp",
  "monitorWhatsAppProductListDeliveries",
  "replaceWhatsAppCatalogCartBotHttp",
]);

export const NATIVE_CATALOG_FUNCTION_SECRET_REFS = Object.freeze({
  onMerchantProductCatalogChange: Object.freeze([]),
  syncWhatsAppMerchantCatalog: Object.freeze(["META_CATALOG_ACCESS_TOKEN"]),
  reconcileWhatsAppMerchantCatalog: Object.freeze([]),
  runWhatsAppCatalogFullReconciliationBotHttp: Object.freeze([
    "PASELLA_BOT_TOKEN",
  ]),
  getMerchantWhatsAppCatalogCompletenessBotHttp: Object.freeze([
    "PASELLA_BOT_TOKEN",
  ]),
  getMerchantWhatsAppProductListBotHttp: Object.freeze(["PASELLA_BOT_TOKEN"]),
  getWhatsAppCatalogSyncStatusV1: Object.freeze([]),
  resolveMerchantWhatsAppCatalogProductBotHttp: Object.freeze([
    "PASELLA_BOT_TOKEN",
    "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
  ]),
  sendMerchantWhatsAppCatalogBotHttp: Object.freeze([
    "PASELLA_BOT_TOKEN",
    "META_WHATSAPP_ACCESS_TOKEN",
    "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
  ]),
  getWhatsAppProductListDeliveryStatusBotHttp: Object.freeze([
    "PASELLA_BOT_TOKEN",
  ]),
  monitorWhatsAppProductListDeliveries: Object.freeze([
    "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
  ]),
  replaceWhatsAppCatalogCartBotHttp: Object.freeze([
    "PASELLA_BOT_TOKEN",
    "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
  ]),
});

export const NATIVE_CATALOG_EXISTING_FUNCTION_SECRET_REFS = Object.freeze({
  getMerchantCatalogBotHttp: Object.freeze([
    "PASELLA_BOT_TOKEN",
    "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
  ]),
  checkoutCart: Object.freeze(["PASELLA_BOT_TOKEN"]),
  cancelOrder: Object.freeze(["PASELLA_BOT_TOKEN", "PAYSTACK_SECRET_KEY"]),
  finalizeOnlinePaid: Object.freeze([]),
  updateOrderPayment: Object.freeze([]),
});

export const CATALOG_FUNCTION_LANES = Object.freeze([
  "dark-new",
  "existing-code",
  "sync-enable",
  "controlled-delivery-enable",
  "all-eligible-delivery-enable",
  "delivery-disable",
  "sync-disable",
]);

const DEPLOYMENT_ENV_KEYS = Object.freeze([
  "SPAZAONE_ENVIRONMENT",
  "SPAZAONE_FIREBASE_PROJECT_ID",
  "BUILD_COMMIT",
  "WHATSAPP_CATALOG_QUEUE_ENABLED",
  "WHATSAPP_CATALOG_SYNC_ENABLED",
  "WHATSAPP_CATALOG_ID",
  "WHATSAPP_CATALOG_CANARY_MERCHANT_IDS",
  "WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED",
  "WHATSAPP_CATALOG_MAX_BATCH_SIZE",
  "META_CATALOG_PROVIDER_MODE",
  "META_GRAPH_API_VERSION",
  "WHATSAPP_SENDER_NUMBER_ID",
  "WHATSAPP_PRODUCT_LIST_ENABLED",
  "WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS",
  "WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED",
  "WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES",
  "WHATSAPP_PRODUCT_LIST_RECIPIENT_COOLDOWN_MS",
  "WHATSAPP_PRODUCT_LIST_MAX_ATTEMPTS",
  "WHATSAPP_CATALOG_PAIR_LIMIT_PAUSE_MS",
  "META_WHATSAPP_MESSAGE_PROVIDER_MODE",
]);

const FORBIDDEN_ENV_NAMES = Object.freeze([
  "PASELLA_BOT_TOKEN",
  "META_CATALOG_ACCESS_TOKEN",
  "META_WHATSAPP_ACCESS_TOKEN",
  "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY",
]);

export class CatalogDeploymentGuardError extends Error {
  constructor(
    code,
    {
      ambiguous = false,
      needsReview = false,
      cleanupStatus,
      cleanupDirectory,
      cleanupAction,
    } = {},
  ) {
    super(code);
    this.name = "CatalogDeploymentGuardError";
    this.code = code;
    this.ambiguous = ambiguous;
    this.needsReview = needsReview;
    this.cleanupStatus = cleanupStatus;
    this.cleanupDirectory = cleanupDirectory;
    this.cleanupAction = cleanupAction;
  }
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

export function parseStrictDotenv(text) {
  if (typeof text !== "string" || Buffer.byteLength(text) > MAX_DOTENV_BYTES) {
    throw new CatalogDeploymentGuardError("CATALOG_DOTENV_SIZE_INVALID");
  }
  if (text.charCodeAt(0) === 0xfeff) {
    throw new CatalogDeploymentGuardError("CATALOG_DOTENV_ENCODING_INVALID");
  }
  const entries = new Map();
  for (const rawLine of text.replaceAll("\r\n", "\n").split("\n")) {
    if (!rawLine) continue;
    const match = rawLine.match(/^([A-Z][A-Z0-9_]*)=([A-Za-z0-9._,-]*)$/);
    if (!match) {
      throw new CatalogDeploymentGuardError("CATALOG_DOTENV_LINE_INVALID");
    }
    const [, key, value] = match;
    if (entries.has(key)) {
      throw new CatalogDeploymentGuardError("CATALOG_DOTENV_KEY_DUPLICATE");
    }
    if (
      FORBIDDEN_ENV_NAMES.includes(key) ||
      /(?:TOKEN|SECRET|PASSWORD|PRIVATE_KEY|API_KEY)/.test(key)
    ) {
      throw new CatalogDeploymentGuardError("CATALOG_DOTENV_SECRET_FORBIDDEN");
    }
    entries.set(key, value);
  }
  return entries;
}

function commaSeparatedIdentifiers(value, pattern, maximum) {
  const entries = String(value ?? "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
  if (
    entries.length > maximum ||
    new Set(entries).size !== entries.length ||
    entries.some((entry) => !pattern.test(entry))
  ) {
    return null;
  }
  return entries;
}

function controlledRolloutScope(actual) {
  const merchantIds = commaSeparatedIdentifiers(
    actual.get("WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS"),
    /^[A-Za-z0-9_-]{1,200}$/,
    20,
  );
  const recipientHashes = commaSeparatedIdentifiers(
    actual.get("WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES"),
    /^[a-f0-9]{64}$/,
    20,
  );
  if (!merchantIds?.length || !recipientHashes?.length) {
    throw new CatalogDeploymentGuardError("CONTROLLED_DELIVERY_SCOPE_INVALID");
  }
  return { merchantIds, recipientHashes };
}

function expectedDeploymentEnvironment(lane, appCommit, actual = new Map()) {
  if (!/^[a-f0-9]{40}$/.test(appCommit)) {
    throw new CatalogDeploymentGuardError("APP_COMMIT_INVALID");
  }
  const syncEnabled = new Set([
    "sync-enable",
    "controlled-delivery-enable",
    "all-eligible-delivery-enable",
    "delivery-disable",
  ]).has(lane);
  const deliveryEnabled = new Set([
    "controlled-delivery-enable",
    "all-eligible-delivery-enable",
  ]).has(lane);
  const fullDelivery = lane === "all-eligible-delivery-enable";
  const configuredLane = new Set([
    "dark-new",
    "sync-enable",
    "controlled-delivery-enable",
    "all-eligible-delivery-enable",
    "delivery-disable",
    "sync-disable",
  ]).has(lane);
  if (!configuredLane) {
    throw new CatalogDeploymentGuardError("CATALOG_DEPLOY_LANE_INVALID");
  }
  const controlledScope =
    lane === "controlled-delivery-enable"
      ? controlledRolloutScope(actual)
      : { merchantIds: [], recipientHashes: [] };
  return new Map([
    ["SPAZAONE_ENVIRONMENT", "production"],
    ["SPAZAONE_FIREBASE_PROJECT_ID", PRODUCTION_FIREBASE_PROJECT_ID],
    ["BUILD_COMMIT", appCommit],
    ["WHATSAPP_CATALOG_QUEUE_ENABLED", syncEnabled ? "true" : "false"],
    ["WHATSAPP_CATALOG_SYNC_ENABLED", syncEnabled ? "true" : "false"],
    ["WHATSAPP_CATALOG_ID", PRODUCTION_NATIVE_CATALOG_TARGET.catalogId],
    ["WHATSAPP_CATALOG_CANARY_MERCHANT_IDS", ""],
    ["WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED", syncEnabled ? "true" : "false"],
    ["WHATSAPP_CATALOG_MAX_BATCH_SIZE", "10"],
    ["META_CATALOG_PROVIDER_MODE", syncEnabled ? "live" : "disabled"],
    [
      "META_GRAPH_API_VERSION",
      PRODUCTION_NATIVE_CATALOG_TARGET.graphApiVersion,
    ],
    [
      "WHATSAPP_SENDER_NUMBER_ID",
      PRODUCTION_NATIVE_CATALOG_TARGET.senderPhoneNumberId,
    ],
    ["WHATSAPP_PRODUCT_LIST_ENABLED", deliveryEnabled ? "true" : "false"],
    [
      "WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS",
      controlledScope.merchantIds.join(","),
    ],
    [
      "WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED",
      fullDelivery ? "true" : "false",
    ],
    [
      "WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES",
      controlledScope.recipientHashes.join(","),
    ],
    ["WHATSAPP_PRODUCT_LIST_RECIPIENT_COOLDOWN_MS", "7000"],
    ["WHATSAPP_PRODUCT_LIST_MAX_ATTEMPTS", "3"],
    ["WHATSAPP_CATALOG_PAIR_LIMIT_PAUSE_MS", "86400000"],
    [
      "META_WHATSAPP_MESSAGE_PROVIDER_MODE",
      deliveryEnabled ? "live" : "disabled",
    ],
  ]);
}

export function validateCatalogDeploymentDotenv({ lane, text, appCommit }) {
  const actual = parseStrictDotenv(text);
  const expected = expectedDeploymentEnvironment(lane, appCommit, actual);
  const actualKeys = [...actual.keys()].sort();
  const expectedKeys = [...DEPLOYMENT_ENV_KEYS].sort();
  if (JSON.stringify(actualKeys) !== JSON.stringify(expectedKeys)) {
    throw new CatalogDeploymentGuardError("CATALOG_DOTENV_KEYSET_INVALID");
  }
  for (const [key, expectedValue] of expected) {
    if (actual.get(key) !== expectedValue) {
      throw new CatalogDeploymentGuardError(`CATALOG_DOTENV_${key}_INVALID`);
    }
  }
  const normalized = [...expected.entries()]
    .map(([key, value]) => `${key}=${value}`)
    .join("\n");
  const merchantScope = commaSeparatedIdentifiers(
    expected.get("WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS"),
    /^[A-Za-z0-9_-]{1,200}$/,
    20,
  );
  const recipientScope = commaSeparatedIdentifiers(
    expected.get("WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES"),
    /^[a-f0-9]{64}$/,
    20,
  );
  return {
    normalized: `${normalized}\n`,
    sha256: sha256(`${normalized}\n`),
    targetConfigurationDigestSha256:
      nativeCatalogTargetConfigurationDigestSha256(),
    keyNames: [...expected.keys()],
    rollout: {
      queueEnabled: expected.get("WHATSAPP_CATALOG_QUEUE_ENABLED") === "true",
      syncEnabled: expected.get("WHATSAPP_CATALOG_SYNC_ENABLED") === "true",
      catalogFullRolloutEnabled:
        expected.get("WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED") === "true",
      deliveryEnabled: expected.get("WHATSAPP_PRODUCT_LIST_ENABLED") === "true",
      deliveryFullRolloutEnabled:
        expected.get("WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED") === "true",
      catalogProviderMode: expected.get("META_CATALOG_PROVIDER_MODE"),
      messageProviderMode: expected.get("META_WHATSAPP_MESSAGE_PROVIDER_MODE"),
      merchantScopeCount: merchantScope?.length ?? 0,
      merchantScopeDigestSha256: sha256(
        (merchantScope ?? []).sort().join("\n"),
      ),
      recipientScopeCount: recipientScope?.length ?? 0,
      recipientScopeDigestSha256: sha256(
        (recipientScope ?? []).sort().join("\n"),
      ),
    },
  };
}

export function catalogFunctionSelector(lane) {
  const functions =
    lane === "dark-new"
      ? NATIVE_CATALOG_NEW_FUNCTIONS
      : lane === "existing-code"
        ? NATIVE_CATALOG_EXISTING_FUNCTIONS
        : lane === "sync-enable" || lane === "sync-disable"
          ? NATIVE_CATALOG_SYNC_FUNCTIONS
          : new Set([
                "controlled-delivery-enable",
                "all-eligible-delivery-enable",
                "delivery-disable",
              ]).has(lane)
            ? NATIVE_CATALOG_DELIVERY_FUNCTIONS
            : null;
  if (!functions) {
    throw new CatalogDeploymentGuardError("CATALOG_DEPLOY_LANE_INVALID");
  }
  return functions.map((name) => `functions:${name}`).join(",");
}

function deploymentDotenvName(name) {
  return (
    name === ".env" || (name.startsWith(".env.") && name !== ".env.example")
  );
}

export async function assertNoSourceDeploymentDotenv(
  functionsDirectory = FUNCTIONS_DIRECTORY,
) {
  const names = await readdir(functionsDirectory);
  if (names.some(deploymentDotenvName)) {
    throw new CatalogDeploymentGuardError("SOURCE_DEPLOYMENT_DOTENV_PRESENT");
  }
}

export function buildEphemeralFirebaseConfig({
  functionsDirectory,
  configDir,
}) {
  const functions = {
    source: functionsDirectory,
    codebase: "default",
    ignore: [
      "node_modules",
      ".git",
      "firebase-debug.log",
      "firebase-debug.*.log",
    ],
    predeploy: [
      'npm --prefix "$RESOURCE_DIR" run lint',
      'npm --prefix "$RESOURCE_DIR" run build',
    ],
  };
  if (configDir) functions.configDir = configDir;
  return {
    functions: [functions],
  };
}

export function buildEphemeralFirebasePolicyConfig() {
  return {
    firestore: {
      rules: path.join(APP_REPOSITORY_ROOT, "firestore.rules"),
      indexes: path.join(APP_REPOSITORY_ROOT, "firestore.indexes.json"),
    },
  };
}

function spawnAndWait(
  command,
  args,
  options,
  { spawnImpl = nodeSpawn, writeCapable = false } = {},
) {
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = spawnImpl(command, args, options);
    } catch (_) {
      reject(
        writeCapable
          ? new CatalogDeploymentGuardError(
              "CATALOG_DEPLOY_EXECUTION_NEEDS_REVIEW",
              { ambiguous: true, needsReview: true },
            )
          : new CatalogDeploymentGuardError(
              "CATALOG_DEPLOY_DRY_RUN_COMMAND_FAILED",
            ),
      );
      return;
    }
    child.once("error", () =>
      reject(
        writeCapable
          ? new CatalogDeploymentGuardError(
              "CATALOG_DEPLOY_EXECUTION_NEEDS_REVIEW",
              { ambiguous: true, needsReview: true },
            )
          : new CatalogDeploymentGuardError(
              "CATALOG_DEPLOY_DRY_RUN_COMMAND_FAILED",
            ),
      ),
    );
    child.once("exit", (code, signal) => {
      if (code === 0) resolve();
      else
        reject(
          writeCapable
            ? new CatalogDeploymentGuardError(
                "CATALOG_DEPLOY_EXECUTION_NEEDS_REVIEW",
                { ambiguous: true, needsReview: true },
              )
            : new CatalogDeploymentGuardError(
                signal
                  ? "CATALOG_DEPLOY_DRY_RUN_INTERRUPTED"
                  : "CATALOG_DEPLOY_DRY_RUN_COMMAND_FAILED",
              ),
        );
    });
  });
}

export async function assertPinnedFirebaseCli({ spawnImpl = nodeSpawn } = {}) {
  let output = "";
  await new Promise((resolve, reject) => {
    const child = spawnImpl(PINNED_FIREBASE_CLI.executablePath, ["--version"], {
      cwd: APP_REPOSITORY_ROOT,
      env: scrubCredentialEnvironment(),
      stdio: ["ignore", "pipe", "ignore"],
    });
    child.stdout.on("data", (chunk) => {
      output += String(chunk);
    });
    child.once("error", () => reject(new Error("spawn")));
    child.once("exit", (code) =>
      code === 0 ? resolve() : reject(new Error("exit")),
    );
  }).catch(() => {
    throw new CatalogDeploymentGuardError("FIREBASE_CLI_VERSION_UNVERIFIED");
  });
  if (output.trim().split(/\s+/)[0] !== PINNED_FIREBASE_CLI.version) {
    throw new CatalogDeploymentGuardError("FIREBASE_CLI_VERSION_MISMATCH");
  }
}

export function assertFirebaseCliEnvironmentPreservationSource(source) {
  if (
    typeof source !== "string" ||
    !/if\s*\(!usedDotenv\)\s*\{\s*wantE\.environmentVariables\s*=\s*\{\s*\.\.\.haveE\.environmentVariables,\s*\.\.\.wantE\.environmentVariables,\s*\};\s*\}/m.test(
      source,
    )
  ) {
    throw new CatalogDeploymentGuardError(
      "FIREBASE_CLI_ENVIRONMENT_PRESERVATION_UNVERIFIED",
    );
  }
}

export async function assertPinnedFirebaseCliEnvironmentPreservation({
  firebaseBinaryPath = PINNED_FIREBASE_CLI.executablePath,
  readFileImpl = readFile,
  realpathImpl = realpath,
} = {}) {
  let source;
  try {
    const entrypoint = await realpathImpl(firebaseBinaryPath);
    const preparePath = path.resolve(
      path.dirname(entrypoint),
      "../deploy/functions/prepare.js",
    );
    source = await readFileImpl(preparePath, "utf8");
  } catch (_) {
    throw new CatalogDeploymentGuardError(
      "FIREBASE_CLI_ENVIRONMENT_PRESERVATION_UNVERIFIED",
    );
  }
  assertFirebaseCliEnvironmentPreservationSource(source);
}

export function codexGuardDeployArguments({ lane, dryRun, configPath }) {
  const args = ["firebase-deploy", "--project", "spaza-one"];
  if (dryRun) args.push("--dry-run");
  args.push("--");
  if (configPath) args.push("--config", configPath);
  const selector =
    lane === "firestore-rules" || lane === "firestore-indexes"
      ? lane.replace("firestore-", "firestore:")
      : catalogFunctionSelector(lane);
  args.push("--only", selector);
  return args;
}

function catalogPolicySourcePath(lane) {
  if (lane === "firestore-rules") {
    return path.join(APP_REPOSITORY_ROOT, "firestore.rules");
  }
  if (lane === "firestore-indexes") {
    return path.join(APP_REPOSITORY_ROOT, "firestore.indexes.json");
  }
  throw new CatalogDeploymentGuardError("CATALOG_POLICY_LANE_INVALID");
}

function requiredTtlEntry(value) {
  return `${String(value?.collectionGroup ?? "")}/${String(value?.fieldPath ?? "")}`;
}

function exactRecordKeys(value, allowed) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  return Object.keys(value).every((key) => allowed.includes(key));
}

function canonicalIndexField(field) {
  if (
    !exactRecordKeys(field, [
      "fieldPath",
      "order",
      "arrayConfig",
      "vectorConfig",
    ]) ||
    typeof field.fieldPath !== "string" ||
    !field.fieldPath
  ) {
    throw new CatalogDeploymentGuardError(
      "CATALOG_FIRESTORE_INDEXES_SOURCE_INVALID",
    );
  }
  const modes = ["order", "arrayConfig", "vectorConfig"].filter(
    (key) => field[key] !== undefined,
  );
  if (modes.length !== 1) {
    throw new CatalogDeploymentGuardError(
      "CATALOG_FIRESTORE_INDEXES_SOURCE_INVALID",
    );
  }
  return {
    fieldPath: field.fieldPath,
    ...(field.order !== undefined ? { order: String(field.order) } : {}),
    ...(field.arrayConfig !== undefined
      ? { arrayConfig: String(field.arrayConfig) }
      : {}),
    ...(field.vectorConfig !== undefined
      ? { vectorConfig: field.vectorConfig }
      : {}),
  };
}

function canonicalIndexMode(mode) {
  if (
    !exactRecordKeys(mode, ["order", "arrayConfig", "queryScope"]) ||
    typeof mode.queryScope !== "string" ||
    (!mode.order && !mode.arrayConfig) ||
    (mode.order && mode.arrayConfig)
  ) {
    throw new CatalogDeploymentGuardError(
      "CATALOG_FIRESTORE_INDEXES_SOURCE_INVALID",
    );
  }
  return {
    queryScope: mode.queryScope,
    ...(mode.order ? { order: String(mode.order) } : {}),
    ...(mode.arrayConfig ? { arrayConfig: String(mode.arrayConfig) } : {}),
  };
}

export function canonicalFirestoreIndexConfiguration(value) {
  if (
    !exactRecordKeys(value, ["indexes", "fieldOverrides"]) ||
    !Array.isArray(value.indexes) ||
    !Array.isArray(value.fieldOverrides)
  ) {
    throw new CatalogDeploymentGuardError(
      "CATALOG_FIRESTORE_INDEXES_SOURCE_INVALID",
    );
  }
  const indexes = value.indexes
    .map((index) => {
      if (
        !exactRecordKeys(index, [
          "collectionGroup",
          "queryScope",
          "fields",
          "density",
        ]) ||
        typeof index.collectionGroup !== "string" ||
        !index.collectionGroup ||
        typeof index.queryScope !== "string" ||
        !Array.isArray(index.fields) ||
        index.fields.length < 1
      ) {
        throw new CatalogDeploymentGuardError(
          "CATALOG_FIRESTORE_INDEXES_SOURCE_INVALID",
        );
      }
      return {
        collectionGroup: index.collectionGroup,
        queryScope: index.queryScope,
        fields: index.fields.map(canonicalIndexField),
        ...(index.density !== undefined
          ? { density: String(index.density) }
          : {}),
      };
    })
    .sort((left, right) =>
      JSON.stringify(left).localeCompare(JSON.stringify(right)),
    );
  const fieldOverrides = value.fieldOverrides
    .map((override) => {
      if (
        !exactRecordKeys(override, [
          "collectionGroup",
          "fieldPath",
          "ttl",
          "indexes",
        ]) ||
        typeof override.collectionGroup !== "string" ||
        !override.collectionGroup ||
        typeof override.fieldPath !== "string" ||
        !override.fieldPath ||
        typeof override.ttl !== "boolean" ||
        !Array.isArray(override.indexes)
      ) {
        throw new CatalogDeploymentGuardError(
          "CATALOG_FIRESTORE_INDEXES_SOURCE_INVALID",
        );
      }
      return {
        collectionGroup: override.collectionGroup,
        fieldPath: override.fieldPath,
        ttl: override.ttl,
        indexes: override.indexes
          .map(canonicalIndexMode)
          .sort((left, right) =>
            JSON.stringify(left).localeCompare(JSON.stringify(right)),
          ),
      };
    })
    .sort((left, right) =>
      JSON.stringify(left).localeCompare(JSON.stringify(right)),
    );
  if (
    new Set(indexes.map((entry) => JSON.stringify(entry))).size !==
      indexes.length ||
    new Set(
      fieldOverrides.map(
        (entry) => `${entry.collectionGroup}/${entry.fieldPath}`,
      ),
    ).size !== fieldOverrides.length
  ) {
    throw new CatalogDeploymentGuardError(
      "CATALOG_FIRESTORE_INDEXES_SOURCE_INVALID",
    );
  }
  return { indexes, fieldOverrides };
}

export async function catalogPolicySourceContract(lane) {
  const sourcePath = catalogPolicySourcePath(lane);
  const source = await readFile(sourcePath);
  const sourceSha256 = sha256(source);
  if (lane === "firestore-rules") {
    const text = source.toString("utf8");
    const requiredCollections = [
      "whatsappCatalogMappings",
      "whatsappCatalogOutbox",
      "whatsappCatalogSyncState",
      "whatsappCatalogReconciliationRuns",
      "whatsappProductListDeliveries",
      "whatsappProductListRecipientState",
      "whatsappCatalogCartReplacements",
      "whatsappCatalogCartStates",
    ];
    if (
      requiredCollections.some(
        (collection) =>
          !new RegExp(
            `match\\s+/${collection}/\\{document=\\*\\*\\}\\s*\\{\\s*allow\\s+read,\\s*write:\\s*if\\s+false;\\s*\\}`,
          ).test(text),
      )
    ) {
      throw new CatalogDeploymentGuardError(
        "CATALOG_FIRESTORE_RULES_CONTRACT_INVALID",
      );
    }
    return {
      lane,
      selector: "firestore:rules",
      sourcePath: "firestore.rules",
      sourceSha256,
    };
  }
  let parsed;
  try {
    parsed = JSON.parse(source.toString("utf8"));
  } catch (_) {
    throw new CatalogDeploymentGuardError(
      "CATALOG_FIRESTORE_INDEXES_SOURCE_INVALID",
    );
  }
  const canonicalConfiguration = canonicalFirestoreIndexConfiguration(parsed);
  const ttlFields = (
    Array.isArray(parsed?.fieldOverrides) ? parsed.fieldOverrides : []
  )
    .filter((entry) => entry?.ttl === true)
    .map(requiredTtlEntry)
    .sort();
  if (
    JSON.stringify(ttlFields) !==
    JSON.stringify([...REQUIRED_CATALOG_TTL_FIELDS].sort())
  ) {
    throw new CatalogDeploymentGuardError(
      "CATALOG_FIRESTORE_TTL_SOURCE_INVALID",
    );
  }
  return {
    lane,
    selector: "firestore:indexes",
    sourcePath: "firestore.indexes.json",
    sourceSha256,
    databaseId: PRODUCTION_FIRESTORE_DATABASE_ID,
    indexCount: canonicalConfiguration.indexes.length,
    fieldOverrideCount: canonicalConfiguration.fieldOverrides.length,
    fullIndexConfigurationDigestSha256: sha256(
      JSON.stringify(canonicalConfiguration),
    ),
    ttlFieldCount: ttlFields.length,
    ttlContractDigestSha256: sha256(ttlFields.join("\n")),
  };
}

async function execReadback(command, args, execFileImpl = execFile) {
  try {
    const result = await execFileImpl(command, args, {
      cwd: APP_REPOSITORY_ROOT,
      encoding: "utf8",
      maxBuffer: MAX_READBACK_BYTES,
      env: scrubCredentialEnvironment(),
    });
    return String(result.stdout ?? "");
  } catch (_) {
    throw new CatalogDeploymentGuardError("CATALOG_POLICY_READBACK_FAILED");
  }
}

async function listedCatalogFunctionEndpoints(lane, execFileImpl = execFile) {
  const functionNames = catalogFunctionSelector(lane)
    .split(",")
    .map((selector) => selector.replace(/^functions:/, ""))
    .sort();
  let parsed;
  try {
    parsed = JSON.parse(
      await execReadback(
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
        execFileImpl,
      ),
    );
  } catch (_) {
    throw new CatalogDeploymentGuardError("CATALOG_FUNCTION_READBACK_FAILED");
  }
  const endpoints = Array.isArray(parsed)
    ? parsed
    : Array.isArray(parsed?.result)
      ? parsed.result
      : null;
  if (!endpoints) {
    throw new CatalogDeploymentGuardError("CATALOG_FUNCTION_READBACK_FAILED");
  }
  const selected = endpoints.filter((endpoint) =>
    functionNames.includes(String(endpoint?.id ?? "")),
  );
  if (
    selected.length !== functionNames.length ||
    new Set(selected.map((endpoint) => String(endpoint?.id ?? ""))).size !==
      functionNames.length ||
    selected.some(
      (endpoint) =>
        String(endpoint?.region ?? "") !== PRODUCTION_FIREBASE_FUNCTION_REGION,
    )
  ) {
    throw new CatalogDeploymentGuardError(
      "CATALOG_FUNCTION_READBACK_SELECTOR_MISMATCH",
    );
  }
  return { functionNames, selected };
}

/** Internal only: raw environment values must never be copied into a receipt. */
async function collectCatalogFunctionHashInputs(
  { lane },
  { execFileImpl = execFile } = {},
) {
  const { selected } = await listedCatalogFunctionEndpoints(lane, execFileImpl);
  return Object.fromEntries(
    selected.map((endpoint) => [
      String(endpoint.id),
      {
        environmentVariables: { ...(endpoint.environmentVariables ?? {}) },
      },
    ]),
  );
}

const PLATFORM_MANAGED_FUNCTION_ENVIRONMENT_KEYS = new Set([
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

function canonicalFunctionEnvironment(endpoint) {
  const rawEnvironment = endpoint?.environmentVariables;
  const environment =
    rawEnvironment &&
    typeof rawEnvironment === "object" &&
    !Array.isArray(rawEnvironment)
      ? rawEnvironment
      : {};
  const userEntries = Object.entries(environment).filter(
    ([key]) => !PLATFORM_MANAGED_FUNCTION_ENVIRONMENT_KEYS.has(key),
  );
  const entries = userEntries
    .map(([key, value]) => [key, typeof value === "string" ? value : null])
    .sort(([left], [right]) => left.localeCompare(right));
  const rawSecretEnvironment = endpoint?.secretEnvironmentVariables;
  const secretEnvironment = Array.isArray(rawSecretEnvironment)
    ? rawSecretEnvironment
        .map((entry) => ({
          key: String(entry?.key ?? ""),
          projectId: String(entry?.projectId ?? ""),
          secret: String(entry?.secret ?? ""),
          version: String(entry?.version ?? ""),
        }))
        .sort((left, right) => left.key.localeCompare(right.key))
    : [];
  return {
    entries,
    secretEnvironment,
    shapeValid:
      (rawEnvironment === undefined ||
        (typeof rawEnvironment === "object" &&
          rawEnvironment !== null &&
          !Array.isArray(rawEnvironment))) &&
      userEntries.every(([, value]) => typeof value === "string") &&
      (rawSecretEnvironment === undefined ||
        Array.isArray(rawSecretEnvironment)),
  };
}

function expectedConfiguredEnvironmentDigest(functionNames, validated) {
  const expected = [...parseStrictDotenv(validated.normalized).entries()].sort(
    ([left], [right]) => left.localeCompare(right),
  );
  return sha256(
    JSON.stringify(
      [...functionNames].sort().map((functionName) => [
        functionName,
        {
          entries: expected,
          secretKeys: [
            ...(NATIVE_CATALOG_FUNCTION_SECRET_REFS[functionName] ?? []),
          ].sort(),
        },
      ]),
    ),
  );
}

function expectedSecretReferenceMatches(entry, expectedKey) {
  const secret = String(entry?.secret ?? "");
  const projectId = String(entry?.projectId ?? "");
  return (
    String(entry?.key ?? "") === expectedKey &&
    (secret === expectedKey ||
      secret ===
        `projects/${PRODUCTION_FIREBASE_PROJECT_ID}/secrets/${expectedKey}`) &&
    (!projectId || projectId === PRODUCTION_FIREBASE_PROJECT_ID) &&
    String(entry?.version ?? "").length > 0
  );
}

function safeBuildSourceIdentity(endpoint) {
  const source = endpoint?.source;
  if (!source || typeof source !== "object" || Array.isArray(source)) {
    return null;
  }
  const storage = source.storageSource;
  if (
    storage &&
    typeof storage === "object" &&
    !Array.isArray(storage) &&
    typeof storage.bucket === "string" &&
    storage.bucket &&
    typeof storage.object === "string" &&
    storage.object &&
    String(storage.generation ?? "")
  ) {
    return {
      type: "storage",
      bucket: storage.bucket,
      object: storage.object,
      generation: String(storage.generation),
    };
  }
  const repository = source.repoSource ?? source.repositorySource;
  if (
    repository &&
    typeof repository === "object" &&
    !Array.isArray(repository)
  ) {
    const repositoryName = String(
      repository.repoName ?? repository.repository ?? "",
    );
    const revision = String(
      repository.commitSha ?? repository.revision ?? repository.tagName ?? "",
    );
    if (repositoryName && revision) {
      return { type: "repository", repositoryName, revision };
    }
  }
  return null;
}

/**
 * Hashes only firebase-tools' normalized functions:list endpoint identity.
 * Gen 1's signed sourceUploadUrl is deliberately ignored; Gen 2 must expose a
 * safe immutable storage/repository source identity. The provider's
 * firebase-functions-hash is SHA-1, but this function and the aggregate
 * receipt expose only SHA-256 digests.
 */
export function canonicalFunctionBuildIdentityDigest(endpoint) {
  const id = String(endpoint?.id ?? "");
  const region = String(endpoint?.region ?? "");
  const platform = String(endpoint?.platform ?? "");
  const runtime = String(endpoint?.runtime ?? "");
  const entryPoint = String(endpoint?.entryPoint ?? "");
  const codebase = String(endpoint?.codebase ?? "");
  const providerHashSha1 = String(endpoint?.hash ?? "");
  if (
    !/^[A-Za-z][A-Za-z0-9_-]{0,127}$/.test(id) ||
    region !== PRODUCTION_FIREBASE_FUNCTION_REGION ||
    runtime !== "nodejs20" ||
    entryPoint !== id ||
    codebase !== "default" ||
    !/^[a-f0-9]{40}$/.test(providerHashSha1) ||
    (platform !== "gcfv1" && platform !== "gcfv2")
  ) {
    return null;
  }
  const identity = {
    platform,
    id,
    region,
    runtime,
    entryPoint,
    codebase,
    providerHashSha1,
  };
  if (platform === "gcfv2") {
    const source = safeBuildSourceIdentity(endpoint);
    if (!source) return null;
    return sha256(JSON.stringify({ ...identity, source }));
  }
  return sha256(JSON.stringify(identity));
}

export async function collectCatalogFunctionReadback(
  {
    lane,
    validated,
    expectedPreservationDigestSha256,
    candidateSourceContract,
    existingEnvironmentBaselines,
  },
  { execFileImpl = execFile } = {},
) {
  const { functionNames, selected } = await listedCatalogFunctionEndpoints(
    lane,
    execFileImpl,
  );

  const configuredOnly = lane !== "existing-code";
  let secretReferencesMatch = true;
  let environmentShapesValid = true;
  let buildIdentitiesComplete = true;
  const buildIdentities = selected
    .map((endpoint) => {
      const digest = canonicalFunctionBuildIdentityDigest(endpoint);
      if (!digest) buildIdentitiesComplete = false;
      return [String(endpoint?.id ?? ""), digest];
    })
    .sort(([left], [right]) => left.localeCompare(right));
  const buildIdentitySetSha256 = buildIdentitiesComplete
    ? sha256(JSON.stringify(buildIdentities))
    : null;
  const environmentDigestSha256 = sha256(
    JSON.stringify(
      selected
        .map((endpoint) => {
          const functionName = String(endpoint.id);
          const environment = canonicalFunctionEnvironment(endpoint);
          if (!environment.shapeValid) environmentShapesValid = false;
          if (!configuredOnly) {
            return [
              functionName,
              {
                entries: environment.entries,
                secretEnvironment: environment.secretEnvironment,
              },
            ];
          }
          const expectedSecretKeys = [
            ...(NATIVE_CATALOG_FUNCTION_SECRET_REFS[functionName] ?? []),
          ].sort();
          const secretKeys = environment.secretEnvironment
            .map((entry) => entry.key)
            .sort();
          if (
            JSON.stringify(secretKeys) !== JSON.stringify(expectedSecretKeys) ||
            environment.secretEnvironment.some(
              (entry, index) =>
                !expectedSecretReferenceMatches(
                  entry,
                  expectedSecretKeys[index],
                ),
            )
          ) {
            secretReferencesMatch = false;
          }
          return [functionName, { entries: environment.entries, secretKeys }];
        })
        .sort(([left], [right]) => String(left).localeCompare(String(right))),
    ),
  );
  const expectedDigestSha256 = configuredOnly
    ? expectedConfiguredEnvironmentDigest(functionNames, validated)
    : expectedPreservationDigestSha256;
  let candidateSourceBinding;
  try {
    candidateSourceBinding = verifyCandidateFirebaseFunctionHashes({
      endpoints: selected,
      expectedFunctionNames: functionNames,
      expectedSecretReferences: configuredOnly
        ? NATIVE_CATALOG_FUNCTION_SECRET_REFS
        : NATIVE_CATALOG_EXISTING_FUNCTION_SECRET_REFS,
      sourceContract: candidateSourceContract,
      projectId: PRODUCTION_FIREBASE_PROJECT_ID,
      region: PRODUCTION_FIREBASE_FUNCTION_REGION,
      codebase: "default",
      configuredEnvironmentEntries: configuredOnly
        ? [...parseStrictDotenv(validated.normalized).entries()]
        : undefined,
      existingEnvironmentBaselines: configuredOnly
        ? undefined
        : existingEnvironmentBaselines,
    });
  } catch (_) {
    candidateSourceBinding = {
      candidateSourceBindingMatches: false,
      candidateSourceContractSha256: null,
      candidateSourceFileCount: null,
      candidateGeneratedFileCount: null,
      candidateProviderBindingSetSha256: null,
    };
  }
  return {
    selector: catalogFunctionSelector(lane),
    functionCount: functionNames.length,
    region: PRODUCTION_FIREBASE_FUNCTION_REGION,
    environmentDigestSha256,
    expectedEnvironmentDigestSha256: expectedDigestSha256,
    environmentMatches:
      typeof expectedDigestSha256 === "string" &&
      /^[a-f0-9]{64}$/.test(expectedDigestSha256) &&
      environmentDigestSha256 === expectedDigestSha256 &&
      environmentShapesValid &&
      secretReferencesMatch &&
      buildIdentitiesComplete &&
      candidateSourceBinding.candidateSourceBindingMatches,
    environmentShapesValid,
    secretReferencesMatch,
    buildIdentitiesComplete,
    buildIdentitySetSha256,
    ...candidateSourceBinding,
  };
}

function exactTtlReadback(value) {
  if (!Array.isArray(value)) return null;
  const rows = value
    .map((entry) => ({
      name: String(entry?.name ?? ""),
      state: String(entry?.ttlConfig?.state ?? entry?.state ?? ""),
    }))
    .filter((entry) =>
      entry.name.startsWith(
        `projects/${PRODUCTION_FIREBASE_PROJECT_ID}/databases/${PRODUCTION_FIRESTORE_DATABASE_ID}/collectionGroups/`,
      ),
    );
  const expected = REQUIRED_CATALOG_TTL_FIELDS.map((field) => {
    const [collectionGroup, fieldPath] = field.split("/");
    return {
      name: `projects/${PRODUCTION_FIREBASE_PROJECT_ID}/databases/${PRODUCTION_FIRESTORE_DATABASE_ID}/collectionGroups/${collectionGroup}/fields/${fieldPath}`,
      state: "ACTIVE",
    };
  }).sort((a, b) => a.name.localeCompare(b.name));
  const actual = rows.sort((a, b) => a.name.localeCompare(b.name));
  return JSON.stringify(actual) === JSON.stringify(expected) ? actual : null;
}

async function firebaseRulesReadback({
  execFileImpl = execFile,
  fetchImpl = global.fetch,
} = {}) {
  if (typeof fetchImpl !== "function") {
    throw new CatalogDeploymentGuardError("CATALOG_POLICY_READBACK_FAILED");
  }
  const rawToken = Buffer.from(
    await execReadback(
      PINNED_GCLOUD_CLI.executablePath,
      ["auth", "print-access-token", "--account", PRODUCTION_FIREBASE_ACCOUNT],
      execFileImpl,
    ),
    "utf8",
  );
  let token = rawToken.toString("utf8").trim();
  rawToken.fill(0);
  if (token.length < 16 || token.length > 16 * 1024) {
    token = "";
    throw new CatalogDeploymentGuardError("CATALOG_POLICY_READBACK_FAILED");
  }
  const readJson = async (url) => {
    let response;
    try {
      response = await fetchImpl(url, {
        method: "GET",
        redirect: "error",
        headers: { authorization: `Bearer ${token}` },
      });
    } catch (_) {
      throw new CatalogDeploymentGuardError("CATALOG_POLICY_READBACK_FAILED");
    }
    if (!response.ok) {
      throw new CatalogDeploymentGuardError("CATALOG_POLICY_READBACK_FAILED");
    }
    const text = await response.text();
    if (Buffer.byteLength(text) > MAX_READBACK_BYTES) {
      throw new CatalogDeploymentGuardError("CATALOG_POLICY_READBACK_FAILED");
    }
    try {
      return JSON.parse(text);
    } catch (_) {
      throw new CatalogDeploymentGuardError("CATALOG_POLICY_READBACK_FAILED");
    }
  };
  try {
    let pageToken = "";
    let release;
    do {
      const query = new URLSearchParams({ pageSize: "100" });
      if (pageToken) query.set("pageToken", pageToken);
      const payload = await readJson(
        `https://firebaserules.googleapis.com/v1/projects/${PRODUCTION_FIREBASE_PROJECT_ID}/releases?${query}`,
      );
      release = (payload.releases ?? []).find(
        (entry) =>
          entry?.name ===
          `projects/${PRODUCTION_FIREBASE_PROJECT_ID}/releases/cloud.firestore`,
      );
      pageToken = String(payload.nextPageToken ?? "");
    } while (!release && pageToken);
    const rulesetName = String(release?.rulesetName ?? "");
    if (
      !new RegExp(
        `^projects/${PRODUCTION_FIREBASE_PROJECT_ID}/rulesets/[A-Za-z0-9_-]+$`,
      ).test(rulesetName)
    ) {
      throw new CatalogDeploymentGuardError("CATALOG_POLICY_READBACK_FAILED");
    }
    const ruleset = await readJson(
      `https://firebaserules.googleapis.com/v1/${rulesetName}`,
    );
    const files = Array.isArray(ruleset?.source?.files)
      ? ruleset.source.files
      : [];
    const firestoreRules = files.find(
      (file) => String(file?.name ?? "") === "firestore.rules",
    );
    if (typeof firestoreRules?.content !== "string") {
      throw new CatalogDeploymentGuardError("CATALOG_POLICY_READBACK_FAILED");
    }
    return {
      activeRulesetName: rulesetName,
      activeSourceSha256: sha256(firestoreRules.content),
    };
  } finally {
    token = "";
  }
}

export async function collectCatalogPolicyReadback(
  lane,
  {
    execFileImpl = execFile,
    fetchImpl = global.fetch,
    rulesReadback = firebaseRulesReadback,
  } = {},
) {
  if (lane === "firestore-rules") {
    return rulesReadback({ execFileImpl, fetchImpl });
  }
  if (lane !== "firestore-indexes") {
    throw new CatalogDeploymentGuardError("CATALOG_POLICY_LANE_INVALID");
  }
  let remoteIndexes;
  let ttlRows;
  try {
    remoteIndexes = JSON.parse(
      await execReadback(
        PINNED_FIREBASE_CLI.executablePath,
        [
          "--project",
          PRODUCTION_FIREBASE_PROJECT_ID,
          "--account",
          PRODUCTION_FIREBASE_ACCOUNT,
          "--non-interactive",
          "firestore:indexes",
          "--database",
          PRODUCTION_FIRESTORE_DATABASE_ID,
        ],
        execFileImpl,
      ),
    );
    ttlRows = JSON.parse(
      await execReadback(
        PINNED_GCLOUD_CLI.executablePath,
        [
          "firestore",
          "fields",
          "ttls",
          "list",
          "--project",
          PRODUCTION_FIREBASE_PROJECT_ID,
          `--database=${PRODUCTION_FIRESTORE_DATABASE_ID}`,
          "--account",
          PRODUCTION_FIREBASE_ACCOUNT,
          "--limit=unlimited",
          "--format=json(name,ttlConfig.state)",
        ],
        execFileImpl,
      ),
    );
  } catch (_) {
    throw new CatalogDeploymentGuardError("CATALOG_POLICY_READBACK_FAILED");
  }
  const canonicalRemote = canonicalFirestoreIndexConfiguration(remoteIndexes);
  const remoteTtlFields = canonicalRemote.fieldOverrides
    .filter((entry) => entry?.ttl === true)
    .map(requiredTtlEntry)
    .sort();
  const active = exactTtlReadback(ttlRows);
  return {
    databaseId: PRODUCTION_FIRESTORE_DATABASE_ID,
    remoteIndexCount: canonicalRemote.indexes.length,
    remoteFieldOverrideCount: canonicalRemote.fieldOverrides.length,
    remoteFullIndexConfigurationDigestSha256: sha256(
      JSON.stringify(canonicalRemote),
    ),
    remoteTtlFieldCount: remoteTtlFields.length,
    remoteTtlContractDigestSha256: sha256(remoteTtlFields.join("\n")),
    ttlActive: Boolean(active),
    ttlActiveCount: active?.length ?? 0,
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

// Module-private by design. The CLI execute gate is disabled, so importing
// this file must never expose a second path to its write-capable transport.
async function runGuardedCatalogPolicyDeployment({
  lane,
  expectedAppCommit,
  expectedCurrentMainCommit,
  candidateManifestPath,
  expectedCandidateManifestSha256,
  dryRun = true,
  readbackOnly = false,
  spawnImpl = nodeSpawn,
  resolveCommit = resolveAuthorityAppCommit,
  collectReadback = collectCatalogPolicyReadback,
  verifyToolchain = assertPinnedProductionToolchain,
  verifyCandidateManifest = loadAndValidateProductionCandidateManifest,
  temporaryRoot = os.tmpdir(),
  removeTemporaryDirectory = rm,
} = {}) {
  if (!CATALOG_POLICY_LANES.includes(lane)) {
    throw new CatalogDeploymentGuardError("CATALOG_POLICY_LANE_INVALID");
  }
  if (!/^[a-f0-9]{40}$/.test(String(expectedAppCommit ?? ""))) {
    throw new CatalogDeploymentGuardError("EXPECTED_APP_COMMIT_INVALID");
  }
  if (expectedCurrentMainCommit !== FROZEN_APP_MAIN_COMMIT) {
    throw new CatalogDeploymentGuardError(
      "EXPECTED_CURRENT_MAIN_COMMIT_INVALID",
    );
  }
  if (
    !dryRun &&
    (typeof candidateManifestPath !== "string" ||
      !path.isAbsolute(candidateManifestPath) ||
      path.resolve(candidateManifestPath) !== candidateManifestPath ||
      !/^[a-f0-9]{64}$/.test(String(expectedCandidateManifestSha256 ?? "")))
  ) {
    throw new CatalogDeploymentGuardError(
      "PRODUCTION_CANDIDATE_MANIFEST_REFERENCE_INVALID",
    );
  }
  await verifyToolchain();
  const source = await catalogPolicySourceContract(lane);
  const resolveExactCommit = async () => {
    const resolvedCommit = await resolveCommit({
      expectedCandidateCommit: expectedAppCommit,
      expectedCurrentMainCommit,
    });
    if (!dryRun) {
      try {
        await verifyCandidateManifest({
          manifestPath: candidateManifestPath,
          expectedManifestSha256: expectedCandidateManifestSha256,
          expectedAppCommit,
          expectedCurrentMainCommit,
          expectedOperation: {
            kind: "policy_deployment",
            lane,
            selector:
              lane === "firestore-rules"
                ? "firestore:rules"
                : "firestore:indexes",
            inputSha256: source.sourceSha256,
          },
        });
      } catch (_) {
        throw new CatalogDeploymentGuardError(
          "PRODUCTION_CANDIDATE_MANIFEST_INVALID",
        );
      }
    }
    return resolvedCommit;
  };
  const appCommit = await resolveExactCommit();
  if (appCommit !== expectedAppCommit) {
    throw new CatalogDeploymentGuardError("EXPECTED_APP_COMMIT_MISMATCH");
  }
  if (readbackOnly) {
    const readback = await collectReadback(lane);
    if (!policyReadbackMatches(lane, source, readback)) {
      throw new CatalogDeploymentGuardError("CATALOG_POLICY_READBACK_MISMATCH");
    }
    return {
      schemaVersion: 1,
      outcome: "readback_verified",
      lane,
      dryRun: false,
      readbackOnly: true,
      firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
      databaseId: PRODUCTION_FIRESTORE_DATABASE_ID,
      appCommit,
      ...source,
      readback,
      readbackStatus: "verified",
      closedPolicyReceipt: true,
      receiptStatus: "verified",
      retryAllowed: false,
    };
  }
  const temporaryDirectory = await mkdtemp(
    path.join(temporaryRoot, "spazaone-catalog-policy-deploy-"),
  );
  const configPath = path.join(temporaryDirectory, "firebase.json");
  let operationError;
  try {
    await chmod(temporaryDirectory, 0o700);
    await writeFile(
      configPath,
      `${JSON.stringify(buildEphemeralFirebasePolicyConfig(), null, 2)}\n`,
      { encoding: "utf8", flag: "wx", mode: 0o600 },
    );
    if (!dryRun && (await resolveExactCommit()) !== expectedAppCommit) {
      throw new CatalogDeploymentGuardError("EXPECTED_APP_COMMIT_MISMATCH");
    }
    await spawnAndWait(
      CODEX_GUARD,
      codexGuardDeployArguments({ lane, dryRun, configPath }),
      {
        cwd: APP_REPOSITORY_ROOT,
        env: scrubCredentialEnvironment(),
        stdio: "inherit",
      },
      { spawnImpl, writeCapable: !dryRun },
    );
  } catch (error) {
    operationError =
      error instanceof CatalogDeploymentGuardError
        ? error
        : new CatalogDeploymentGuardError("CATALOG_DEPLOY_PREPARATION_FAILED");
  }
  let cleanupStatus = "deleted";
  let cleanupDirectory;
  let cleanupAction;
  try {
    await removeTemporaryDirectory(temporaryDirectory, {
      recursive: true,
      force: true,
    });
  } catch (_) {
    cleanupStatus = "needs_review";
    cleanupDirectory = temporaryDirectory;
    cleanupAction = "remove_exact_ephemeral_directory_after_review";
  }
  if (operationError) {
    operationError.cleanupStatus = cleanupStatus;
    if (cleanupDirectory) {
      operationError.cleanupDirectory = cleanupDirectory;
      operationError.cleanupAction = cleanupAction;
    }
    throw operationError;
  }
  const base = {
    schemaVersion: 1,
    outcome: dryRun ? "dry_run_complete" : "deploy_command_completed",
    lane,
    dryRun,
    readbackOnly: false,
    commandExitZero: true,
    firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
    databaseId: PRODUCTION_FIRESTORE_DATABASE_ID,
    appCommit,
    ...source,
    configurationSha256: nativeCatalogTargetConfigurationDigestSha256(),
    cleanupStatus,
    ...(cleanupDirectory ? { cleanupDirectory, cleanupAction } : {}),
    retryAllowed: false,
  };
  if (dryRun) {
    return {
      ...base,
      readbackStatus: "not_performed",
      closedPolicyReceipt: false,
    };
  }
  try {
    const readback = await collectReadback(lane);
    const verified =
      policyReadbackMatches(lane, source, readback) &&
      cleanupStatus === "deleted";
    return {
      ...base,
      readback,
      readbackStatus: verified ? "verified" : "needs_review",
      closedPolicyReceipt: verified,
      receiptStatus: verified ? "verified" : "needs_review",
      readbackRetryAllowed: false,
    };
  } catch (_) {
    return {
      ...base,
      readbackStatus: "needs_review",
      readbackCode: "CATALOG_POLICY_READBACK_FAILED",
      closedPolicyReceipt: false,
      receiptStatus: "needs_review",
      readbackRetryAllowed: false,
    };
  }
}

/**
 * Uses an out-of-source configDir so the validated dotenv is neither checked
 * in nor uploaded in the Cloud Functions source archive.
 */
// Module-private by design. A future reviewed enablement must close dispatch,
// real readback attestation, and receipt persistence in one internal operation
// before the CLI execute gate changes.
async function runGuardedCatalogDeployment({
  lane,
  expectedAppCommit,
  expectedCurrentMainCommit,
  candidateManifestPath,
  expectedCandidateManifestSha256,
  dotenvText = "",
  dryRun = true,
  spawnImpl = nodeSpawn,
  resolveCommit = resolveAuthorityAppCommit,
  functionsDirectory = FUNCTIONS_DIRECTORY,
  temporaryRoot = os.tmpdir(),
  removeTemporaryDirectory = rm,
  collectFunctionReadback = collectCatalogFunctionReadback,
  collectFunctionHashInputs = collectCatalogFunctionHashInputs,
  collectRuntimeConfigHash = collectFirebaseGen1RuntimeConfigHashSha1,
  computeCandidateSourceContract = computeCandidateFirebaseSourceContract,
  verifyToolchain = assertPinnedProductionToolchain,
  verifyCandidateManifest = loadAndValidateProductionCandidateManifest,
} = {}) {
  if (!/^[a-f0-9]{40}$/.test(String(expectedAppCommit ?? ""))) {
    throw new CatalogDeploymentGuardError("EXPECTED_APP_COMMIT_INVALID");
  }
  if (expectedCurrentMainCommit !== FROZEN_APP_MAIN_COMMIT) {
    throw new CatalogDeploymentGuardError(
      "EXPECTED_CURRENT_MAIN_COMMIT_INVALID",
    );
  }
  if (
    !dryRun &&
    (typeof candidateManifestPath !== "string" ||
      !path.isAbsolute(candidateManifestPath) ||
      path.resolve(candidateManifestPath) !== candidateManifestPath ||
      !/^[a-f0-9]{64}$/.test(String(expectedCandidateManifestSha256 ?? "")))
  ) {
    throw new CatalogDeploymentGuardError(
      "PRODUCTION_CANDIDATE_MANIFEST_REFERENCE_INVALID",
    );
  }
  await assertNoSourceDeploymentDotenv(functionsDirectory);
  await verifyToolchain();
  let validated = null;
  let operationInputSha256;
  if (lane === "existing-code") {
    if (dotenvText.trim()) {
      throw new CatalogDeploymentGuardError(
        "EXISTING_FUNCTION_DOTENV_FORBIDDEN",
      );
    }
    operationInputSha256 = sha256(JSON.stringify({ dotenvSha256: null }));
  } else {
    validated = validateCatalogDeploymentDotenv({
      lane,
      text: dotenvText,
      appCommit: expectedAppCommit,
    });
    operationInputSha256 = validated.sha256;
  }
  const resolveExactCommit = async () => {
    const resolvedCommit = await resolveCommit({
      expectedCandidateCommit: expectedAppCommit,
      expectedCurrentMainCommit,
    });
    if (!dryRun) {
      try {
        await verifyCandidateManifest({
          manifestPath: candidateManifestPath,
          expectedManifestSha256: expectedCandidateManifestSha256,
          expectedAppCommit,
          expectedCurrentMainCommit,
          expectedOperation: {
            kind: "function_deployment",
            lane,
            selector: catalogFunctionSelector(lane),
            inputSha256: operationInputSha256,
          },
        });
      } catch (_) {
        throw new CatalogDeploymentGuardError(
          "PRODUCTION_CANDIDATE_MANIFEST_INVALID",
        );
      }
    }
    return resolvedCommit;
  };
  const appCommit = await resolveExactCommit();
  if (appCommit !== expectedAppCommit) {
    throw new CatalogDeploymentGuardError("EXPECTED_APP_COMMIT_MISMATCH");
  }
  let candidateSourceContract = null;
  const refreshCandidateSourceContract = async () => {
    try {
      const runtimeConfigHashSha1 = await collectRuntimeConfigHash({
        firebaseCliPath: PINNED_FIREBASE_CLI.executablePath,
        projectId: PRODUCTION_FIREBASE_PROJECT_ID,
        account: PRODUCTION_FIREBASE_ACCOUNT,
        anchorFunctionId: NATIVE_CATALOG_EXISTING_FUNCTIONS[0],
        environment: scrubCredentialEnvironment(),
      });
      return await computeCandidateSourceContract({
        repositoryRoot: APP_REPOSITORY_ROOT,
        functionsDirectory,
        expectedAppCommit,
        runtimeConfigHashSha1,
        environment: scrubCredentialEnvironment(),
      });
    } catch (_) {
      throw new CatalogDeploymentGuardError(
        "CANDIDATE_FUNCTION_SOURCE_BINDING_FAILED",
      );
    }
  };
  if (!dryRun) candidateSourceContract = await refreshCandidateSourceContract();
  if (lane === "existing-code") {
    await assertPinnedFirebaseCliEnvironmentPreservation();
    const existingEnvironmentBaselines = dryRun
      ? null
      : await collectFunctionHashInputs({ lane });
    const before = dryRun
      ? null
      : await collectFunctionReadback({ lane, validated: null });
    if (
      before &&
      (!/^[a-f0-9]{64}$/.test(String(before.environmentDigestSha256 ?? "")) ||
        before.environmentShapesValid !== true)
    ) {
      throw new CatalogDeploymentGuardError("CATALOG_FUNCTION_READBACK_FAILED");
    }
    const temporaryDirectory = await mkdtemp(
      path.join(temporaryRoot, "spazaone-catalog-code-deploy-"),
    );
    const configPath = path.join(temporaryDirectory, "firebase.json");
    let operationError;
    try {
      await chmod(temporaryDirectory, 0o700);
      await writeFile(
        configPath,
        `${JSON.stringify(
          buildEphemeralFirebaseConfig({ functionsDirectory }),
          null,
          2,
        )}\n`,
        { encoding: "utf8", flag: "wx", mode: 0o600 },
      );
      if (!dryRun && (await resolveExactCommit()) !== expectedAppCommit) {
        throw new CatalogDeploymentGuardError("EXPECTED_APP_COMMIT_MISMATCH");
      }
      await spawnAndWait(
        CODEX_GUARD,
        codexGuardDeployArguments({ lane, dryRun, configPath }),
        {
          cwd: APP_REPOSITORY_ROOT,
          env: scrubCredentialEnvironment(),
          stdio: "inherit",
        },
        { spawnImpl, writeCapable: !dryRun },
      );
    } catch (error) {
      operationError =
        error instanceof CatalogDeploymentGuardError
          ? error
          : new CatalogDeploymentGuardError(
              "CATALOG_DEPLOY_PREPARATION_FAILED",
            );
    }
    let cleanupStatus = "deleted";
    let cleanupDirectory;
    let cleanupAction;
    try {
      await removeTemporaryDirectory(temporaryDirectory, {
        recursive: true,
        force: true,
      });
    } catch (_) {
      cleanupStatus = "needs_review";
      cleanupDirectory = temporaryDirectory;
      cleanupAction = "remove_exact_ephemeral_directory_after_review";
    }
    if (operationError) {
      operationError.cleanupStatus = cleanupStatus;
      if (cleanupDirectory) {
        operationError.cleanupDirectory = cleanupDirectory;
        operationError.cleanupAction = cleanupAction;
      }
      throw operationError;
    }
    const base = {
      schemaVersion: 1,
      outcome: dryRun ? "dry_run_complete" : "deploy_command_completed",
      lane,
      dryRun,
      commandExitZero: true,
      firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
      appCommit,
      targetConfigurationDigestSha256:
        nativeCatalogTargetConfigurationDigestSha256(),
      dotenvApplied: false,
      existingFunctionEnvironmentPolicy:
        "preserved_by_pinned_cli_remote_merge_without_overlay",
      cleanupStatus,
      ...(cleanupDirectory ? { cleanupDirectory, cleanupAction } : {}),
      selector: catalogFunctionSelector(lane),
      retryAllowed: false,
    };
    if (dryRun) {
      return {
        ...base,
        readbackStatus: "not_performed",
        closedDeploymentReceipt: false,
      };
    }
    try {
      const postDeploySourceContract = await refreshCandidateSourceContract();
      if (
        postDeploySourceContract.contractSha256 !==
        candidateSourceContract.contractSha256
      ) {
        throw new CatalogDeploymentGuardError(
          "CANDIDATE_FUNCTION_SOURCE_CHANGED_DURING_DEPLOY",
        );
      }
      const readback = await collectFunctionReadback({
        lane,
        validated: null,
        expectedPreservationDigestSha256: before.environmentDigestSha256,
        candidateSourceContract: postDeploySourceContract,
        existingEnvironmentBaselines,
      });
      return {
        ...base,
        preDeployEnvironmentDigestSha256: before.environmentDigestSha256,
        readback,
        readbackStatus: readback.environmentMatches
          ? "verified"
          : "needs_review",
        closedDeploymentReceipt:
          readback.environmentMatches && cleanupStatus === "deleted",
        receiptStatus:
          readback.environmentMatches && cleanupStatus === "deleted"
            ? "verified"
            : "needs_review",
      };
    } catch (_) {
      return {
        ...base,
        preDeployEnvironmentDigestSha256: before.environmentDigestSha256,
        readbackStatus: "needs_review",
        readbackCode: "CATALOG_FUNCTION_READBACK_FAILED",
        closedDeploymentReceipt: false,
        receiptStatus: "needs_review",
      };
    }
  }

  const temporaryDirectory = await mkdtemp(
    path.join(temporaryRoot, "spazaone-catalog-deploy-"),
  );
  let operationError;
  let commandExitZero = false;
  try {
    await chmod(temporaryDirectory, 0o700);
    const dotenvPath = path.join(
      temporaryDirectory,
      `.env.${PRODUCTION_FIREBASE_PROJECT_ID}`,
    );
    const configPath = path.join(temporaryDirectory, "firebase.json");
    await writeFile(dotenvPath, validated.normalized, {
      encoding: "utf8",
      flag: "wx",
      mode: 0o600,
    });
    await writeFile(
      configPath,
      `${JSON.stringify(
        buildEphemeralFirebaseConfig({
          functionsDirectory,
          configDir: temporaryDirectory,
        }),
        null,
        2,
      )}\n`,
      { encoding: "utf8", flag: "wx", mode: 0o600 },
    );
    if (!dryRun && (await resolveExactCommit()) !== expectedAppCommit) {
      throw new CatalogDeploymentGuardError("EXPECTED_APP_COMMIT_MISMATCH");
    }
    await spawnAndWait(
      CODEX_GUARD,
      codexGuardDeployArguments({ lane, dryRun, configPath }),
      {
        cwd: APP_REPOSITORY_ROOT,
        env: scrubCredentialEnvironment(),
        stdio: "inherit",
      },
      { spawnImpl, writeCapable: !dryRun },
    );
    commandExitZero = true;
  } catch (error) {
    operationError =
      error instanceof CatalogDeploymentGuardError
        ? error
        : new CatalogDeploymentGuardError("CATALOG_DEPLOY_PREPARATION_FAILED");
  }

  let cleanupStatus = "deleted";
  let cleanupDirectory;
  let cleanupAction;
  try {
    await removeTemporaryDirectory(temporaryDirectory, {
      recursive: true,
      force: true,
    });
  } catch (_) {
    cleanupStatus = "needs_review";
    cleanupDirectory = temporaryDirectory;
    cleanupAction = "remove_exact_ephemeral_directory_after_review";
  }

  if (operationError) {
    operationError.cleanupStatus = cleanupStatus;
    if (cleanupDirectory) {
      operationError.cleanupDirectory = cleanupDirectory;
      operationError.cleanupAction = cleanupAction;
    }
    throw operationError;
  }
  const base = {
    schemaVersion: 1,
    outcome: dryRun ? "dry_run_complete" : "deploy_command_completed",
    lane,
    dryRun,
    commandExitZero,
    firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
    appCommit,
    targetConfigurationDigestSha256: validated.targetConfigurationDigestSha256,
    dotenvApplied: true,
    dotenvSha256: validated.sha256,
    dotenvKeyNames: validated.keyNames,
    rollout: validated.rollout,
    existingFunctionEnvironmentPolicy: "preserved_not_selected",
    selector: catalogFunctionSelector(lane),
    cleanupStatus,
    retryAllowed: false,
    ...(cleanupDirectory ? { cleanupDirectory, cleanupAction } : {}),
  };
  if (dryRun) {
    return {
      ...base,
      readbackStatus: "not_performed",
      closedDeploymentReceipt: false,
    };
  }
  try {
    const postDeploySourceContract = await refreshCandidateSourceContract();
    if (
      postDeploySourceContract.contractSha256 !==
      candidateSourceContract.contractSha256
    ) {
      throw new CatalogDeploymentGuardError(
        "CANDIDATE_FUNCTION_SOURCE_CHANGED_DURING_DEPLOY",
      );
    }
    const readback = await collectFunctionReadback({
      lane,
      validated,
      candidateSourceContract: postDeploySourceContract,
    });
    const closedDeploymentReceipt =
      readback.environmentMatches && cleanupStatus === "deleted";
    return {
      ...base,
      readback,
      readbackStatus: readback.environmentMatches ? "verified" : "needs_review",
      closedDeploymentReceipt,
      receiptStatus: closedDeploymentReceipt ? "verified" : "needs_review",
    };
  } catch (_) {
    return {
      ...base,
      readbackStatus: "needs_review",
      readbackCode: "CATALOG_FUNCTION_READBACK_FAILED",
      closedDeploymentReceipt: false,
      receiptStatus: "needs_review",
    };
  }
}

export function parseDeploymentGuardArguments(argv) {
  let lane = "";
  let expectedAppCommit = "";
  let expectedCurrentMainCommit = "";
  let candidateManifestPath = "";
  let expectedCandidateManifestSha256 = "";
  let receiptPath = "";
  let execute = false;
  let readbackOnly = false;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--execute") {
      if (execute) {
        throw new CatalogDeploymentGuardError(
          "CATALOG_DEPLOY_ARGUMENT_DUPLICATE",
        );
      }
      execute = true;
      continue;
    }
    if (argument === "--readback-only") {
      if (readbackOnly) {
        throw new CatalogDeploymentGuardError(
          "CATALOG_DEPLOY_ARGUMENT_DUPLICATE",
        );
      }
      readbackOnly = true;
      continue;
    }
    if (argument === "--lane") {
      if (lane || !argv[index + 1] || argv[index + 1].startsWith("--")) {
        throw new CatalogDeploymentGuardError(
          "CATALOG_DEPLOY_ARGUMENT_INVALID",
        );
      }
      lane = argv[index + 1];
      index += 1;
      continue;
    }
    if (argument === "--expected-app-commit") {
      if (
        expectedAppCommit ||
        !argv[index + 1] ||
        argv[index + 1].startsWith("--")
      ) {
        throw new CatalogDeploymentGuardError(
          "CATALOG_DEPLOY_ARGUMENT_INVALID",
        );
      }
      expectedAppCommit = argv[index + 1];
      index += 1;
      continue;
    }
    if (argument === "--expected-current-main-commit") {
      if (
        expectedCurrentMainCommit ||
        !argv[index + 1] ||
        argv[index + 1].startsWith("--")
      ) {
        throw new CatalogDeploymentGuardError(
          "CATALOG_DEPLOY_ARGUMENT_INVALID",
        );
      }
      expectedCurrentMainCommit = argv[index + 1];
      index += 1;
      continue;
    }
    if (argument === "--receipt-path") {
      if (receiptPath || !argv[index + 1] || argv[index + 1].startsWith("--")) {
        throw new CatalogDeploymentGuardError(
          "CATALOG_DEPLOY_ARGUMENT_INVALID",
        );
      }
      receiptPath = argv[index + 1];
      index += 1;
      continue;
    }
    if (argument === "--candidate-manifest-path") {
      if (
        candidateManifestPath ||
        !argv[index + 1] ||
        argv[index + 1].startsWith("--")
      ) {
        throw new CatalogDeploymentGuardError(
          "CATALOG_DEPLOY_ARGUMENT_INVALID",
        );
      }
      candidateManifestPath = argv[index + 1];
      index += 1;
      continue;
    }
    if (argument === "--expected-candidate-manifest-sha256") {
      if (
        expectedCandidateManifestSha256 ||
        !argv[index + 1] ||
        argv[index + 1].startsWith("--")
      ) {
        throw new CatalogDeploymentGuardError(
          "CATALOG_DEPLOY_ARGUMENT_INVALID",
        );
      }
      expectedCandidateManifestSha256 = argv[index + 1];
      index += 1;
      continue;
    }
    throw new CatalogDeploymentGuardError("CATALOG_DEPLOY_ARGUMENT_FORBIDDEN");
  }
  if (
    !new Set([...CATALOG_FUNCTION_LANES, ...CATALOG_POLICY_LANES]).has(lane)
  ) {
    throw new CatalogDeploymentGuardError("CATALOG_DEPLOY_LANE_INVALID");
  }
  if (!/^[a-f0-9]{40}$/.test(expectedAppCommit)) {
    throw new CatalogDeploymentGuardError("EXPECTED_APP_COMMIT_INVALID");
  }
  if (expectedCurrentMainCommit !== FROZEN_APP_MAIN_COMMIT) {
    throw new CatalogDeploymentGuardError(
      "EXPECTED_CURRENT_MAIN_COMMIT_INVALID",
    );
  }
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
    (!execute &&
      (receiptPath || candidateManifestPath || expectedCandidateManifestSha256))
  ) {
    throw new CatalogDeploymentGuardError(
      "CATALOG_DEPLOY_RECEIPT_EXECUTION_INVALID",
    );
  }
  if (readbackOnly && (!CATALOG_POLICY_LANES.includes(lane) || execute)) {
    throw new CatalogDeploymentGuardError("CATALOG_DEPLOY_ARGUMENT_FORBIDDEN");
  }
  return {
    lane,
    expectedAppCommit,
    expectedCurrentMainCommit,
    dryRun: !execute,
    execute,
    receiptPath: execute ? receiptPath : null,
    candidateManifestPath: execute ? candidateManifestPath : null,
    expectedCandidateManifestSha256: execute
      ? expectedCandidateManifestSha256
      : null,
    readbackOnly,
  };
}

async function readStandardInput() {
  const chunks = [];
  let length = 0;
  for await (const chunk of process.stdin) {
    length += chunk.length;
    if (length > MAX_DOTENV_BYTES) {
      throw new CatalogDeploymentGuardError("CATALOG_DOTENV_SIZE_INVALID");
    }
    chunks.push(Buffer.from(chunk));
  }
  const value = Buffer.concat(chunks).toString("utf8");
  chunks.forEach((chunk) => chunk.fill(0));
  return value;
}

async function main() {
  try {
    const options = parseDeploymentGuardArguments(process.argv.slice(2));
    if (options.execute) {
      throw new CatalogDeploymentGuardError(
        "PRODUCTION_CATALOG_DEPLOY_EXECUTOR_NOT_ENABLED",
      );
    }
    const policyLane = CATALOG_POLICY_LANES.includes(options.lane);
    if (
      process.stdin.isTTY &&
      options.lane !== "existing-code" &&
      !policyLane
    ) {
      throw new CatalogDeploymentGuardError("CATALOG_DOTENV_STDIN_REQUIRED");
    }
    const dotenvText =
      process.stdin.isTTY || policyLane ? "" : await readStandardInput();
    const result = policyLane
      ? await runGuardedCatalogPolicyDeployment(options)
      : await runGuardedCatalogDeployment({
          ...options,
          dotenvText,
        });
    if (result.receiptStatus === "needs_review") {
      throw new CatalogDeploymentGuardError(
        "CATALOG_DEPLOY_READBACK_NEEDS_REVIEW",
        { ambiguous: true, needsReview: true },
      );
    }
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } catch (error) {
    const safe =
      error instanceof CatalogDeploymentGuardError ||
      error instanceof ReconciliationOperatorError
        ? error
        : new CatalogDeploymentGuardError("CATALOG_DEPLOY_GUARD_FAILED");
    process.stderr.write(
      `${JSON.stringify({
        outcome: safe.needsReview ? "needs_review" : "blocked",
        code: safe.code,
        ambiguous: safe.ambiguous === true,
        ...(safe.needsReview ? { retryAllowed: false } : {}),
        ...(safe.cleanupStatus ? { cleanupStatus: safe.cleanupStatus } : {}),
        ...(safe.cleanupDirectory
          ? {
              cleanupDirectory: safe.cleanupDirectory,
              cleanupAction: safe.cleanupAction,
            }
          : {}),
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
